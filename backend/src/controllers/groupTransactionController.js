const GroupTransaction = require('../models/groupTransaction');
const User = require('../models/user');
const WalletTransaction = require('../models/walletTransaction');
const { FEATURES, hasFeature } = require('../utils/subscriptionFeatures');
const { sendGroupSettleOtp } = require('../utils/email/groupSettleOtp');
const { sendGroupLeaveRequestEmail } = require('../utils/email/groupLeaveRequestEmail');
const groupTransactionEmail = require('../utils/email/groupTransactionEmail');
const mongoose = require('mongoose');
const { logGroupActivity, logGroupActivityForAllMembers } = require('./activityController');
const { awardGiftCard, shouldAwardGiftCard } = require('./userGiftCardController');
const PDFDocument = require('pdfkit');
const { sendGroupReceiptEmail } = require('../utils/email/groupReceiptEmail');
const { processReferralRewardOnFirstCreation } = require('../utils/referralService');
const { validateCoinCreationAccess } = require('../utils/coinUsageGuard');
const { recordCoinLedgerEntry } = require('../utils/coinLedgerService');
const { getCoinPricing } = require('../utils/coinPricing');
const {
  INR,
  normalizeCurrency,
  enrichExpenseWithInr,
} = require('../utils/currencyConverter');
const { getSupportedCurrencyCodes } = require('../utils/supportedCurrencies');
const Notification = require('../models/notification');
const { sendToUser } = require('../services/notificationService');

const { isBlockedBy } = require('../utils/userHelpers');
const { getTodayRange } = require('../utils/dateHelpers');

const isSubscribed = (userId) => hasFeature(userId, FEATURES.GROUP_CREATION);
const hasGroupExpenseAccess = (userId) => hasFeature(userId, FEATURES.GROUP_EXPENSES);

// Helper function to process expenses and convert Object IDs to emails in addedBy field
async function processExpenses(expenses) {
  return await Promise.all(
    (expenses || []).map(async (expense) =>
      enrichExpenseWithInr({
        ...expense,
        currency: normalizeCurrency(expense.currency),
      })
    )
  );
}

function getLockedCurrencyForGroup(group, excludedExpenseId = null) {
  const remainingExpenses = (group.expenses || []).filter((expense) => {
    if (
      excludedExpenseId &&
      expense?._id?.toString() === excludedExpenseId.toString()
    ) {
      return false;
    }
    return true;
  });

  if (remainingExpenses.length === 0) {
    return null;
  }

  remainingExpenses.sort((a, b) => {
    const firstDate = new Date(a?.date || a?.createdAt || 0).getTime();
    const secondDate = new Date(b?.date || b?.createdAt || 0).getTime();
    return firstDate - secondDate;
  });

  const firstExpense = remainingExpenses[0];
  if (!firstExpense) {
    return null;
  }

  return normalizeCurrency(firstExpense.currency || INR);
}

function buildCurrencyLockError(lockedCurrency) {
  return `You must use ${lockedCurrency} for all expenses in this group because it was the currency used in the first expense here.`;
}

// Helper: check if all userIds exist in User collection
async function validateUsers(userIds) {
  const count = await User.countDocuments({ _id: { $in: userIds } });
  return count === userIds.length;
}

exports.createGroupWithCoins = async (req, res) => {
  const pricing = await getCoinPricing();
  const GROUP_COST = pricing.groupCreationCost;
  const GROUP_DAILY_LIMIT = 1;
  try {
    const { title, memberEmails, color, communityIds } = req.body;
    const validCommunityIds = Array.isArray(communityIds) ? communityIds.filter(Boolean) : (communityIds ? [communityIds] : []);
    const creator = await User.findById(req.user._id).select(
      'email blockedUsers lenDenCoins freeGroupsRemaining'
    );

    if (!creator) {
      return res.status(400).json({ error: 'Creator not found' });
    }

    const subscribed = await isSubscribed(creator._id);
    const { start, end } = getTodayRange();
    const todayCount = await GroupTransaction.countDocuments({
      creator: creator._id,
      createdAt: { $gte: start, $lte: end },
    });
    const accessError = validateCoinCreationAccess({
      subscribed,
      freeRemaining: creator.freeGroupsRemaining,
      dailyCount: todayCount,
      dailyLimit: GROUP_DAILY_LIMIT,
      dailyLimitMessage: 'Daily limit reached: You can create 1 group per day.',
      coinBalance: creator.lenDenCoins,
      coinCost: GROUP_COST,
      featureLabel: 'group creation',
    });
    if (accessError && accessError.error) {
      return res.status(accessError.status).json({ error: accessError.error });
    }
    const accessWarning = accessError?.warning;

    if (!title) {
      return res.status(400).json({ error: 'Title is required' });
    }
    if (!Array.isArray(memberEmails)) {
      return res.status(400).json({ error: 'memberEmails must be an array.' });
    }

    // Filter out creator's email, normalize to lowercase, de-duplicate
    const filteredMemberEmails = [...new Set(
      memberEmails
        .map(e => (e || '').toString().toLowerCase().trim())
        .filter(email => email && email !== creator.email.toLowerCase())
    )];

    // Find users by email
    const users = await User.find({ email: { $in: filteredMemberEmails } }).select(
      'email blockedUsers privacySettings'
    );
    if (users.length !== filteredMemberEmails.length) {
      return res.status(400).json({ error: 'One or more members do not exist' });
    }
    const skippedUsers = [];
    const allowedUsers = [];
    for (const member of users) {
      if (isBlockedBy(creator, member)) {
        return res.status(403).json({
          error: `You have blocked ${member.email}. Unblock to proceed.`,
        });
      }
      if (isBlockedBy(member, creator)) {
        return res.status(403).json({
          error: `You cannot add ${member.email} because they have blocked you.`,
        });
      }
      if (member.privacySettings?.allowDirectGroupAdd === false) {
        skippedUsers.push(member);
      } else {
        allowedUsers.push(member);
      }
    }

    const updatedCreator = await User.findOneAndUpdate(
      { _id: creator._id, lenDenCoins: { $gte: GROUP_COST } },
      { $inc: { lenDenCoins: -GROUP_COST } },
      { new: true }
    );
    if (!updatedCreator) {
      return res.status(400).json({ error: 'Insufficient LenDen coins to create this group.' });
    }
    creator.lenDenCoins = updatedCreator.lenDenCoins;
    await recordCoinLedgerEntry({
      userId: creator._id,
      direction: 'spent',
      coins: GROUP_COST,
      source: 'group_creation_with_coins',
      title: 'Group Created With Coins',
      description: `Spent ${GROUP_COST} LenDen coins to create the group "${title}".`,
      metadata: {
        title,
        memberCount: Array.isArray(memberEmails) ? memberEmails.length : 0,
      },
    });

    const memberIds = allowedUsers.map(u => u._id.toString());
    memberIds.unshift(creator._id.toString());

    const members = memberIds.map(id => ({ user: id }));
    const balances = memberIds.map(id => ({ user: id, balance: 0 }));
    const group = await GroupTransaction.create({ title, creator: creator._id, members, balances, color, communityIds: validCommunityIds });
    if (validCommunityIds.length > 0) {
      try {
        const Community = require('../models/community');
        await Community.updateMany({ _id: { $in: validCommunityIds } }, { $addToSet: { groups: group._id } });
      } catch (_) {}
    }
    let referralReward = null;
    try {
      referralReward = await processReferralRewardOnFirstCreation(creator._id);
    } catch (e) {
      console.error('Referral reward processing failed (non-fatal):', e);
    }
    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email name')
      .populate('creator', 'email');
    const groupObj = populatedGroup.toObject();
    groupObj.members = groupObj.members
      .filter(m => m.user != null)
      .map(m => ({ _id: m.user._id, email: m.user.email, joinedAt: m.joinedAt, leftAt: m.leftAt }));
    groupObj.creator = groupObj.creator
      ? { _id: groupObj.creator._id, email: groupObj.creator.email }
      : { _id: creator._id, email: creator.email };

    const groupCountWithCoins = await GroupTransaction.countDocuments({ creator: creator._id });
    let awardedCardWithCoins = null;
    if (shouldAwardGiftCard(creator._id, groupCountWithCoins, 3)) {
      awardedCardWithCoins = await awardGiftCard(creator._id, 'group');
    }

    res.status(201).json({
        message: "Group created successfully with LenDen coins",
        group: groupObj,
        lenDenCoins: creator.lenDenCoins,
        warning: accessWarning,
        referralReward,
        giftCardAwarded: awardedCardWithCoins ? true : false,
        awardedCard: awardedCardWithCoins,
        skippedUsers: skippedUsers.map(u => ({ email: u.email, reason: 'direct_add_restricted' })),
    });

    try {
      const creatorUser = await User.findById(creator._id).select('name email');
      const creatorName = creatorUser?.name || creatorUser?.email || 'Someone';
      for (const skipped of skippedUsers) {
        await Notification.create({
          sender: creator._id, senderModel: 'User',
          recipientType: 'specific-users', recipients: [skipped._id], recipientModel: 'User',
          message: `${creatorName} created a group "${title}" and invited you to join.`,
          category: 'group',
          deliveryStatus: 'sent', sentAt: new Date(),
        });
        sendToUser(User, skipped._id, {
          title: 'Group Invite',
          body: `${creatorName} invited you to join "${title}". Tap to view.`,
          data: { type: 'group_join_invite', groupId: group._id.toString(), groupTitle: title },
        }, { settingKey: 'groupNotifications' });
      }
      const creatorInfo = { creatorId: creator._id, creatorEmail: creator.email };
      await logGroupActivityForAllMembers('group_created_with_coins', group, {}, null, creatorInfo);
      groupTransactionEmail.sendGroupCreatedEmail(populatedGroup, creator);
    } catch (e) {
      console.error('Failed to log group activity or send email:', e);
    }
  } catch (err) {
    console.error('createGroupWithCoins error:', err);
    res.status(500).json({ error: err.message || 'Server error' });
  }
};

