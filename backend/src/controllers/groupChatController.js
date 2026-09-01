const GroupChat = require('../models/groupChat');
const GroupTransaction = require('../models/groupTransaction');
const User = require('../models/user');
const { FEATURES, hasFeature } = require('../utils/subscriptionFeatures');
const {
    decodeChatMessage,
    normalizeStoredChatMessage,
    toChatResponse
} = require('../utils/chatCodec');
const { recordCoinLedgerEntry } = require('../utils/coinLedgerService');
const { getCoinPricing } = require('../utils/coinPricing');
const { sendToUser } = require('../services/notificationService');

function hasEncryptedPayloads(encryptedPayloads) {
    return Array.isArray(encryptedPayloads) && encryptedPayloads.length > 0;
}

module.exports = (io) => {
    let users = {};

    io.on('connection', (socket) => {
        socket.on('joinGroup', (groupTransactionId) => {
            if (groupTransactionId) {
                socket.join(groupTransactionId);
            }
        });

        socket.on('createGroupMessage', async (data) => {
            try {
                const {
                    groupTransactionId,
                    senderId,
                    message,
                    parentMessageId,
                    encryptedPayloads,
                    senderPublicKey,
                    encryptionVersion,
                    mentions,
                    mentionsAll,
                } = data;
                const decodedMessage = typeof message === 'string'
                    ? decodeChatMessage(message)
                    : '';
                const usingEncryptedPayloads = hasEncryptedPayloads(encryptedPayloads);

                if (!usingEncryptedPayloads && (!decodedMessage || !decodedMessage.trim())) {
                    socket.emit('createGroupMessageError', { ...data, error: 'Message cannot be empty.' });
                    return;
                }

                const groupTransaction = await GroupTransaction.findById(groupTransactionId);
                if (!groupTransaction) {
                    socket.emit('createGroupMessageError', { ...data, error: 'Group transaction not found' });
                    return;
                }

                const sender = await User.findById(senderId);
                if (!sender) {
                    socket.emit('createGroupMessageError', { ...data, error: 'User not found' });
                    return;
                }

                if (usingEncryptedPayloads) {
                    const isRegisteredDeviceKey = (sender.chatEncryptionDevices || [])
                        .some(d => d.publicKey === senderPublicKey);
                    if (!senderPublicKey || !isRegisteredDeviceKey) {
                        socket.emit('createGroupMessageError', { ...data, error: 'Encrypted chat key mismatch. Please refresh and try again.' });
                        return;
                    }
                }

                // Check if user is still an active member of the group
                const isActiveMember = groupTransaction.members.some(member => 
                    member.user.toString() === senderId && !member.leftAt
                );

                if (!isActiveMember) {
                    socket.emit('createGroupMessageError', {
                        ...data,
                        error: 'You are no longer an active member of this group. Chat is disabled.'
                    });
                    return;
                }

                const activeMemberIds = groupTransaction.members
                    .filter(member => !member.leftAt)
                    .map(member => member.user.toString());
                const validMentions = Array.isArray(mentions)
                    ? mentions.filter(id => activeMemberIds.includes(String(id)))
                    : [];

                const isSubscribed = await hasFeature(senderId, FEATURES.GROUP_CHAT);

                let start;
                let end;
                let todayCount = 0;
                if (!isSubscribed) {
                    start = new Date();
                    start.setHours(0, 0, 0, 0);
                    end = new Date();
                    end.setHours(23, 59, 59, 999);
                    todayCount = await GroupChat.countDocuments({
                        groupTransactionId,
                        senderId,
                        createdAt: { $gte: start, $lte: end },
                    });
                }

                const userMessageCount = groupTransaction.messageCounts.find(mc => mc.user.toString() === senderId);
                if (!isSubscribed) {
                    const pricing = await getCoinPricing();
                    const MESSAGE_COST = pricing.groupChatMessageCost;
                    const dailyLimitReached = todayCount >= 3;
                    const totalFreeUsed = userMessageCount && userMessageCount.count >= 5;
                    const needsCoins = dailyLimitReached || totalFreeUsed;

                    if (needsCoins) {
                        const updatedSender = await User.findOneAndUpdate(
                            { _id: sender._id, lenDenCoins: { $gte: MESSAGE_COST } },
                            { $inc: { lenDenCoins: -MESSAGE_COST } },
                            { new: true }
                        );
                        if (!updatedSender) {
                            socket.emit('createGroupMessageError', { ...data, error: 'Insufficient LenDen coins to send a message. Please subscribe or earn more coins.' });
                            return;
                        }
                        sender.lenDenCoins = updatedSender.lenDenCoins;
                        await recordCoinLedgerEntry({
                            userId: sender._id,
                            direction: 'spent',
                            coins: MESSAGE_COST,
                            source: 'group_chat_with_coins',
                            title: 'Group Chat Message Sent With Coins',
                            description: `Spent ${MESSAGE_COST} LenDen coins to send a group chat message.`,
                            metadata: {
                                groupTransactionId,
                            },
                        });
                    }
                }

                if (userMessageCount) {
                    await GroupTransaction.updateOne(
                        { _id: groupTransactionId, 'messageCounts.user': senderId },
                        { $inc: { 'messageCounts.$.count': 1 } }
                    );
                } else {
                    await GroupTransaction.updateOne(
                        { _id: groupTransactionId },
                        { $push: { messageCounts: { user: senderId, count: 1 } } }
                    );
                }

                let chat = new GroupChat({
                    groupTransactionId,
                    senderId,
                    message: usingEncryptedPayloads
                        ? null
                        : normalizeStoredChatMessage(decodedMessage.trim()),
                    senderPublicKey: usingEncryptedPayloads ? senderPublicKey : null,
                    encryptionVersion: usingEncryptedPayloads ? (Number(encryptionVersion) || 1) : 0,
                    encryptedPayloads: usingEncryptedPayloads ? encryptedPayloads : [],
                    parentMessageId,
                    mentions: validMentions,
                    mentionsAll: mentionsAll === true,
                });

                await chat.save();

                chat = await GroupChat.findById(chat._id)
                    .populate('senderId', 'name')
                    .populate({
                        path: 'parentMessageId',
                        populate: {
                            path: 'senderId',
                            select: 'name'
                        }
                    });

                const updatedGroupTransaction = await GroupTransaction.findById(groupTransactionId).populate('messageCounts.user', 'name');

                io.to(groupTransactionId).emit('newGroupMessage', {
                    chat: toChatResponse(chat),
                    messageCounts: updatedGroupTransaction.messageCounts,
                    lenDenCoins: sender.lenDenCoins
                });

                // Push FCM notifications to all active members who are offline
                const senderIdStr = senderId.toString();
                const notifyMemberIds = groupTransaction.members
                    .filter(m => !m.leftAt && m.user.toString() !== senderIdStr)
                    .map(m => m.user.toString());

                const senderName = sender.name || sender.username || sender.email || 'Someone';
                const groupTitle = groupTransaction.title || 'Group';
                const messagePreview = usingEncryptedPayloads
                    ? '🔒 Encrypted message'
                    : (decodedMessage || '').slice(0, 100);

                for (const memberId of notifyMemberIds) {
                    // Only notify members not currently connected to this group's socket room
                    if (!users[memberId]) {
                        sendToUser(
                            User,
                            memberId,
                            {
                                title: `${groupTitle} 💬`,
                                body: `${senderName}: ${messagePreview}`,
                                data: {
                                    type: 'group_chat_message',
                                    groupId: groupTransactionId.toString(),
                                    groupName: groupTitle,
                                },
                            },
                            { settingKey: 'groupNotifications' }
                        );
                    }
                }
            } catch (error) {
                console.error('Error in createGroupMessage socket handler:', error);
                socket.emit('createGroupMessageError', { ...data, error: 'An error occurred while sending the message.' });
            }
        });

        // Edit group message
        socket.on('editGroupMessage', async (data) => {
            try {
                const {
                    messageId,
                    userId,
                    message,
                    encryptedPayloads,
                    senderPublicKey,
                    encryptionVersion,
                    mentions,
                    mentionsAll,
                } = data;
                const decodedMessage = typeof message === 'string'
                    ? decodeChatMessage(message)
                    : '';
                const usingEncryptedPayloads = hasEncryptedPayloads(encryptedPayloads);

                const chat = await GroupChat.findOne({
                    _id: messageId,
                    senderId: userId
                });

                if (!chat) {
                    socket.emit('editGroupMessageError', { ...data, error: 'Message not found or not authorized to edit' });
                    return;
                }

                if (!usingEncryptedPayloads && (!decodedMessage || !decodedMessage.trim())) {
                    socket.emit('editGroupMessageError', { ...data, error: 'Message cannot be empty.' });
                    return;
                }

                const sender = await User.findById(userId).select('chatEncryptionDevices');
                const isRegisteredDeviceKey = (sender?.chatEncryptionDevices || [])
                    .some(d => d.publicKey === senderPublicKey);
                if (usingEncryptedPayloads && (!senderPublicKey || !isRegisteredDeviceKey)) {
                    socket.emit('editGroupMessageError', { ...data, error: 'Encrypted chat key mismatch. Please refresh and try again.' });
                    return;
                }

                // Check if user is still an active member of the group
                const groupTransaction = await GroupTransaction.findById(chat.groupTransactionId);
                if (groupTransaction) {
                    const isActiveMember = groupTransaction.members.some(member => 
                        member.user.toString() === userId && !member.leftAt
                    );

                    if (!isActiveMember) {
                        socket.emit('editGroupMessageError', { 
                            ...data, 
                            error: 'You are no longer an active member of this group. Chat is disabled.' 
                        });
                        return;
                    }
                }

                // Check if message is within 2 minutes of creation
                const now = new Date();
                const messageTime = new Date(chat.createdAt);
                const timeDiff = (now - messageTime) / (1000 * 60); // in minutes

                if (timeDiff > 2) {
                    socket.emit('editGroupMessageError', { ...data, error: 'Cannot edit message after 2 minutes' });
                    return;
                }

                chat.message = usingEncryptedPayloads
                    ? null
                    : normalizeStoredChatMessage(decodedMessage.trim());
                chat.senderPublicKey = usingEncryptedPayloads ? senderPublicKey : chat.senderPublicKey;
                chat.encryptionVersion = usingEncryptedPayloads ? (Number(encryptionVersion) || 1) : 0;
                chat.encryptedPayloads = usingEncryptedPayloads ? encryptedPayloads : [];
                chat.isEdited = true;
                if (Array.isArray(mentions) && groupTransaction) {
                    const activeMemberIds = groupTransaction.members
                        .filter(member => !member.leftAt)
                        .map(member => member.user.toString());
                    chat.mentions = mentions.filter(id => activeMemberIds.includes(String(id)));
                    chat.mentionsAll = mentionsAll === true;
                }
                await chat.save();

                const updatedChat = await GroupChat.findById(chat._id)
                    .populate('senderId', 'name')
                    .populate({
                        path: 'parentMessageId',
                        populate: {
                            path: 'senderId',
                            select: 'name'
                        }
                    });

                io.to(chat.groupTransactionId.toString()).emit('groupMessageUpdated', toChatResponse(updatedChat));
            } catch (error) {
                console.error('Error in editGroupMessage socket handler:', error);
                socket.emit('editGroupMessageError', { ...data, error: 'An error occurred while editing the message.' });
            }
        });

        // Delete group message
        socket.on('deleteGroupMessage', async (data) => {
            try {
                const { messageId, userId, forEveryone } = data;

                const chat = await GroupChat.findById(messageId);

                if (!chat) {
                    socket.emit('deleteGroupMessageError', { ...data, error: 'Message not found' });
                    return;
                }

                // Check if user is still an active member of the group
                const groupTransaction = await GroupTransaction.findById(chat.groupTransactionId);
                if (groupTransaction) {
                    const isActiveMember = groupTransaction.members.some(member => 
                        member.user.toString() === userId && !member.leftAt
                    );

                    if (!isActiveMember) {
                        socket.emit('deleteGroupMessageError', { 
                            ...data, 
                            error: 'You are no longer an active member of this group. Chat is disabled.' 
                        });
                        return;
                    }
                }

                if (forEveryone && chat.senderId.toString() !== userId) {
                    socket.emit('deleteGroupMessageError', { ...data, error: 'Not authorized to delete for everyone' });
                    return;
                }

                if (forEveryone) {
                    await GroupChat.findByIdAndDelete(messageId);
                } else {
                    if (!chat.deletedFor.includes(userId)) {
                        chat.deletedFor.push(userId);
                        await chat.save();
                    }
                }

                io.to(chat.groupTransactionId.toString()).emit('groupMessageDeleted', {
                    messageId,
                    groupTransactionId: chat.groupTransactionId,
                    forEveryone
                });
            } catch (error) {
                console.error('Error in deleteGroupMessage socket handler:', error);
                socket.emit('deleteGroupMessageError', { ...data, error: 'An error occurred while deleting the message.' });
            }
        });

        // Add group reaction
        socket.on('addGroupReaction', async (data) => {
            try {
                const { messageId, userId, emoji } = data;

                const chat = await GroupChat.findById(messageId);

                if (!chat) {
                    socket.emit('addGroupReactionError', { ...data, error: 'Message not found' });
                    return;
                }

                // Check if user is still an active member of the group
                const groupTransaction = await GroupTransaction.findById(chat.groupTransactionId);
                if (groupTransaction) {
                    const isActiveMember = groupTransaction.members.some(member => 
                        member.user.toString() === userId && !member.leftAt
                    );

                    if (!isActiveMember) {
                        socket.emit('addGroupReactionError', { 
                            ...data, 
                            error: 'You are no longer an active member of this group. Chat is disabled.' 
                        });
                        return;
                    }
                }

                // Remove existing reaction from this user for this message
                chat.reactions = chat.reactions.filter(reaction => reaction.userId.toString() !== userId);

                // Add new reaction
                chat.reactions.push({ emoji, userId });
                await chat.save();

                const updatedChat = await GroupChat.findById(chat._id)
                    .populate('senderId', 'name')
                    .populate({
                        path: 'parentMessageId',
                        populate: {
                            path: 'senderId',
                            select: 'name'
                        }
                    });

                io.to(chat.groupTransactionId.toString()).emit('groupMessageUpdated', updatedChat);
            } catch (error) {
                console.error('Error in addGroupReaction socket handler:', error);
                socket.emit('addGroupReactionError', { ...data, error: 'An error occurred while adding the reaction.' });
            }
        });
    });

    const exports = {};

    exports.getGroupMessages = async (req, res) => {
        try {
            const { groupTransactionId } = req.params;
            const { userId } = req.query;

            // First check if the user is still an active member
            const groupTransaction = await GroupTransaction.findById(groupTransactionId).populate('messageCounts.user', 'name');
            if (!groupTransaction) {
                return res.status(404).json({ message: 'Group transaction not found' });
            }

            const isActiveMember = groupTransaction.members.some(member => 
                member.user.toString() === userId && !member.leftAt
            );

            if (!isActiveMember) {
                return res.status(403).json({ 
                    message: 'You are no longer an active member of this group. Chat access denied.' 
                });
            }

            // Get all active member IDs to filter messages
            const activeMemberIds = groupTransaction.members
                .filter(member => !member.leftAt)
                .map(member => member.user);

            const messages = await GroupChat.find({
                groupTransactionId,
                deletedFor: { $ne: userId },
                senderId: { $in: activeMemberIds } // Only show messages from active members
            })
            .populate('senderId', 'name')
            .populate({
                path: 'parentMessageId',
                populate: {
                    path: 'senderId',
                    select: 'name'
                }
            })
            .sort({ createdAt: 'asc' });

            res.status(200).json({
                messages: messages.map((message) => toChatResponse(message)),
                messageCounts: groupTransaction.messageCounts
            });
        } catch (error) {
            res.status(500).json({ message: 'Error fetching group messages', error });
        }
    };

    return exports;
};