exports.createGroup = async (req, res) => {
  try {
    const { title, memberEmails, color, communityIds } = req.body;
    const validCommunityIds = Array.isArray(communityIds) ? communityIds.filter(Boolean) : (communityIds ? [communityIds] : []);
    const creator = await User.findById(req.user._id).select(
      'email blockedUsers'
    );

    if (!creator) {
      return res.status(400).json({ error: 'Creator not found' });
    }

    // Subscription is handled by subscription checks and free-attempts are enforced
    // by the `handleUsage('group')` middleware. No need to re-check here.

    if (!title) {
      return res.status(400).json({ error: 'Title is required' });
    }

    if (!(await isSubscribed(creator._id))) {
      const { start, end } = getTodayRange();
      const todayCount = await GroupTransaction.countDocuments({
        creator: creator._id,
        createdAt: { $gte: start, $lte: end },
      });
      if (todayCount >= 1) {
        return res.status(429).json({
          error: 'Daily limit reached: You can create 1 group per day.',
        });
      }
    }
    if (!Array.isArray(memberEmails)) {
      return res.status(400).json({ error: 'memberEmails must be an array.' });
    }

    // Filter out creator's email, normalize to lowercase, de-duplicate
    const filteredMemberEmails = [...new Set(
      memberEmails
        .map(e => (e || '').toString().toLowerCase().trim())
        .filter(email => email && email !== creator.email.toLowerCase())
    )];

    // Find users by email
    const users = await User.find({ email: { $in: filteredMemberEmails } }).select(
      'email blockedUsers privacySettings'
    );
    if (users.length !== filteredMemberEmails.length) {
      return res.status(400).json({ error: 'One or more members do not exist' });
    }
    const skippedUsers = [];
    const allowedUsers = [];
    for (const member of users) {
      if (isBlockedBy(creator, member)) {
        return res.status(403).json({
          error: `You have blocked ${member.email}. Unblock to proceed.`,
        });
      }
      if (isBlockedBy(member, creator)) {
        return res.status(403).json({
          error: `You cannot add ${member.email} because they have blocked you.`,
        });
      }
      if (member.privacySettings?.allowDirectGroupAdd === false) {
        skippedUsers.push(member);
      } else {
        allowedUsers.push(member);
      }
    }

    const memberIds = allowedUsers.map(u => u._id.toString());
    memberIds.unshift(creator._id.toString());

    const members = memberIds.map(id => ({ user: id }));
    const balances = memberIds.map(id => ({ user: id, balance: 0 }));
    const group = await GroupTransaction.create({ title, creator: creator._id, members, balances, color, communityIds: validCommunityIds });
    if (validCommunityIds.length > 0) {
      try {
        const Community = require('../models/community');
        await Community.updateMany({ _id: { $in: validCommunityIds } }, { $addToSet: { groups: group._id } });
      } catch (_) {}
    }
    let referralReward = null;
    try {
      referralReward = await processReferralRewardOnFirstCreation(creator._id);
    } catch (e) {
      console.error('Referral reward processing failed (non-fatal):', e);
    }

    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email name')
      .populate('creator', 'email');
    const groupObj = populatedGroup.toObject();
    groupObj.members = groupObj.members
      .filter(m => m.user != null)
      .map(m => ({ _id: m.user._id, email: m.user.email, joinedAt: m.joinedAt, leftAt: m.leftAt }));
    groupObj.creator = groupObj.creator
      ? { _id: groupObj.creator._id, email: groupObj.creator.email }
      : { _id: creator._id, email: creator.email };

    const groupCount = await GroupTransaction.countDocuments({ creator: creator._id });
    let awardedCard = null;
    if (shouldAwardGiftCard(creator._id, groupCount, 3)) {
      awardedCard = await awardGiftCard(creator._id, 'group');
    }

    res.status(201).json({
        message: "Group created successfully",
        group: groupObj,
        freeGroupsRemaining: creator.freeGroupsRemaining,
        referralReward,
        giftCardAwarded: awardedCard ? true : false,
        awardedCard: awardedCard,
        skippedUsers: skippedUsers.map(u => ({ email: u.email, reason: 'direct_add_restricted' })),
    });
    
    // Log activity for group creation - all members get notified
    try {
      const creatorInfo = {
        creatorId: creator._id,
        creatorEmail: creator.email
      };
      await logGroupActivityForAllMembers('group_created', group, {}, null, creatorInfo);
      groupTransactionEmail.sendGroupCreatedEmail(populatedGroup, creator);

      // Notify added members
      if (allowedUsers.length > 0) {
        const eligibleIds = allowedUsers.map(u => u._id);
        const eligible = await User.find({ _id: { $in: eligibleIds }, 'notificationSettings.groupNotifications': { $ne: false } }).select('_id');
        if (eligible.length > 0) {
          await Notification.create(eligible.map(u => ({
            sender: creator._id, senderModel: 'User', recipientType: 'specific-users',
            recipients: [u._id], recipientModel: 'User', category: 'group',
            message: `${creator.email} added you to the group "${title}".`,
          })));
          eligible.forEach(u => sendToUser(User, u._id, { title: 'Added to Group', body: `${creator.email} added you to the group "${title}".`, data: { type: 'group_created' } }, { settingKey: 'groupNotifications' }));
        }
      }
      // Notify skipped users  they have direct-add restricted but are invited to join
      const creatorUser = await User.findById(creator._id).select('name email');
      const creatorName = creatorUser?.name || creatorUser?.email || 'Someone';
      for (const skipped of skippedUsers) {
        await Notification.create({
          sender: creator._id, senderModel: 'User',
          recipientType: 'specific-users', recipients: [skipped._id], recipientModel: 'User',
          message: `${creatorName} created a group "${title}" and invited you to join.`,
          category: 'group',
          deliveryStatus: 'sent', sentAt: new Date(),
        });
        sendToUser(User, skipped._id, {
          title: 'Group Invite',
          body: `${creatorName} invited you to join "${title}". Tap to view.`,
          data: { type: 'group_join_invite', groupId: group._id.toString(), groupTitle: title },
        }, { settingKey: 'groupNotifications' });
      }
    } catch (e) {
      console.error('Failed to log group activity or send email:', e);
    }
  } catch (err) {
    console.error('createGroup error:', err);
    res.status(500).json({ error: err.message || 'Server error' });
  }
};

exports.sendGroupInvite = async (req, res) => {
  try {
    const { groupId } = req.params;
    const { emails } = req.body;
    if (!Array.isArray(emails) || emails.length === 0) {
      return res.status(400).json({ error: 'emails array required' });
    }

    const group = await GroupTransaction.findById(groupId).select('title members');
    if (!group) return res.status(404).json({ error: 'Group not found' });

    const isMember = group.members.some(
      m => !m.leftAt && m.user.toString() === req.user._id.toString(),
    );
    if (!isMember) return res.status(403).json({ error: 'Not a member of this group' });

    const inviter = await User.findById(req.user._id).select('name email');
    const inviterName = inviter?.name || inviter?.email || 'Someone';

    const normalizedEmails = emails.map(e => e.toString().toLowerCase().trim());
    const targets = await User.find({ email: { $in: normalizedEmails } }).select('_id email');

    for (const target of targets) {
      await Notification.create({
        sender: req.user._id, senderModel: 'User',
        recipientType: 'specific-users', recipients: [target._id], recipientModel: 'User',
        title: 'Group Invite',
        message: `${inviterName} invited you to join "${group.title}". Ask them for the join code or use the app to request an invite.`,
        category: 'group',
        deliveryStatus: 'sent', sentAt: new Date(),
      });
      sendToUser(User, target._id, {
        title: 'Group Invite',
        body: `${inviterName} invited you to join "${group.title}".`,
        data: { type: 'group_join_invite', groupId: groupId.toString(), groupTitle: group.title },
      }, { settingKey: 'groupNotifications' });
    }

    res.json({ sent: targets.length });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.addMember = async (req, res) => {
  try {
    const { groupId } = req.params;
    const email = (req.body.email || '').toLowerCase().trim();
    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });
    if (group.creator.toString() !== req.user._id.toString()) return res.status(403).json({ error: 'Only creator can add members' });

    const user = await User.findOne({ email });
    if (!user) return res.status(404).json({ error: 'User not found' });

    // Check if trying to add the group creator
    if (user._id.toString() === group.creator.toString()) {
      return res.status(400).json({ error: 'Group creator is already a member by default' });
    }

    // Check if user is already an active member (no action needed, clear error)
    if (group.members.some(m => m.user.toString() === user._id.toString() && !m.leftAt)) {
      return res.status(400).json({ error: 'User already a member' });
    }

    // Respect target user's group-add privacy setting only for genuinely new adds
    if (user.privacySettings?.allowDirectGroupAdd === false) {
      // Add to pendingInvites if not already there
      if (!group.pendingInvites.some(i => i.email === user.email.toLowerCase())) {
        group.pendingInvites.push({ email: user.email.toLowerCase(), invitedBy: req.user._id });
        await group.save();
      }
      // In-app notification
      try {
        const inviter = await User.findById(req.user._id).select('name email');
        const inviterName = inviter?.name || inviter?.email || 'Someone';
        await Notification.create({
          sender: req.user._id, senderModel: 'User',
          recipientType: 'specific-users', recipients: [user._id], recipientModel: 'User',
          title: 'Group Invite',
          message: `${inviterName} invited you to join "${group.title}". Use code ${group.joinCode ?? 'shared by admin'} to join.`,
          category: 'group', deliveryStatus: 'sent', sentAt: new Date(),
        });
        sendToUser(User, user._id, {
          title: 'Group Invite',
          body: `${inviterName} invited you to join "${group.title}". Tap to view.`,
          data: { type: 'group_join_invite', groupId: group._id.toString(), groupTitle: group.title },
        }, { settingKey: 'groupNotifications' });
      } catch (_) {}
      return res.json({ notified: true, message: 'User has restricted direct group additions. An invite notification has been sent  they can join using the group code.' });
    }
    
    // Check if user was previously removed and handle re-adding
    const existingMemberIndex = group.members.findIndex(m => m.user.toString() === user._id.toString());
    if (existingMemberIndex !== -1) {
      // User was previously in the group, reactivate them
      group.members[existingMemberIndex].leftAt = null;
      group.members[existingMemberIndex].joinedAt = new Date(); // Update join date
      
      // Check if balance entry exists, if not create one
      const existingBalance = group.balances.find(b => b.user.toString() === user._id.toString());
      if (!existingBalance) {
        group.balances.push({ user: user._id, balance: 0 });
      }
    } else {
      // User is completely new to the group
      group.members.push({ user: user._id, joinedAt: new Date() });
      group.balances.push({ user: user._id, balance: 0 });
    }
    await group.save();
    // Populate members and creator for response
    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    // Map members to include email
    const groupObj = populatedGroup.toObject();
    groupObj.members = groupObj.members.map(m => ({
      _id: m.user._id,
      email: m.user.email,
      joinedAt: m.joinedAt,
      leftAt: m.leftAt
    }));
    groupObj.creator = {
      _id: groupObj.creator._id,
      email: groupObj.creator.email
    };
    res.json({ group: groupObj });

    // Log activity for member addition - all members get notified
    try {
      const creatorInfo = {
        creatorId: req.user._id,
        creatorEmail: req.user.email
      };
      await logGroupActivityForAllMembers('member_added', group, {
        memberEmail: email
      }, null, creatorInfo);
      groupTransactionEmail.sendMemberAddedEmail(populatedGroup, email, req.user.email);

      // Notify the added member
      if (user.notificationSettings?.groupNotifications !== false) {
        await Notification.create({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [user._id], recipientModel: 'User', category: 'group',
          message: `${req.user.email} added you to the group "${group.title}".`,
        });
      }
      sendToUser(User, user._id, { title: 'Added to Group', body: `${req.user.email} added you to the group "${group.title}".`, data: { type: 'group_member_added' } }, { settingKey: 'groupNotifications' });
    } catch (e) {
      console.error('Failed to log group activity or send email:', e);
    }
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.removeMember = async (req, res) => {
  try {
    const { groupId } = req.params;
    const email = (req.body.email || '').toLowerCase().trim();
    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });
    if (group.creator.toString() !== req.user._id.toString()) return res.status(403).json({ error: 'Only creator can remove members' });

    const user = await User.findOne({ email });
    if (!user) return res.status(404).json({ error: 'User not found' });
    
    // Check if trying to remove the creator
    if (user._id.toString() === group.creator.toString()) {
      return res.status(400).json({ error: 'Cannot remove group creator' });
    }
    
    // Check if user is a member
    const memberIndex = group.members.findIndex(m => m.user.toString() === user._id.toString() && !m.leftAt);
    if (memberIndex === -1) return res.status(400).json({ error: 'User is not a member of this group' });
    
    // Check if user has pending balances
    const userBalance = group.balances.find(b => b.user.toString() === user._id.toString());
    if (userBalance && userBalance.balance !== 0) {
      return res.status(400).json({ error: 'Cannot remove member with pending balances. Please ask them to settle their balance first.' });
    }
    
    // Mark member as left
    group.members[memberIndex].leftAt = new Date();
    await group.save();
    
    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    const groupObj = populatedGroup.toObject();
    
    // Process expenses to convert Object IDs to emails in addedBy field
    const processedExpenses = await processExpenses(groupObj.expenses);
    
    groupObj.members = groupObj.members.map(m => ({
      _id: m.user._id,
      email: m.user.email,
      joinedAt: m.joinedAt,
      leftAt: m.leftAt
    }));
    groupObj.creator = {
      _id: groupObj.creator._id,
      email: groupObj.creator.email
    };
    groupObj.expenses = processedExpenses;
    
    res.json({ group: groupObj });
    
    // Log activity for member removal - all members get notified
    try {
      const creatorInfo = {
        creatorId: req.user._id,
        creatorEmail: req.user.email
      };
      await logGroupActivityForAllMembers('member_removed', group, {
        memberEmail: email
      }, null, creatorInfo);

      groupTransactionEmail.sendYouHaveBeenRemovedEmail(populatedGroup, email, req.user.email);
      groupTransactionEmail.sendMemberRemovedEmail(populatedGroup, email, req.user.email);

      // Notify the removed member in-app
      if (user.notificationSettings?.groupNotifications !== false) {
        await Notification.create({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [user._id], recipientModel: 'User', category: 'group',
          message: `You were removed from the group "${group.title}" by ${req.user.email}.`,
        });
      }
      sendToUser(User, user._id, { title: 'Removed from Group', body: `You were removed from the group "${group.title}".`, data: { type: 'group_member_removed' } }, { settingKey: 'groupNotifications' });
    } catch (e) {
      console.error('Failed to log group activity or send email:', e);
    }
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.addExpense = async (req, res) => {
  const pricing = await getCoinPricing();
  const EXPENSE_COST = pricing.groupExpenseCost;
  try {
    const { groupId } = req.params;
    const {
      description,
      amount,
      currency,
      splitType,
      split,
      date,
      selectedMembers,
      useCoins,
      category,
      addedBy: addedByInput,
    } = req.body;

    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });
    
    const userId = req.user._id;
    
    // Fetch user's email from database since req.user.email might not be populated
    const user = await User.findById(userId).select(
      'email lenDenCoins blockedUsers'
    );
    if (!user) return res.status(404).json({ error: 'User not found' });
    const userEmail = user.email;
    
    
    if (!group.members.some(m => m.user.toString() === userId.toString() && !m.leftAt)) return res.status(403).json({ error: 'Not a group member' });
    if (!description || !amount || amount <= 0) return res.status(400).json({ error: 'Description and positive amount required' });

    const normalizedCurrency = normalizeCurrency(currency);
    const supportedCurrencyCodes = await getSupportedCurrencyCodes();
    if (!supportedCurrencyCodes.includes(normalizedCurrency)) {
      return res.status(400).json({ error: 'Unsupported currency selected' });
    }

    const lockedCurrency = getLockedCurrencyForGroup(group);
    if (lockedCurrency && lockedCurrency !== normalizedCurrency) {
      return res.status(400).json({
        error: buildCurrencyLockError(lockedCurrency),
        lockedCurrency,
      });
    }

    if (!(await hasGroupExpenseAccess(userId))) {
      const { start, end } = getTodayRange();
      const todayExpenseCount = (group.expenses || []).filter((e) => {
        if (!e || !e.addedBy || !e.date) return false;
        const expenseDate = new Date(e.date);
        return (
          e.addedBy === userEmail &&
          expenseDate >= start &&
          expenseDate <= end
        );
      }).length;
      if (todayExpenseCount >= 3 && useCoins == true) {
        const accessError = validateCoinCreationAccess({
          subscribed: false,
          freeRemaining: 0,
          dailyCount: todayExpenseCount,
          dailyLimit: 3,
          dailyLimitMessage:
              'Daily limit reached: You can add 3 expenses per group per day.',
          coinBalance: user.lenDenCoins,
          coinCost: EXPENSE_COST,
          featureLabel: 'group expense',
        });
        if (accessError && accessError.error) {
          return res.status(accessError.status).json({ error: accessError.error });
        }

        const updatedCoinUser = await User.findOneAndUpdate(
          { _id: user._id, lenDenCoins: { $gte: EXPENSE_COST } },
          { $inc: { lenDenCoins: -EXPENSE_COST } },
          { new: true }
        );
        if (!updatedCoinUser) {
          return res.status(400).json({
            error: 'Insufficient LenDen coins to add this expense.',
          });
        }
        user.lenDenCoins = updatedCoinUser.lenDenCoins;
        await recordCoinLedgerEntry({
          userId: user._id,
          direction: 'spent',
          coins: EXPENSE_COST,
          source: 'group_expense_with_coins',
          title: 'Group Expense Added With Coins',
          description: `Spent ${EXPENSE_COST} LenDen coins to add an extra expense in group "${group.title}".`,
          metadata: {
            groupId: group._id,
            groupTitle: group.title,
            amount,
            currency: normalizedCurrency,
          },
        });
      } else if (todayExpenseCount >= 3) {
        return res.status(429).json({
          error:
            'Daily limit reached: You can add 3 expenses per group per day.',
        });
      }
    }
    
    // Validate selected members
    if (!selectedMembers || !Array.isArray(selectedMembers) || selectedMembers.length === 0) {
      return res.status(400).json({ error: 'At least one member must be selected for the expense' });
    }
    
    // Get active members and validate selected members
    const activeMembers = group.members.filter(m => !m.leftAt);
    
    // Populate members if not already populated
    let populatedActiveMembers = activeMembers;
    if (activeMembers.length > 0 && typeof activeMembers[0].user === 'object' && !activeMembers[0].user.email) {
      // Members are not populated, we need to populate them
      const populatedGroup = await GroupTransaction.findById(groupId)
        .populate('members.user', 'email');
      populatedActiveMembers = populatedGroup.members.filter(m => !m.leftAt);
    }
    
    const activeMemberEmails = populatedActiveMembers.map(m => {
      if (m.user && typeof m.user === 'object' && m.user.email) {
        return m.user.email;
      }
      return null;
    }).filter(email => email !== null);
    
    
    // Validate that all selected members are active members
    const invalidMembers = selectedMembers.filter(email => !activeMemberEmails.includes(email));
    if (invalidMembers.length > 0) {
      return res.status(400).json({ error: `Invalid members selected: ${invalidMembers.join(', ')}` });
    }

    // Resolve addedBy  must be an active group member (defaults to requesting user)
    if (addedByInput && !activeMemberEmails.includes(addedByInput)) {
      return res.status(400).json({ error: `addedBy member "${addedByInput}" is not an active group member` });
    }
    const effectiveAddedBy = addedByInput || userEmail;
    
    let splitArr = [];
    
    if (splitType === 'equal') {
      // Split equally among selected members only
      const per = parseFloat((amount / selectedMembers.length).toFixed(2));
      let total = per * selectedMembers.length;
      let diff = parseFloat((amount - total).toFixed(2));
      
      // Create split array for selected members only
      splitArr = selectedMembers.map((email, i) => {
        const member = populatedActiveMembers.find(m => {
          if (m.user && typeof m.user === 'object' && m.user.email) {
            return m.user.email === email;
          }
          return false;
        });
        if (member) {
          return { user: member.user._id || member.user, amount: per + (i === 0 ? diff : 0) };
        }
        return null;
      }).filter(item => item !== null);
      
      
    } else if (splitType === 'custom') {
      if (!Array.isArray(split) || split.length === 0) {
        return res.status(400).json({ error: 'Custom split requires split data for each selected member' });
      }
      
      // Validate that split amounts sum to total amount
      const totalSplitAmount = split.reduce((sum, item) => sum + (item.amount || 0), 0);
      if (Math.abs(totalSplitAmount - amount) > 0.01) { // Allow small floating point differences
        return res.status(400).json({ error: `Split amounts (${totalSplitAmount}) must sum to total amount (${amount})` });
      }
      
      // Convert email-based split to user ID-based split
      splitArr = [];
      for (const splitItem of split) {
        const member = populatedActiveMembers.find(m => {
          if (m.user && typeof m.user === 'object' && m.user.email) {
            return m.user.email === splitItem.user;
          }
          return false;
        });
        
        if (!member) {
          return res.status(400).json({ error: `Member with email ${splitItem.user} not found in selected members` });
        }
        
        if (splitItem.amount <= 0) {
          return res.status(400).json({ error: `Amount for ${splitItem.user} must be greater than 0` });
        }
        
        splitArr.push({
          user: member.user._id || member.user,
          amount: splitItem.amount
        });
      }
      
    } else {
      return res.status(400).json({ error: 'Invalid split type' });
    }
    
    // Add expense with selected members
    const expenseData = {
      description,
      amount,
      currency: normalizedCurrency,
      addedBy: effectiveAddedBy,
      date: date ? new Date(date) : new Date(),
      category: category || 'other',
      selectedMembers: selectedMembers,
      split: splitArr
    };

    group.expenses.push(expenseData);

    // Update balances - only for selected members (create entry if missing)
    splitArr.forEach(s => {
      let bal = group.balances.find(b => b.user.toString() === s.user.toString());
      if (!bal) { bal = { user: s.user, balance: 0 }; group.balances.push(bal); }
      bal.balance += s.amount;
    });
    // Credit the effective payer (may differ from requesting user)
    const payerMember = populatedActiveMembers.find(
      m => m.user && typeof m.user === 'object' && m.user.email === effectiveAddedBy
    );
    const payerUserId = payerMember ? (payerMember.user._id || payerMember.user) : userId;
    let payerBal = group.balances.find(b => b.user.toString() === payerUserId.toString());
    if (!payerBal) { payerBal = { user: payerUserId, balance: 0 }; group.balances.push(payerBal); }
    payerBal.balance -= amount;
    
    await group.save();
    
    // Return populated group data
    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    const groupObj = populatedGroup.toObject();
    
    // Process expenses to convert Object IDs to emails in addedBy field
    const processedExpenses = await processExpenses(groupObj.expenses);
    
    groupObj.members = groupObj.members.map(m => ({
      _id: m.user._id,
      email: m.user.email,
      joinedAt: m.joinedAt,
      leftAt: m.leftAt
    }));
    groupObj.creator = {
      _id: groupObj.creator._id,
      email: groupObj.creator.email
    };
    groupObj.expenses = processedExpenses;
    
    res.json({ group: groupObj });
    
    // Log activity for expense addition - all members get notified
    try {
      const creatorInfo = {
        creatorId: userId,
        creatorEmail: req.user.email
      };
      await logGroupActivityForAllMembers('expense_added', group, {
        expenseDescription: description,
        expenseAmount: amount,
        currency: normalizedCurrency,
      }, null, creatorInfo);
      groupTransactionEmail.sendExpenseAddedEmail(populatedGroup, expenseData, userEmail);

      // Notify all active members except the adder
      const adderIdStr = userId.toString();
      const addExpenseMemberIds = populatedGroup.members
        .filter(m => !m.leftAt && m.user._id.toString() !== adderIdStr)
        .map(m => m.user._id);
      if (addExpenseMemberIds.length > 0) {
        const eligible = await User.find({ _id: { $in: addExpenseMemberIds }, 'notificationSettings.groupNotifications': { $ne: false } }).select('_id');
        if (eligible.length > 0) {
          await Notification.create(eligible.map(u => ({
            sender: userId, senderModel: 'User', recipientType: 'specific-users',
            recipients: [u._id], recipientModel: 'User', category: 'group',
            message: `${userEmail} added an expense "${description}" of Rs.${amount} to group "${group.title}".`,
          })));
          eligible.forEach(u => sendToUser(User, u._id, { title: 'New Group Expense', body: `${userEmail} added an expense "${description}" of Rs.${amount} to group "${group.title}".`, data: { type: 'group_expense_added' } }, { settingKey: 'groupNotifications' }));
        }
      }
    } catch (e) {
      console.error('Failed to log group activity or send email:', e);
    }
  } catch (err) {
    console.error('Error in addExpense:', err);
    if (err.name === 'VersionError') {
      return res.status(409).json({
        error: 'This group was updated by someone else at the same time. Please try again.',
      });
    }
    res.status(500).json({ error: 'Server error' });
  }
};

exports.requestLeave = async (req, res) => {
  try {
    const { groupId } = req.params;
    const userId = req.user._id;
    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });
    if (!group.members.some(m => m.user.toString() === userId.toString() && !m.leftAt)) return res.status(403).json({ error: 'Not a group member' });
    if (!group.canRemoveMember(userId)) {
      if (!group.pendingLeaves.some(l => l.user.toString() === userId.toString())) {
        group.pendingLeaves.push({ user: userId });
        await group.save();
        // Send email to group creator (mock)
        // ...
      }
      return res.status(400).json({ error: 'Settle your balance before leaving. Request sent to group creator.' });
    }
    // Mark as left
    const member = group.members.find(m => m.user.toString() === userId.toString() && !m.leftAt);
    if (member) member.leftAt = new Date();
    await group.save();
    res.json({ group });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.settleBalance = async (req, res) => {
  try {
    const { groupId } = req.params;
    const { userId } = req.body; // user to settle
    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });
    if (group.creator.toString() !== req.user._id.toString()) return res.status(403).json({ error: 'Only creator can settle balances' });
    // Send OTP to creator's email
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    group._pendingOtp = { userId, otp, createdAt: new Date() };
    await sendGroupSettleOtp(req.user.email, otp);
    await group.save();
    res.json({ message: 'OTP sent to your email' });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.otpVerifySettle = async (req, res) => {
  try {
    const { groupId } = req.params;
    const { userId, otp } = req.body;
    const group = await GroupTransaction.findById(groupId);
    if (!group || !group._pendingOtp) return res.status(400).json({ error: 'No pending OTP' });
    const OTP_EXPIRY_MS = 10 * 60 * 1000;
    if (Date.now() - new Date(group._pendingOtp.createdAt).getTime() > OTP_EXPIRY_MS) {
      group._pendingOtp = undefined;
      await group.save();
      return res.status(400).json({ error: 'OTP expired. Please request a new OTP.' });
    }
    if (group._pendingOtp.userId !== userId || group._pendingOtp.otp !== otp) return res.status(400).json({ error: 'Invalid OTP' });
    // Settle balance
    const bal = group.balances.find(b => b.user.toString() === userId.toString());
    if (bal) bal.balance = 0;
    // Remove pending leave if any
    group.pendingLeaves = group.pendingLeaves.filter(l => l.user.toString() !== userId.toString());
    group._pendingOtp = undefined;
    await group.save();
    res.json({ group });

    // Notify the member whose balance was zeroed
    User.findById(userId).select('notificationSettings').then(member => {
      if (member?.notificationSettings?.groupNotifications !== false) {
        return Notification.create({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [userId], recipientModel: 'User', category: 'group',
          message: 'Your group balance has been settled by the group admin.',
        });
      }
    }).catch(() => {});
    sendToUser(User, userId, { title: 'Balance Settled', body: 'Your group balance has been settled by the group admin.', data: { type: 'group_balance_settled' } }, { settingKey: 'groupNotifications' });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// Get all groups for the logged-in user (as creator or member)
exports.getUserGroups = async (req, res) => {
  try {
    const userId = req.user._id;
    const userEmail = req.user.email;
    const { search, status = 'all', favouritesOnly } = req.query;

    // Base query: user is creator or member (including left members)
    const baseQuery = {
      $or: [
        { creator: userId },
        { 'members.user': userId },
      ],
    };

    // Status filter (joined vs left)
    if (status === 'joined') {
      baseQuery['members.user'] = userId;
      baseQuery['members.leftAt'] = null;
      delete baseQuery.$or;
    } else if (status === 'left') {
      // User must be a member with leftAt set
      baseQuery['members.user'] = userId;
      baseQuery['members.leftAt'] = { $ne: null };
      delete baseQuery.$or;
    }

    let groups = await GroupTransaction.find(baseQuery)
      .populate('members.user', 'email name profileImage')
      .populate('creator', 'email name profileImage')
      .sort({ createdAt: -1 });

    const createdGroupsCount = groups.filter(
      (g) => g.creator && g.creator._id.toString() === userId.toString()
    ).length;

    // Map to summary format with computed fields
    let groupSummaries = await Promise.all(
      groups.map(async (g) => {
        const obj = g.toObject();

        // Process expenses to convert Object IDs to emails in addedBy field
        const processedExpenses = await processExpenses(obj.expenses);
        const totalAmountInr = processedExpenses.reduce(
          (sum, expense) => sum + Number(expense.amountInr || 0),
          0
        );

        // Determine userStatus based on member entry
        const myMemberEntry = (obj.members || []).find(
          (m) => m && m.user && m.user._id && m.user._id.toString() === userId.toString()
        );
        const userStatus = myMemberEntry && myMemberEntry.leftAt ? 'left' : 'joined';

        // Compute userPendingBalance: sum of unsettled split amounts for this user
        let userPendingBalance = 0;
        for (const expense of processedExpenses) {
          for (const splitItem of expense.split || []) {
            const splitUserId =
              splitItem.user?._id?.toString?.() ||
              splitItem.user?.toString?.() ||
              '';
            if (splitUserId === userId.toString() && !splitItem.settled) {
              userPendingBalance += Number(splitItem.amountInr || splitItem.amount || 0);
            }
          }
        }

        return {
          _id: obj._id,
          title: obj.title,
          description: obj.description || '',
          groupImageUrl: `${req.protocol}://${req.get('host')}/api/group-transactions/${obj._id}/image?v=${obj.groupImage ? new Date(obj.updatedAt).getTime() : '0'}`,
          creator: obj.creator
            ? {
                _id: obj.creator._id,
                email: obj.creator.email,
                name: obj.creator.name || '',
                profileImage: obj.creator.profileImage
                  ? `${req.protocol}://${req.get('host')}/api/users/${obj.creator._id}/profile-image`
                  : null,
              }
            : null,
          members: (obj.members || [])
            .map((m) => {
              if (m && m.user) {
                return {
                  _id: m.user._id,
                  email: m.user.email,
                  name: m.user.name || '',
                  role: m.role || 'member',
                  joinedAt: m.joinedAt,
                  leftAt: m.leftAt,
                  profileImage: m.user.profileImage
                    ? `${req.protocol}://${req.get('host')}/api/users/${m.user._id}/profile-image`
                    : null,
                };
              }
              return null;
            })
            .filter((m) => m !== null),
          expenses: processedExpenses,
          totalExpenses: processedExpenses.length,
          totalAmountInr: Number(totalAmountInr.toFixed(2)),
          balances: obj.balances || [],
          memberPayments: obj.memberPayments || [],
          color: obj.color,
          favourite: obj.favourite || [],
          messageCount: obj.messageCount || 0,
          createdAt: obj.createdAt,
          updatedAt: obj.updatedAt,
          userStatus,
          userPendingBalance: Number(userPendingBalance.toFixed(2)),
          joinCode: obj.joinCode || null,
          pendingInvites: (obj.pendingInvites || []).map(i => ({ email: i.email, invitedAt: i.invitedAt })),
        };
      })
    );

    // Apply favourites filter
    if (favouritesOnly === 'true') {
      groupSummaries = groupSummaries.filter(
        (g) =>
          (g.favourite || []).includes(userEmail) ||
          (g.favourite || []).some(
            (f) => f && f.toString() === userId.toString()
          )
      );
    }

    // Apply search filter
    if (search && search.trim()) {
      const q = search.trim().toLowerCase();
      groupSummaries = groupSummaries.filter((g) => {
        if ((g.title || '').toLowerCase().includes(q)) return true;
        if ((g.description || '').toLowerCase().includes(q)) return true;
        for (const m of g.members || []) {
          if ((m.email || '').toLowerCase().includes(q)) return true;
        }
        for (const e of g.expenses || []) {
          if ((e.description || '').toLowerCase().includes(q)) return true;
        }
        return false;
      });
    }

    // Apply status filter post-processing if needed (handles edge case where base query may return extra)
    if (status === 'joined') {
      groupSummaries = groupSummaries.filter((g) => g.userStatus === 'joined');
    } else if (status === 'left') {
      groupSummaries = groupSummaries.filter((g) => g.userStatus === 'left');
    }

    res.json({
      groups: groupSummaries,
      totalGroups: groupSummaries.length,
      createdGroupsCount,
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getGroupById = async (req, res) => {
  try {
    const userId = req.user._id;
    const { groupId } = req.params;
    const g = await GroupTransaction.findById(groupId)
      .populate('members.user', 'email name')
      .populate('creator', 'email');
    if (!g) return res.status(404).json({ error: 'Group not found' });
    const obj = g.toObject();
    const processedExpenses = await processExpenses(obj.expenses);
    const totalAmountInr = processedExpenses.reduce((sum, e) => sum + Number(e.amountInr || 0), 0);
    const myMemberEntry = (obj.members || []).find(
      (m) => m && m.user && m.user._id && m.user._id.toString() === userId.toString()
    );
    const userStatus = myMemberEntry && myMemberEntry.leftAt ? 'left' : 'joined';
    let userPendingBalance = 0;
    for (const expense of processedExpenses) {
      for (const splitItem of expense.split || []) {
        const splitUserId = splitItem.user?._id?.toString?.() || splitItem.user?.toString?.() || '';
        if (splitUserId === userId.toString() && !splitItem.settled) {
          userPendingBalance += Number(splitItem.amountInr || splitItem.amount || 0);
        }
      }
    }
    res.json({
      _id: obj._id,
      title: obj.title,
      description: obj.description || '',
      groupImageUrl: obj.groupImage
        ? `${req.protocol}://${req.get('host')}/api/group-transactions/${obj._id}/image?v=${new Date(obj.updatedAt).getTime()}`
        : null,
      creator: obj.creator ? { _id: obj.creator._id, email: obj.creator.email } : null,
      members: (obj.members || [])
        .map((m) => m && m.user ? { _id: m.user._id, email: m.user.email, name: m.user.name || '', joinedAt: m.joinedAt, leftAt: m.leftAt } : null)
        .filter((m) => m !== null),
      expenses: processedExpenses,
      totalExpenses: processedExpenses.length,
      totalAmountInr: Number(totalAmountInr.toFixed(2)),
      balances: obj.balances || [],
      memberPayments: obj.memberPayments || [],
      color: obj.color,
      favourite: obj.favourite || [],
      messageCount: obj.messageCount || 0,
      createdAt: obj.createdAt,
      updatedAt: obj.updatedAt,
      userStatus,
      userPendingBalance: Number(userPendingBalance.toFixed(2)),
      joinCode: obj.joinCode || null,
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.toggleGroupFavourite = async (req, res) => {
  try {
    const { groupId } = req.params;
    const email = (req.body.email || '').toLowerCase().trim();

    if (!email) {
      return res.status(400).json({ error: 'Email is required' });
    }

    const group = await GroupTransaction.findById(groupId);

    if (!group) {
      return res.status(404).json({ error: 'Group not found' });
    }

    const user = await User.findOne({ email });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Check if user is a member of the group
    const isMember = group.members.some(member => member.user.toString() === user._id.toString() && !member.leftAt);
    if (!isMember) {
      return res.status(403).json({ error: 'Only group members can favourite a group' });
    }

    const favouriteIndex = group.favourite.indexOf(email);

    if (favouriteIndex > -1) {
      // Remove from favourites
      group.favourite.splice(favouriteIndex, 1);
    } else {
      // Add to favourites
      group.favourite.push(email);
    }

    await group.save();

    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email')
      .populate('creator', 'email');

    const groupObj = populatedGroup.toObject();
    groupObj.members = groupObj.members.map(m => ({
      _id: m.user._id,
      email: m.user.email,
      joinedAt: m.joinedAt,
      leftAt: m.leftAt
    }));
    groupObj.creator = {
      _id: groupObj.creator._id,
      email: groupObj.creator.email
    };

    res.json({ group: groupObj });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.updateGroupColor = async (req, res) => {
  try {
    const { groupId } = req.params;
    const { color } = req.body;
    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });
    if (group.creator.toString() !== req.user._id.toString()) return res.status(403).json({ error: 'Only creator can update color' });
    group.color = color || '#2196F3';
    await group.save();
    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    const groupObj = populatedGroup.toObject();
    
    // Process expenses to convert Object IDs to emails in addedBy field
    const processedExpenses = await processExpenses(groupObj.expenses);
    
    groupObj.members = groupObj.members.map(m => ({
      _id: m.user._id,
      email: m.user.email,
      joinedAt: m.joinedAt,
      leftAt: m.leftAt
    }));
    groupObj.creator = {
      _id: groupObj.creator._id,
      email: groupObj.creator.email
    };
    groupObj.expenses = processedExpenses;
    
    res.json({ group: groupObj });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.uploadGroupImage = async (req, res) => {
  try {
    const { groupId } = req.params;
    if (!req.file) return res.status(400).json({ error: 'No image file provided' });

    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });

    const userId = req.user._id;
    if (!group.members.some(m => m.user.toString() === userId.toString() && !m.leftAt)) {
      return res.status(403).json({ error: 'Not an active group member' });
    }

    group.groupImage = req.file.buffer;
    group.groupImageMimeType = req.file.mimetype || 'image/jpeg';
    await group.save();

    res.json({
      groupImageUrl: `${req.protocol}://${req.get('host')}/api/group-transactions/${group._id}/image?v=${group.updatedAt.getTime()}`,
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

const _groupFallbackPool = [
  'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=800&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1522071820081-009f0129c71c?w=800&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1543269865-cbf427effbad?w=800&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1491438590914-bc09fcaaf77a?w=800&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1517048676732-d65bc937f952?w=800&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1521737604893-d14cc237f11d?w=800&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1574957831710-f3c2292ad6e0?w=800&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1517694712202-14dd9538aa97?w=800&fit=crop&auto=format',
];

function _groupIdHash(id) {
  const s = String(id || '');
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return h;
}

exports.getGroupImage = async (req, res) => {
  try {
    const group = await GroupTransaction.findById(req.params.groupId).select(
      'groupImage groupImageMimeType'
    );
    if (!group) return res.status(404).send('Not found');
    if (!group.groupImage) {
      return res.redirect(_groupFallbackPool[_groupIdHash(req.params.groupId) % _groupFallbackPool.length]);
    }
    res.set('Content-Type', group.groupImageMimeType || 'image/jpeg');
    res.send(group.groupImage);
  } catch (err) {
    res.status(500).send('Error');
  }
};

exports.removeGroupImage = async (req, res) => {
  try {
    const { groupId } = req.params;
    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });

    const userId = req.user._id;
    if (!group.members.some(m => m.user.toString() === userId.toString() && !m.leftAt)) {
      return res.status(403).json({ error: 'Not an active group member' });
    }

    group.groupImage = null;
    group.groupImageMimeType = '';
    await group.save();
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// Delete group (only creator)
exports.deleteGroup = async (req, res) => {
  try {
    const { groupId } = req.params;
    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });
    if (group.creator.toString() !== req.user._id.toString()) return res.status(403).json({ error: 'Only creator can delete group' });

    // Collect active member IDs before deletion so we can notify them after
    const activeMemberIds = group.members
      .filter(m => !m.leftAt && m.user.toString() !== req.user._id.toString())
      .map(m => m.user);

    await GroupTransaction.findByIdAndDelete(groupId);
    res.json({ message: 'Group deleted successfully' });

    if (activeMemberIds.length > 0) {
      User.find({ _id: { $in: activeMemberIds }, 'notificationSettings.groupNotifications': { $ne: false } })
        .select('_id').then(eligible => {
          if (eligible.length > 0) {
            Notification.create(eligible.map(u => ({
              sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
              recipients: [u._id], recipientModel: 'User', category: 'group',
              message: `The group "${group.title}" was deleted by ${req.user.email}.`,
            })));
            eligible.forEach(u => sendToUser(User, u._id, { title: 'Group Deleted', body: `The group "${group.title}" was deleted by ${req.user.email}.`, data: { type: 'group_deleted' } }, { settingKey: 'groupNotifications' }));
          }
        }).catch(() => {});
    }
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// Leave group (members only, not creator)
exports.leaveGroup = async (req, res) => {
  try {
    const { groupId } = req.params;
    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });
    
    // Check if user is the creator
    if (group.creator.toString() === req.user._id.toString()) {
      return res.status(400).json({ error: 'Group creator cannot leave. Use delete group instead.' });
    }
    
    // Check if user is a member
    const memberIndex = group.members.findIndex(m => m.user.toString() === req.user._id.toString() && !m.leftAt);
    if (memberIndex === -1) return res.status(400).json({ error: 'You are not a member of this group' });
    
    // Calculate user's total split amount (pending balance) - excluding settled amounts
    let userBalance = 0;
    for (let expense of group.expenses) {
      for (let splitItem of expense.split) {
        if (splitItem.user.toString() === req.user._id.toString()) {
          // Only include unsettled amounts
          if (!splitItem.settled) {
            userBalance += splitItem.amount;
          }
        }
      }
    }
    
    // Check if user has pending balances
    if (userBalance !== 0) {
      return res.status(400).json({
        error: 'Cannot leave group with pending balances. Please settle your balance first or send a leave request to the group creator.',
        userBalance: userBalance
      });
    }
    
    // Mark member as left
    group.members[memberIndex].leftAt = new Date();
    await group.save();
    
    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    const groupObj = populatedGroup.toObject();
    
    // Process expenses to convert Object IDs to emails in addedBy field
    const processedExpenses = await processExpenses(groupObj.expenses);
    
    groupObj.members = groupObj.members.map(m => ({
      _id: m.user._id,
      email: m.user.email,
      joinedAt: m.joinedAt,
      leftAt: m.leftAt
    }));
    groupObj.creator = {
      _id: groupObj.creator._id,
      email: groupObj.creator.email
    };
    groupObj.expenses = processedExpenses;
    
    res.json({ group: groupObj });

    logGroupActivity(req.user._id, 'group_left', group, {}).catch(() => {});

    // Send email + notify group creator
    try {
      groupTransactionEmail.sendMemberLeftEmail(populatedGroup, req.user.email);
      User.findById(group.creator).select('notificationSettings').then(creatorUser => {
        if (creatorUser?.notificationSettings?.groupNotifications !== false) {
          return Notification.create({
            sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
            recipients: [group.creator], recipientModel: 'User', category: 'group',
            message: `${req.user.email} left the group "${group.title}".`,
          });
        }
      }).catch(() => {});
      sendToUser(User, group.creator, { title: 'Member Left Group', body: `${req.user.email} left the group "${group.title}".`, data: { type: 'group_member_left' } }, { settingKey: 'groupNotifications' });
    } catch (e) {
      console.error('Failed to send member left email:', e);
    }
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// Delete expense (only creator)
exports.deleteExpense = async (req, res) => {
  try {
    const { groupId, expenseId } = req.params;
    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });
    if (group.creator.toString() !== req.user._id.toString()) return res.status(403).json({ error: 'Only creator can delete expenses' });
    
    // Find and remove the expense
    const expenseIndex = group.expenses.findIndex(e => e._id.toString() === expenseId);
    if (expenseIndex === -1) return res.status(404).json({ error: 'Expense not found' });
    
    // Store expense details before removal for activity logging
    const deletedExpense = group.expenses[expenseIndex];
    
    // Remove the expense
    group.expenses.splice(expenseIndex, 1);
    await group.save();
    
    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    const groupObj = populatedGroup.toObject();
    
    // Process expenses to convert Object IDs to emails in addedBy field
    const processedExpenses = await processExpenses(groupObj.expenses);
    
    groupObj.members = groupObj.members.map(m => ({
      _id: m.user._id,
      email: m.user.email,
      joinedAt: m.joinedAt,
      leftAt: m.leftAt
    }));
    groupObj.creator = {
      _id: groupObj.creator._id,
      email: groupObj.creator.email
    };
    groupObj.expenses = processedExpenses;
    
    res.json({ group: groupObj });
    
    // Log activity for expense deletion - all members get notified
    try {
      const creatorInfo = {
        creatorId: req.user._id,
        creatorEmail: req.user.email
      };
      await logGroupActivityForAllMembers('expense_deleted', group, {
        expenseDescription: deletedExpense.description,
        expenseAmount: deletedExpense.amount,
        currency: normalizeCurrency(deletedExpense.currency),
      }, null, creatorInfo);
      groupTransactionEmail.sendExpenseDeletedEmail(populatedGroup, deletedExpense, req.user.email);

      // Notify all active members except the deleter
      const deleterIdStr = req.user._id.toString();
      const memberIds = populatedGroup.members
        .filter(m => !m.leftAt && m.user._id.toString() !== deleterIdStr)
        .map(m => m.user._id);
      if (memberIds.length > 0) {
        const eligible = await User.find({ _id: { $in: memberIds }, 'notificationSettings.groupNotifications': { $ne: false } }).select('_id');
        if (eligible.length > 0) {
          await Notification.create(eligible.map(u => ({
            sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
            recipients: [u._id], recipientModel: 'User', category: 'group',
            message: `${req.user.email} deleted the expense "${deletedExpense.description}" from group "${group.title}".`,
          })));
          eligible.forEach(u => sendToUser(User, u._id, { title: 'Expense Deleted', body: `${req.user.email} deleted the expense "${deletedExpense.description}" from group "${group.title}".`, data: { type: 'group_expense_deleted' } }, { settingKey: 'groupNotifications' }));
        }
      }
    } catch (e) {
      console.error('Failed to log group activity or send email:', e);
    }
  } catch (err) {
    if (err.name === 'VersionError') {
      return res.status(409).json({
        error: 'This group was updated by someone else at the same time. Please try again.',
      });
    }
    res.status(500).json({ error: 'Server error' });
  }
};

// Edit expense (only the person who created the expense)
exports.editExpense = async (req, res) => {
  try {
    const { groupId, expenseId } = req.params;
    const {
      description,
      amount,
      currency,
      selectedMembers,
      splitType,
      customSplitAmounts,
      date,
      category,
    } = req.body;
    // Handle both user and admin tokens (different field names)
    let userEmail = req.user.email;
    const userId = req.user._id;
    
    // Debug: Check what's in req.user
    
    // If email is not in token, fetch it from database
    if (!userEmail) {
      const User = require('../models/user');
      const Admin = require('../models/admin');
      
      // Try to find user first, then admin
      let user = await User.findById(userId);
      if (user) {
        userEmail = user.email;
      } else {
        let admin = await Admin.findById(userId);
        if (admin) {
          userEmail = admin.email;
        }
      }
    }
    
    const group = await GroupTransaction.findById(groupId)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    if (!group) return res.status(404).json({ error: 'Group not found' });
    
    // Find the expense
    const expenseIndex = group.expenses.findIndex(e => e._id.toString() === expenseId);
    if (expenseIndex === -1) return res.status(404).json({ error: 'Expense not found' });
    
    const expense = group.expenses[expenseIndex];
    
    // Check if the current user is the one who created this expense
    
    // Normalize email comparison (case-insensitive)
    const normalizedExpenseAddedBy = (expense.addedBy || '').toLowerCase().trim();
    const normalizedUserEmail = (userEmail || '').toLowerCase().trim();
    
    
    if (normalizedExpenseAddedBy !== normalizedUserEmail) {
      return res.status(403).json({ 
        error: 'Only the person who created this expense can edit it',
        debug: {
          expenseAddedBy: expense.addedBy,
          userEmail: userEmail,
          normalizedExpenseAddedBy: normalizedExpenseAddedBy,
          normalizedUserEmail: normalizedUserEmail
        }
      });
    }
    
    
    // Validate required fields
    if (!description || !amount || amount <= 0) {
      return res.status(400).json({ error: 'Description and valid amount are required' });
    }

    const normalizedCurrency = normalizeCurrency(currency || expense.currency);
    const supportedCurrencyCodes = await getSupportedCurrencyCodes();
    if (!supportedCurrencyCodes.includes(normalizedCurrency)) {
      return res.status(400).json({ error: 'Unsupported currency selected' });
    }

    const lockedCurrency = getLockedCurrencyForGroup(group, expenseId);
    if (lockedCurrency && lockedCurrency !== normalizedCurrency) {
      return res.status(400).json({
        error: buildCurrencyLockError(lockedCurrency),
        lockedCurrency,
      });
    }
    
    // Validate that all selected members are active (haven't left the group)
    const activeMembers = group.members.filter(m => !m.leftAt).map(m => m.user.email);
    const inactiveSelectedMembers = selectedMembers.filter(email => !activeMembers.includes(email));
    if (inactiveSelectedMembers.length > 0) {
      return res.status(400).json({ 
        error: `Cannot include members who have left the group: ${inactiveSelectedMembers.join(', ')}` 
      });
    }
    
    // Remove old expense from balances
    const oldAmount = expense.amount;
    expense.split.forEach(s => {
      const bal = group.balances.find(b => b.user.toString() === s.user.toString());
      if (bal) bal.balance -= s.amount;
    });
    const payerBal = group.balances.find(b => b.user.toString() === userId.toString());
    if (payerBal) payerBal.balance += oldAmount;
    
    // Prepare new split data based on split type
    let splitArr = [];
    if (splitType === 'equal') {
      const splitAmount = amount / selectedMembers.length;
      splitArr = selectedMembers.map(memberEmail => {
        const member = group.members.find(m => m.user.email === memberEmail && !m.leftAt);
        if (!member) {
          throw new Error(`Member with email ${memberEmail} not found`);
        }
        return {
          user: member.user._id,
          amount: splitAmount
        };
      });
    } else if (splitType === 'custom') {
      // Handle custom split with provided amounts
      if (!customSplitAmounts) {
        return res.status(400).json({ error: 'Custom split amounts are required for custom split type' });
      }
      
      splitArr = selectedMembers.map(memberEmail => {
        const member = group.members.find(m => m.user.email === memberEmail && !m.leftAt);
        if (!member) {
          throw new Error(`Member with email ${memberEmail} not found`);
        }
        const customAmount = customSplitAmounts[memberEmail] || 0;
        return {
          user: member.user._id,
          amount: customAmount
        };
      });
    } else {
      return res.status(400).json({ error: 'Invalid split type' });
    }
    
    // Update the expense
    expense.description = description;
    expense.amount = amount;
    expense.currency = normalizedCurrency;
    expense.date = date ? new Date(date) : new Date();
    expense.category = category || expense.category || 'other';
    expense.selectedMembers = selectedMembers;
    expense.split = splitArr;
    
    // Update balances with new expense
    splitArr.forEach(s => {
      const bal = group.balances.find(b => b.user.toString() === s.user.toString());
      if (bal) bal.balance += s.amount;
    });
    const newPayerBal = group.balances.find(b => b.user.toString() === userId.toString());
    if (newPayerBal) newPayerBal.balance -= amount;
    
    await group.save();
    
    const groupObj = group.toObject();
    
    // Process expenses to convert Object IDs to emails in addedBy field
    const processedExpenses = await processExpenses(groupObj.expenses);
    
    groupObj.members = groupObj.members.map(m => ({
      _id: m.user._id,
      email: m.user.email,
      joinedAt: m.joinedAt,
      leftAt: m.leftAt
    }));
    groupObj.creator = {
      _id: groupObj.creator._id,
      email: groupObj.creator.email
    };
    groupObj.expenses = processedExpenses;
    
    res.json({ group: groupObj });
    
    // Log activity for expense editing - all members get notified
    try {
      const creatorInfo = {
        creatorId: userId,
        creatorEmail: userEmail
      };
      await logGroupActivityForAllMembers('expense_edited', group, {
        expenseDescription: description,
        expenseAmount: amount,
        currency: normalizedCurrency,
      }, null, creatorInfo);
      groupTransactionEmail.sendExpenseEditedEmail(group, expense, userEmail);

      // Notify all active members except the editor
      const editorIdStr = userId.toString();
      const editMemberIds = group.members
        .filter(m => !m.leftAt && m.user._id.toString() !== editorIdStr)
        .map(m => m.user._id);
      if (editMemberIds.length > 0) {
        const eligible = await User.find({ _id: { $in: editMemberIds }, 'notificationSettings.groupNotifications': { $ne: false } }).select('_id');
        if (eligible.length > 0) {
          await Notification.create(eligible.map(u => ({
            sender: userId, senderModel: 'User', recipientType: 'specific-users',
            recipients: [u._id], recipientModel: 'User', category: 'group',
            message: `${userEmail} edited the expense "${description}" in group "${group.title}".`,
          })));
          eligible.forEach(u => sendToUser(User, u._id, { title: 'Expense Edited', body: `${userEmail} edited the expense "${description}" in group "${group.title}".`, data: { type: 'group_expense_edited' } }, { settingKey: 'groupNotifications' }));
        }
      }
    } catch (e) {
      console.error('Failed to log group activity or send email:', e);
    }
  } catch (err) {
    if (err.name === 'VersionError') {
      return res.status(409).json({
        error: 'This group was updated by someone else at the same time. Please try again.',
      });
    }
    res.status(500).json({ error: 'Server error' });
  }
};

exports.settleMemberExpenses = async (req, res) => {
  try {
    const { groupId } = req.params;
    const email = (req.body.email || '').toLowerCase().trim();
    const group = await GroupTransaction.findById(groupId);
    
    if (!group) {
      return res.status(404).json({ error: 'Group not found' });
    }
    
    // Check if user is the group creator
    if (group.creator.toString() !== req.user._id.toString()) {
      return res.status(403).json({ error: 'Only group creator can settle member expenses' });
    }
    
    // Find the member to settle
    const user = await User.findOne({ email });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    // Check if trying to settle the creator
    if (user._id.toString() === group.creator.toString()) {
      return res.status(400).json({ error: 'Cannot settle group creator expenses' });
    }
    
    // Check if user is a member
    const memberIndex = group.members.findIndex(m => m.user.toString() === user._id.toString() && !m.leftAt);
    if (memberIndex === -1) {
      return res.status(400).json({ error: 'User is not an active member of this group' });
    }
    
    
    // Mark all split amounts for this member as settled in all expenses
    let expensesUpdated = 0;
    const creator = await User.findById(req.user._id);
    if (!creator) {
      return res.status(404).json({ error: 'Creator not found' });
    }
    
    for (let expense of group.expenses) {
      let expenseModified = false;
      
      for (let splitItem of expense.split) {
        if (splitItem.user.toString() === user._id.toString() && !splitItem.settled) {
          // Mark this split as settled (don't change the amount, just mark as settled)
          splitItem.settled = true;
          splitItem.settledAt = new Date();
          splitItem.settledBy = creator.email;
          expenseModified = true;
        }
      }
      
      if (expenseModified) {
        expensesUpdated++;
      }
    }
    
    
    await group.save();
    
    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    const groupObj = populatedGroup.toObject();
    
    // Process expenses to convert Object IDs to emails in addedBy field
    const processedExpenses = await processExpenses(groupObj.expenses);
    
    groupObj.members = groupObj.members.map(m => ({
      _id: m.user._id,
      email: m.user.email,
      joinedAt: m.joinedAt,
      leftAt: m.leftAt
    }));
    groupObj.creator = {
      _id: groupObj.creator._id,
      email: groupObj.creator.email
    };
    groupObj.expenses = processedExpenses;
    
    res.json({ 
      group: groupObj,
      message: `Successfully marked ${expensesUpdated} expenses as settled for ${email}` 
    });
    
    // Log activity for expense settlement - all members get notified
    try {
      const creatorInfo = {
        creatorId: req.user._id,
        creatorEmail: req.user.email
      };
      await logGroupActivityForAllMembers('expense_settled', group, {
        memberEmail: email,
        expensesUpdated: expensesUpdated
      }, null, creatorInfo);

      // Notify the settled member
      if (user.notificationSettings?.groupNotifications !== false) {
        await Notification.create({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [user._id], recipientModel: 'User', category: 'group',
          message: `${req.user.email} marked your expenses as settled in group "${group.title}".`,
        });
      }
      sendToUser(User, user._id, { title: 'Expenses Settled', body: `${req.user.email} marked your expenses as settled in group "${group.title}".`, data: { type: 'group_expenses_settled' } }, { settingKey: 'groupNotifications' });
    } catch (e) {
      console.error('Failed to log group activity:', e);
    }
  } catch (err) {
    console.error('Error settling member expenses:', err);
    if (err.name === 'VersionError') {
      return res.status(409).json({
        error: 'This group was updated by someone else at the same time. Please try again.',
      });
    }
    res.status(500).json({ error: 'Server error' });
  }
};

// Record a peer-to-peer payment between two group members.
// Tracks only this specific payer'receiver pair so other debts are unaffected.
// Pays a fellow group member via an atomic LenDen Wallet transfer, then
// records it in memberPayments[] so the balance-netting calculation picks it
// up. The recipient is resolved from the group's own membership list (not an
// arbitrary client-supplied email) so money can only go to a real active
// member/creator of this group  and the wallet movement now happens here
// rather than being a bookkeeping-only log of a payment that may or may not
// have actually occurred.
exports.recordMemberPayment = async (req, res) => {
  const session = await mongoose.startSession();
  try {
    const { groupId } = req.params;
    const { toEmail, amount } = req.body;

    if (!toEmail || !amount || parseFloat(amount) <= 0) {
      return res.status(400).json({ error: 'toEmail and a positive amount are required' });
    }

    const group = await GroupTransaction.findById(groupId)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    if (!group) return res.status(404).json({ error: 'Group not found' });

    const isMember = group.members.some(
      m => m.user._id.toString() === req.user._id.toString() && !m.leftAt
    );
    const isCreator = group.creator._id.toString() === req.user._id.toString();
    if (!isMember && !isCreator) {
      return res.status(403).json({ error: 'You are not an active member of this group' });
    }

    const cleanToEmail = toEmail.toLowerCase().trim();
    const activeMemberEmails = group.members
      .filter(m => !m.leftAt)
      .map(m => (m.user.email || '').toLowerCase());
    activeMemberEmails.push((group.creator.email || '').toLowerCase());
    if (!activeMemberEmails.includes(cleanToEmail)) {
      return res.status(400).json({ error: 'Recipient is not an active member of this group' });
    }
    if (cleanToEmail === (req.user.email || '').toLowerCase().trim()) {
      return res.status(400).json({ error: 'Cannot pay yourself' });
    }

    const payee = await User.findOne({ email: cleanToEmail }).select('_id email');
    if (!payee) return res.status(404).json({ error: 'Recipient not found on LenDen' });

    const parsedAmount = parseFloat(amount);
    let newBalance;
    await session.withTransaction(async () => {
      // Atomic check-and-debit  fails (returns null) if balance is insufficient.
      const payer = await User.findOneAndUpdate(
        { _id: req.user._id, walletBalance: { $gte: parsedAmount } },
        { $inc: { walletBalance: -parsedAmount } },
        { new: true, session }
      );
      if (!payer) {
        throw Object.assign(new Error('Insufficient wallet balance'), {
          status: 400,
          userMessage: 'Insufficient LenDen wallet balance. Please top up your wallet and try again.',
        });
      }

      await User.findByIdAndUpdate(payee._id, { $inc: { walletBalance: parsedAmount } }, { session });

      await WalletTransaction.create([
        { user: payer._id, type: 'debit', amount: parsedAmount, toEmail: payee.email, note: `Group expense settlement  ${group.title}`, sourceType: 'group' },
        { user: payee._id, type: 'credit', amount: parsedAmount, fromEmail: payer.email, note: `Group expense settlement  ${group.title}`, sourceType: 'group' },
      ], { session });

      group.memberPayments.push({
        from: req.user.email.toLowerCase().trim(),
        to: cleanToEmail,
        amount: parsedAmount,
        paidAt: new Date(),
      });
      await group.save({ session });

      newBalance = payer.walletBalance;
    });

    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    const groupObj = populatedGroup.toObject();
    const processedExpenses = await processExpenses(groupObj.expenses);
    groupObj.members = groupObj.members.map(m => ({
      _id: m.user._id,
      email: m.user.email,
      joinedAt: m.joinedAt,
      leftAt: m.leftAt,
    }));
    groupObj.creator = { _id: groupObj.creator._id, email: groupObj.creator.email };
    groupObj.expenses = processedExpenses;

    res.json({ group: groupObj, balance: newBalance });

    // Fire-and-forget: notify payer and payee
    Promise.all([
      User.findById(req.user._id).select('notificationSettings'),
      User.findById(payee._id).select('notificationSettings'),
    ]).then(([payerUser, payeeUser]) => {
      const notifs = [];
      if (payerUser?.notificationSettings?.transactionNotifications !== false) {
        notifs.push(Notification.create({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [req.user._id], recipientModel: 'User', category: 'transaction',
          message: `Group settlement: Rs.${parsedAmount} sent to ${cleanToEmail} for group "${group.title}".`,
        }));
      }
      if (payeeUser?.notificationSettings?.transactionNotifications !== false) {
        notifs.push(Notification.create({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [payee._id], recipientModel: 'User', category: 'transaction',
          message: `Group settlement: You received Rs.${parsedAmount} from ${req.user.email} for group "${group.title}".`,
        }));
      }
      sendToUser(User, payee._id, { title: 'Group Settlement Received', body: `You received Rs.${parsedAmount} from ${req.user.email} for group "${group.title}".`, data: { type: 'group_settlement_received' } }, { settingKey: 'groupNotifications' });
      return Promise.all(notifs);
    }).catch(() => {});
  } catch (err) {
    if (err.name === 'VersionError') {
      return res.status(409).json({
        error: 'This group was updated by someone else at the same time. Please try again.',
      });
    }
    res.status(err.status ?? 500).json({ error: err.userMessage || 'Server error' });
  } finally {
    session.endSession();
  }
};

// Allow the paying member to self-settle their own splits after making payment.
// Called automatically from the frontend Pay Now / Pay success callback.
exports.selfSettleExpenses = async (req, res) => {
  try {
    const { groupId } = req.params;
    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });

    // Must be an active member (creator included)
    const isMember = group.members.some(
      m => m.user.toString() === req.user._id.toString() && !m.leftAt
    );
    const isCreator = group.creator.toString() === req.user._id.toString();
    if (!isMember && !isCreator) {
      return res.status(403).json({ error: 'You are not an active member of this group' });
    }

    // Mark all of this user's unsettled splits across all expenses
    let expensesUpdated = 0;
    for (const expense of group.expenses) {
      let modified = false;
      for (const splitItem of expense.split) {
        if (splitItem.user.toString() === req.user._id.toString() && !splitItem.settled) {
          splitItem.settled = true;
          splitItem.settledAt = new Date();
          splitItem.settledBy = req.user.email;
          modified = true;
        }
      }
      if (modified) expensesUpdated++;
    }

    await group.save();

    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    const groupObj = populatedGroup.toObject();
    const processedExpenses = await processExpenses(groupObj.expenses);
    groupObj.members = groupObj.members.map(m => ({
      _id: m.user._id,
      email: m.user.email,
      joinedAt: m.joinedAt,
      leftAt: m.leftAt,
    }));
    groupObj.creator = { _id: groupObj.creator._id, email: groupObj.creator.email };
    groupObj.expenses = processedExpenses;

    res.json({ group: groupObj, expensesUpdated });

    try {
      await logGroupActivityForAllMembers('expense_settled', group, {
        memberEmail: req.user.email,
        expensesUpdated,
      }, null, { creatorId: req.user._id, creatorEmail: req.user.email });
    } catch (e) {
      console.error('Failed to log group activity:', e);
    }
  } catch (err) {
    if (err.name === 'VersionError') {
      return res.status(409).json({
        error: 'This group was updated by someone else at the same time. Please try again.',
      });
    }
    res.status(500).json({ error: 'Server error' });
  }
};

// Settle expense splits for specific members
exports.settleExpenseSplits = async (req, res) => {
  try {
    const { groupId, expenseId } = req.params;
    const { memberEmails } = req.body || {}; // Array of member emails to settle

    if (!req.user || !req.user._id) {
      return res.status(401).json({ error: 'Authentication required' });
    }

    if (!memberEmails || !Array.isArray(memberEmails) || memberEmails.length === 0) {
      return res.status(400).json({ error: 'memberEmails array is required' });
    }
    
    const group = await GroupTransaction.findById(groupId);
    if (!group) {
      return res.status(404).json({ error: 'Group not found' });
    }
    
    // Check if user is the group creator
    if (group.creator.toString() !== req.user._id.toString()) {
      return res.status(403).json({ error: 'Only group creator can settle expense splits' });
    }
    
    // Find the expense
    const expense = group.expenses.id(expenseId);
    if (!expense) {
      return res.status(404).json({ error: 'Expense not found' });
    }
    
    // Get creator's email
    const creator = await User.findById(req.user._id);
    if (!creator) {
      return res.status(404).json({ error: 'Creator not found' });
    }
    
    let settledCount = 0;
    let alreadySettledCount = 0;
    let alreadySettledMembers = [];
    
    // Settle splits for the specified members
    for (let splitItem of expense.split) {
      const member = await User.findById(splitItem.user);
      if (member && memberEmails.includes(member.email)) {
        if (splitItem.settled) {
          // Track already settled members
          alreadySettledCount++;
          alreadySettledMembers.push(member.email);
          continue;
        }
        splitItem.settled = true;
        splitItem.settledAt = new Date();
        splitItem.settledBy = creator.email;
        settledCount++;
      }
    }
    
    if (settledCount === 0) {
      if (alreadySettledCount > 0) {
        return res.status(400).json({ 
          error: `All selected members are already settled: ${alreadySettledMembers.join(', ')}` 
        });
      }
      return res.status(400).json({ error: 'No valid splits found to settle' });
    }
    
    await group.save();
    
    // Populate and return updated group
    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    
    const groupObj = populatedGroup.toObject();
    groupObj.members = groupObj.members.map(m => ({
      _id: m.user._id,
      email: m.user.email,
      joinedAt: m.joinedAt,
      leftAt: m.leftAt
    }));
    groupObj.creator = {
      _id: groupObj.creator._id,
      email: groupObj.creator.email
    };
    
    let message = `Successfully settled ${settledCount} split(s) in expense`;
    if (alreadySettledCount > 0) {
      message += `. ${alreadySettledCount} member(s) were already settled: ${alreadySettledMembers.join(', ')}`;
    }
    
    res.json({ 
      group: groupObj,
      message: message,
      settledCount: settledCount,
      alreadySettledCount: alreadySettledCount,
      alreadySettledMembers: alreadySettledMembers
    });
    
    // Log activity for expense split settlement - all members get notified
    try {
      const creatorInfo = {
        creatorId: req.user._id,
        creatorEmail: req.user.email
      };
      await logGroupActivityForAllMembers('expense_settled', group, {
        expenseDescription: expense.description,
        settledCount: settledCount,
        memberEmails: memberEmails
      }, null, creatorInfo);
      groupTransactionEmail.sendExpenseSettledEmail(populatedGroup, expense, req.user.email);

      // Notify each settled member
      const settledUsers = await User.find({ email: { $in: memberEmails }, 'notificationSettings.groupNotifications': { $ne: false } }).select('_id');
      if (settledUsers.length > 0) {
        await Notification.create(settledUsers.map(u => ({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [u._id], recipientModel: 'User', category: 'group',
          message: `${req.user.email} settled your split for expense "${expense.description}" in group "${group.title}".`,
        })));
        settledUsers.forEach(u => sendToUser(User, u._id, { title: 'Split Settled', body: `${req.user.email} settled your split for expense "${expense.description}" in group "${group.title}".`, data: { type: 'group_split_settled' } }, { settingKey: 'groupNotifications' }));
      }
    } catch (e) {
      console.error('Failed to log group activity or send email:', e);
    }
  } catch (err) {
    console.error('Error settling expense splits:', err);
    if (err.name === 'VersionError') {
      return res.status(409).json({
        error: 'This group was updated by someone else at the same time. Please try again.',
      });
    }
    res.status(500).json({ error: 'Server error' });
  }
};

// Send leave request to group creator
exports.sendLeaveRequest = async (req, res) => {
  try {
    const { groupId } = req.params;
    const group = await GroupTransaction.findById(groupId)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    
    if (!group) {
      return res.status(404).json({ error: 'Group not found' });
    }
    
    // Check if user is a member (not creator)
    if (group.creator._id.toString() === req.user._id.toString()) {
      return res.status(400).json({ error: 'Group creator cannot send leave request. Use delete group instead.' });
    }
    
    const memberIndex = group.members.findIndex(m => m.user._id.toString() === req.user._id.toString() && !m.leftAt);
    if (memberIndex === -1) {
      return res.status(400).json({ error: 'You are not a member of this group' });
    }
    
    // Calculate user's total split amount (pending balance) - excluding settled amounts
    let userBalance = 0;
    for (let expense of group.expenses) {
      for (let splitItem of expense.split) {
        if (splitItem.user.toString() === req.user._id.toString()) {
          // Only include unsettled amounts
          if (!splitItem.settled) {
            userBalance += splitItem.amount;
          }
        }
      }
    }
    
    // Get user's email
    const user = await User.findById(req.user._id);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    // Prepare group details for email
    const groupDetails = {
      title: group.title,
      members: group.members,
      expenses: group.expenses,
      creator: group.creator
    };
    
    // Send email to group creator
    const emailSent = await sendGroupLeaveRequestEmail(
      group.creator.email,
      groupDetails,
      user.email,
      userBalance
    );
    
    if (emailSent) {
      res.json({
        success: true,
        message: 'Leave request sent to group creator successfully',
        userBalance: userBalance
      });

      // Notify group creator in-app
      User.findById(group.creator._id).select('notificationSettings').then(creatorUser => {
        if (creatorUser?.notificationSettings?.groupNotifications !== false) {
          return Notification.create({
            sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
            recipients: [group.creator._id], recipientModel: 'User', category: 'group',
            message: `${user.email} requested to leave the group "${group.title}".`,
          });
        }
      }).catch(() => {});
      sendToUser(User, group.creator._id, { title: 'Leave Request', body: `${user.email} requested to leave the group "${group.title}".`, data: { type: 'group_leave_request' } }, { settingKey: 'groupNotifications' });
    } else {
      res.status(500).json({ error: 'Failed to send leave request email' });
    }
  } catch (err) {
    console.error('Error sending leave request:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

exports.generateGroupReceipt = async (req, res) => {
  try {
    const { groupId } = req.params;
    const { action, email } = req.body;

    if (!action || !email) {
      return res.status(400).json({ error: 'Action and email are required' });
    }

    const group = await GroupTransaction.findById(groupId)
      .populate('members.user', 'email name')
      .populate('creator', 'email name');

    if (!group) {
      return res.status(404).json({ error: 'Group not found' });
    }

    // Generate PDF with custom styling
    const doc = new PDFDocument({ 
      margin: 0,
      size: 'A4'
    });
    
    const buffers = [];
    doc.on('data', buffers.push.bind(buffers));
    doc.on('end', async () => {
      const pdfBuffer = Buffer.concat(buffers);

      if (action === 'email') {
        try {
          await sendGroupReceiptEmail(email, group, pdfBuffer);
          await logGroupActivityForAllMembers('receipt_generated', group, { action: 'email', recipient: email }, null, { creatorId: req.user._id, creatorEmail: req.user.email });
          res.json({ success: true, message: 'Group receipt sent to email' });
        } catch (error) {
          console.error('Failed to send group receipt email:', error);
          res.status(500).json({ error: 'Failed to send group receipt email' });
        }
      } else if (action === 'download' || action === 'share') {
        res.setHeader('Content-Type', 'application/pdf');
        res.setHeader('Content-Disposition', `attachment; filename=group-receipt-${group._id}.pdf`);
        await logGroupActivityForAllMembers('receipt_generated', group, { action }, null, { creatorId: req.user._id, creatorEmail: req.user.email });
        res.send(pdfBuffer);
      } else {
        res.status(400).json({ error: 'Invalid action' });
      }
    });

    // Define colors
    const limeGreen = '#C5E063';
    const darkText = '#1a1a1a';
    const lightGray = '#f5f5f5';
    const successGreen = '#4CAF50';
    const warningRed = '#F44336';

    // Add lime green header background
    doc.rect(0, 0, 595, 150).fill(limeGreen);

    // Add title "Cash Receipt" in header
    doc.fillColor(darkText)
       .font('Helvetica-Bold')
       .fontSize(36)
       .text('Group Transaction Receipt', 50, 55, { align: 'center' });

    // Create white rounded rectangle for main content
    const contentY = 180;
    const contentX = 50;
    const contentWidth = 495;

    let currentY = contentY;

    // Helper function to check if we need a new page
    const checkPageBreak = (spaceNeeded) => {
      if (currentY + spaceNeeded > 750) {
        doc.addPage();
        currentY = 50;
        return true;
      }
      return false;
    };

    // Draw white background box
    doc.rect(contentX, currentY, contentWidth, 120).fill('#ffffff');
    doc.rect(contentX, currentY, contentWidth, 120).stroke('#e0e0e0');

    // Title inside white box
    doc.fillColor(darkText)
       .font('Helvetica-Bold')
       .fontSize(16)
       .text('GROUP INFORMATION', contentX, currentY + 15, {
         width: contentWidth,
         align: 'center'
       });

    currentY += 50;
    const leftMargin = contentX + 40;

    // Generate receipt number
    const receiptNumber = group._id.toString().slice(-6).toUpperCase();
    
    // Group basic info
    doc.font('Helvetica-Bold')
       .text('Group Title:', leftMargin, currentY)
       .font('Helvetica')
       .text(group.title, leftMargin + 150, currentY);
    currentY += 20;

    doc.font('Helvetica-Bold')
       .text('Creator:', leftMargin, currentY)
       .font('Helvetica')
       .text(`${group.creator.name || group.creator.email}`, leftMargin + 150, currentY);
    currentY += 20;

    doc.font('Helvetica-Bold')
       .text('Created On:', leftMargin, currentY)
       .font('Helvetica')
       .text(new Date(group.createdAt).toLocaleDateString('en-US', { 
         year: 'numeric', 
         month: 'long', 
         day: 'numeric' 
       }), leftMargin + 150, currentY);
    currentY += 20;

    doc.font('Helvetica-Bold')
       .text('Status:', leftMargin, currentY)
       .font('Helvetica')
       .fillColor(group.isActive ? successGreen : warningRed)
       .text(group.isActive ? 'Active' : 'Inactive', leftMargin + 150, currentY);
    
    currentY += 40;
    checkPageBreak(150);

    // MEMBERS SECTION
    doc.fillColor(darkText)
       .font('Helvetica-Bold')
       .fontSize(14)
       .text('GROUP MEMBERS', leftMargin, currentY);
    currentY += 25;

    // Members table header
    doc.rect(leftMargin, currentY, contentWidth - 80, 25).fill(lightGray);
    doc.fillColor(darkText)
       .font('Helvetica-Bold')
       .fontSize(10)
       .text('Member Email', leftMargin + 5, currentY + 8, { width: 180 })
       .text('Joined', leftMargin + 190, currentY + 8, { width: 80 })
       .text('Left', leftMargin + 275, currentY + 8, { width: 80 })
       .text('Status', leftMargin + 360, currentY + 8, { width: 55 });
    currentY += 25;

    // Display members
    group.members.forEach((member, index) => {
      checkPageBreak(20);
      if (index % 2 === 0) {
        doc.rect(leftMargin, currentY, contentWidth - 80, 20).fill('#fafafa');
      }
      
      doc.fillColor(darkText)
         .font('Helvetica')
         .fontSize(9)
         .text(member.user.email.substring(0, 28), leftMargin + 5, currentY + 5, { width: 180 })
         .text(new Date(member.joinedAt).toLocaleDateString(), leftMargin + 190, currentY + 5, { width: 80 })
         .text(member.leftAt ? new Date(member.leftAt).toLocaleDateString() : '-', leftMargin + 275, currentY + 5, { width: 80 });
      
      doc.fillColor(member.leftAt ? warningRed : successGreen)
         .text(member.leftAt ? 'Left' : 'Active', leftMargin + 360, currentY + 5, { width: 55 });
      
      currentY += 20;
    });

    currentY += 30;
    checkPageBreak(150);

    // Display balances
    group.balances.forEach((balance, index) => {
      checkPageBreak(20);
      const member = group.members.find(m => m.user._id.equals(balance.user));
      if (member && member.user) {
        if (index % 2 === 0) {
          doc.rect(leftMargin, currentY, contentWidth - 80, 20).fill('#fafafa');
        }
        
        doc.fillColor(darkText)
           .font('Helvetica')
           .fontSize(9)
           .text(member.user.email, leftMargin + 5, currentY + 5, { width: 280 });
        
        const balanceColor = balance.balance > 0 ? warningRed : (balance.balance < 0 ? successGreen : darkText);
        doc.fillColor(balanceColor)
           .text(balance.balance.toFixed(2), leftMargin + 290, currentY + 5, { width: 125, align: 'right' });
        
        currentY += 20;
      }
    });

    currentY += 30;
    checkPageBreak(150);

    // EXPENSES SECTION
    doc.fillColor(darkText)
       .font('Helvetica-Bold')
       .fontSize(14)
       .text('DETAILED EXPENSES', leftMargin, currentY);
    currentY += 25;

    // Calculate total
    const totalAmount = group.expenses.reduce((sum, exp) => sum + exp.amount, 0);

    // Display each expense with full details
    group.expenses.forEach((expense, expIndex) => {
      checkPageBreak(200);

      // Expense box
      doc.rect(leftMargin, currentY, contentWidth - 80, 25).fill(limeGreen);
      doc.fillColor(darkText)
         .font('Helvetica-Bold')
         .fontSize(11)
         .text(`Expense #${expIndex + 1}: ${expense.description}`, leftMargin + 5, currentY + 7);
      currentY += 25;

      // Expense details
      doc.rect(leftMargin, currentY, contentWidth - 80, 90).fill('#ffffff');
      doc.rect(leftMargin, currentY, contentWidth - 80, 90).stroke('#e0e0e0');
      
      doc.fillColor(darkText)
         .font('Helvetica-Bold')
         .fontSize(9)
         .text('Amount:', leftMargin + 10, currentY + 10)
         .font('Helvetica')
         .text(`Rs.${expense.amount.toFixed(2)}`, leftMargin + 100, currentY + 10);
      
      doc.font('Helvetica-Bold')
         .text('Added By:', leftMargin + 10, currentY + 25)
         .font('Helvetica')
         .text(expense.addedBy, leftMargin + 100, currentY + 25);
      
      doc.font('Helvetica-Bold')
         .text('Date:', leftMargin + 10, currentY + 40)
         .font('Helvetica')
         .text(new Date(expense.date).toLocaleDateString('en-US', { 
           year: 'numeric', 
           month: 'long', 
           day: 'numeric',
           hour: '2-digit',
           minute: '2-digit'
         }), leftMargin + 100, currentY + 40);
      
      doc.font('Helvetica-Bold')
         .text('Selected Members:', leftMargin + 10, currentY + 55)
         .font('Helvetica')
         .fontSize(8)
         .text(expense.selectedMembers ? expense.selectedMembers.join(', ') : 'N/A', leftMargin + 100, currentY + 55, { width: 300 });
      
      currentY += 95;

      // Split details header
      checkPageBreak(100);
      doc.rect(leftMargin + 10, currentY, contentWidth - 100, 20).fill(lightGray);
      doc.fillColor(darkText)
         .font('Helvetica-Bold')
         .fontSize(9)
         .text('Member', leftMargin + 15, currentY + 6, { width: 150 })
         .text('Amount', leftMargin + 170, currentY + 6, { width: 70, align: 'right' })
         .text('Settled', leftMargin + 245, currentY + 6, { width: 60 })
         .text('Settled At', leftMargin + 310, currentY + 6, { width: 70 })
         .text('Settled By', leftMargin + 385, currentY + 6, { width: 60 });
      currentY += 20;

      // Split items
      expense.split.forEach((split, splitIndex) => {
        checkPageBreak(20);
        const member = group.members.find(m => m.user._id.equals(split.user));
        if (member && member.user) {
          if (splitIndex % 2 === 0) {
            doc.rect(leftMargin + 10, currentY, contentWidth - 100, 18).fill('#fafafa');
          }
          
          doc.fillColor(darkText)
             .font('Helvetica')
             .fontSize(8)
             .text(member.user.email.substring(0, 22), leftMargin + 15, currentY + 4, { width: 150 })
             .text(split.amount.toFixed(2), leftMargin + 170, currentY + 4, { width: 70, align: 'right' });
          
          doc.fillColor(split.settled ? successGreen : warningRed)
             .text(split.settled ? 'Yes' : 'No', leftMargin + 245, currentY + 4, { width: 60 });
          
          doc.fillColor(darkText)
             .text(split.settledAt ? new Date(split.settledAt).toLocaleDateString() : '-', leftMargin + 310, currentY + 4, { width: 70 })
             .text(split.settledBy ? split.settledBy.substring(0, 12) : '-', leftMargin + 385, currentY + 4, { width: 60 });
          
          currentY += 18;
        }
      });

      currentY += 25;
    });

    // Total summary
    checkPageBreak(80);
    doc.rect(leftMargin, currentY, contentWidth - 80, 35).fill(limeGreen);
    doc.fillColor(darkText)
       .font('Helvetica-Bold')
       .fontSize(14)
       .text('TOTAL EXPENSE:', leftMargin + 10, currentY + 10)
       .fontSize(16)
       .text(`Rs.${totalAmount.toFixed(2)}`, leftMargin + 200, currentY + 8, { width: 215, align: 'right' });
    
    currentY += 50;

    // Footer
    checkPageBreak(50);
    doc.fillColor('#999999')
       .font('Helvetica')
       .fontSize(8)
       .text(
         `Generated on ${new Date().toLocaleString()} | Group ID: ${group._id}`,
         50,
         currentY + 20,
         { align: 'center', width: 495 }
       );

    doc.end();

  } catch (err) {
    console.error('Error generating group receipt:', err);
    res.status(500).json({ error: 'Failed to generate group receipt' });
  }
};

//  Join Code 

const crypto = require('crypto');

const _generateCode = () => crypto.randomBytes(4).toString('hex').toUpperCase(); // 8 chars

exports.generateJoinCode = async (req, res) => {
  try {
    const group = await GroupTransaction.findById(req.params.groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });

    const user = await User.findById(req.user._id).select('email');
    if (_emailOf(group.creator) !== user.email && group.creator.toString() !== req.user._id.toString()) {
      return res.status(403).json({ error: 'Only the group creator can generate an invite code' });
    }

    let code;
    let attempts = 0;
    do {
      code = _generateCode();
      if (++attempts > 10) return res.status(500).json({ error: 'Failed to generate a unique join code, please try again' });
    } while (await GroupTransaction.exists({ joinCode: code }));

    group.joinCode = code;
    await group.save();
    res.json({ joinCode: group.joinCode });
  } catch (err) {
    res.status(500).json({ error: 'Failed to generate join code' });
  }
};

exports.disableJoinCode = async (req, res) => {
  try {
    const group = await GroupTransaction.findById(req.params.groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });

    const user = await User.findById(req.user._id).select('email');
    if (group.creator.toString() !== req.user._id.toString()) {
      return res.status(403).json({ error: 'Only the group creator can disable the invite code' });
    }

    await GroupTransaction.findByIdAndUpdate(group._id, { $unset: { joinCode: 1 } });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: 'Failed to disable join code' });
  }
};

exports.joinByCode = async (req, res) => {
  try {
    const { joinCode } = req.body;
    if (!joinCode) return res.status(400).json({ error: 'joinCode is required' });

    const group = await GroupTransaction.findOne({ joinCode: joinCode.toUpperCase() });
    if (!group) return res.status(404).json({ error: 'Invalid or expired invite code' });
    if (!group.isActive) return res.status(400).json({ error: 'This group is no longer active' });

    const user = await User.findById(req.user._id).select('email');
    const userEmail = user.email;

    const alreadyMember = group.members.some(
      m => m.leftAt == null && (m.user.toString() === req.user._id.toString())
    );
    if (alreadyMember) return res.status(400).json({ error: 'You are already a member of this group' });

    // Re-add if previously left
    const prevEntry = group.members.find(m => m.user.toString() === req.user._id.toString() && m.leftAt != null);
    if (prevEntry) {
      prevEntry.leftAt = null;
      prevEntry.joinedAt = new Date();
    } else {
      group.members.push({ user: req.user._id, joinedAt: new Date() });
    }

    if (!group.balances.find(b => b.user.toString() === req.user._id.toString())) {
      group.balances.push({ user: req.user._id, balance: 0 });
    }

    // Clear any pending invite for this user's email
    group.pendingInvites = (group.pendingInvites || []).filter(i => i.email !== userEmail.toLowerCase());

    await group.save();
    res.json({ success: true, group });

    logGroupActivity(req.user._id, 'group_joined', group, {}).catch(() => {});

    // Notify group creator that a new member joined
    User.findById(group.creator).select('notificationSettings').then(creatorUser => {
      if (creatorUser?.notificationSettings?.groupNotifications !== false) {
        return Notification.create({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [group.creator], recipientModel: 'User', category: 'group',
          message: `${userEmail} joined the group "${group.title}" via invite link.`,
        });
      }
    }).catch(() => {});
    sendToUser(User, group.creator, { title: 'New Member Joined', body: `${userEmail} joined the group "${group.title}" via invite link.`, data: { type: 'group_member_joined' } }, { settingKey: 'groupNotifications' });
  } catch (err) {
    res.status(500).json({ error: 'Failed to join group' });
  }
};

//  Group Statistics 

exports.getGroupStats = async (req, res) => {
  try {
    const group = await GroupTransaction.findById(req.params.groupId).populate('members.user', 'email name username');
    if (!group) return res.status(404).json({ error: 'Group not found' });

    const user = await User.findById(req.user._id).select('email');
    const isMember = group.members.some(
      m => m.leftAt == null && m.user._id.toString() === req.user._id.toString()
    );
    if (!isMember) return res.status(403).json({ error: 'Not a member of this group' });

    const expenses = group.expenses || [];

    // Totals
    const totalExpenses = expenses.reduce((s, e) => s + (e.amount || 0), 0);
    const settledExpenses = expenses.reduce((s, e) => {
      const allSettled = e.split.length > 0 && e.split.every(sp => sp.settled);
      return s + (allSettled ? (e.amount || 0) : 0);
    }, 0);
    const pendingExpenses = totalExpenses - settledExpenses;

    // Category breakdown
    const categoryMap = {};
    for (const e of expenses) {
      const cat = e.category || 'other';
      categoryMap[cat] = (categoryMap[cat] || 0) + (e.amount || 0);
    }
    const categoryBreakdown = Object.entries(categoryMap).map(([cat, amt]) => ({ category: cat, amount: amt }));

    // Monthly trend (last 12 months)
    const now = new Date();
    const monthlyCounts = Array(12).fill(0);
    const monthlyAmounts = Array(12).fill(0);
    const months = [];
    for (let i = 11; i >= 0; i--) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
      months.push(`${d.toLocaleString('default', { month: 'short' })} ${d.getFullYear()}`);
    }
    for (const e of expenses) {
      const d = new Date(e.date || e.createdAt || Date.now());
      const monthsAgo = (now.getFullYear() - d.getFullYear()) * 12 + (now.getMonth() - d.getMonth());
      if (monthsAgo >= 0 && monthsAgo < 12) {
        monthlyCounts[11 - monthsAgo]++;
        monthlyAmounts[11 - monthsAgo] += e.amount || 0;
      }
    }

    // Member balance summary  include every active member (balance defaults to 0)
    const balanceMap = {};
    for (const b of group.balances) {
      balanceMap[b.user.toString()] = b.balance;
    }
    const memberBalances = group.members
      .filter(m => m.user && !m.leftAt)
      .map(m => {
        const uid = m.user._id.toString();
        const email = m.user.email || '';
        const name = m.user.name || m.user.username || email;
        const balance = balanceMap[uid] ?? 0;
        return { email, name, balance };
      });

    res.json({
      totalExpenses,
      settledExpenses,
      pendingExpenses,
      totalExpenseCount: expenses.length,
      categoryBreakdown,
      monthlyCounts,
      monthlyAmounts,
      months,
      memberBalances,
    });
  } catch (err) {
    console.error('getGroupStats error:', err);
    res.status(500).json({ error: 'Failed to fetch group stats' });
  }
};

function _emailOf(field) {
  if (!field) return '';
  if (typeof field === 'object' && field.email) return field.email;
  return field.toString();
}

// Get communities a group belongs to
exports.getGroupCommunities = async (req, res) => {
  try {
    const group = await GroupTransaction.findById(req.params.groupId).select('communityIds members creator');
    if (!group) return res.status(404).json({ error: 'Group not found' });
    const isMember = group.members.some(m => m.user.toString() === req.user._id.toString());
    const isCreator = group.creator.toString() === req.user._id.toString();
    if (!isMember && !isCreator) return res.status(403).json({ error: 'Not a member' });
    const Community = require('../models/community');
    const communities = await Community.find({ _id: { $in: group.communityIds } })
      .select('name color inviteCode members').lean();
    res.json({ communities });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

// Add group to a community (must be admin of that community)
exports.addGroupToCommunityFromGroup = async (req, res) => {
  try {
    const { groupId } = req.params;
    const { communityId } = req.body;
    const Community = require('../models/community');
    const community = await Community.findById(communityId);
    if (!community) return res.status(404).json({ error: 'Community not found' });
    const isAdmin = community.members.some(m => m.user.toString() === req.user._id.toString() && m.role === 'admin');
    if (!isAdmin) return res.status(403).json({ error: 'You must be an admin of that community' });
    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });

    // Link group  community
    const alreadyIn = group.communityIds.map(id => id.toString()).includes(communityId);
    if (!alreadyIn) {
      group.communityIds.push(communityId);
      await group.save();
    }

    let communitySaved = false;
    if (!community.groups.map(id => id.toString()).includes(groupId)) {
      community.groups.push(group._id);
      communitySaved = true;
    }

    // Auto-add active group members who aren't already in the community
    const existingMemberIds = new Set(community.members.map(m => m.user.toString()));
    const activeGroupMembers = group.members.filter(m => !m.leftAt);
    for (const gm of activeGroupMembers) {
      if (!existingMemberIds.has(gm.user.toString())) {
        community.members.push({ user: gm.user, role: 'member', invitedBy: req.user._id });
        existingMemberIds.add(gm.user.toString());
        communitySaved = true;
      }
    }

    if (communitySaved) await community.save();
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

// Remove group from a community (must be admin of that community)
exports.removeGroupFromCommunityFromGroup = async (req, res) => {
  try {
    const { groupId, communityId } = req.params;
    const Community = require('../models/community');
    const community = await Community.findById(communityId);
    if (!community) return res.status(404).json({ error: 'Community not found' });
    const isAdmin = community.members.some(m => m.user.toString() === req.user._id.toString() && m.role === 'admin');
    if (!isAdmin) return res.status(403).json({ error: 'You must be an admin of that community' });
    await GroupTransaction.findByIdAndUpdate(groupId, { $pull: { communityIds: communityId } });
    await Community.findByIdAndUpdate(communityId, { $pull: { groups: groupId } });
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

