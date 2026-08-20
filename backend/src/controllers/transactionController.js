const mongoose = require('mongoose');
const Transaction = require('../models/transaction');
const User = require('../models/user');
const WalletTransaction = require('../models/walletTransaction');
const lendingborrowingotp = require('../utils/email/lendingborrowingotp');
const { sendTransactionReceipt, sendTransactionClearedNotification } = require('../utils/email/lendingborrowingotp');
const { logTransactionActivity } = require('./activityController');
const { awardGiftCard, shouldAwardGiftCard } = require('./userGiftCardController');
const multer = require('multer');
const allowedMimeTypes = ['image/png', 'image/jpeg', 'image/jpg'];
const PDFDocument = require('pdfkit');

const { sendReceiptEmail } = require('../utils/email/receiptEmail');
const { processReferralRewardOnFirstCreation } = require('../utils/referralService');
const { validateCoinCreationAccess } = require('../utils/coinUsageGuard');
const { handleRouteError } = require('../utils/apiError');
const { recordCoinLedgerEntry } = require('../utils/coinLedgerService');
const { FEATURES, hasFeature } = require('../utils/subscriptionFeatures');
const { getCoinPricing } = require('../utils/coinPricing');
const Notification = require('../models/notification');
const { sendToUser } = require('../services/notificationService');

const { isBlockedBy } = require('../utils/userHelpers');
const { getTodayRange } = require('../utils/dateHelpers');

const isSubscribed = (userId) => hasFeature(userId, FEATURES.SECURE_TRANSACTIONS);

// Generate and send/download a transaction receipt
// Generate and send/download a transaction receipt
exports.generateReceipt = async (req, res) => {
  try {
    const { transactionId } = req.params;
    const { action, email } = req.body;

    if (!action || !email) {
      return res.status(400).json({ error: 'Action and email are required' });
    }

    const transaction = await Transaction.findOne({ transactionId });
    if (!transaction) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    if (req.user.email !== transaction.userEmail && req.user.email !== transaction.counterpartyEmail) {
      return res.status(403).json({ error: 'You are not a party to this transaction.' });
    }

    // Receipt may only be emailed to a party of the transaction, not an arbitrary address.
    if (action === 'email') {
      const allowedEmails = [transaction.userEmail, transaction.counterpartyEmail].map(e => e.toLowerCase());
      if (!allowedEmails.includes(email.toLowerCase())) {
        return res.status(403).json({ error: 'Receipt can only be sent to parties of this transaction.' });
      }
    }

    // Generate PDF with custom size
    const doc = new PDFDocument({ 
      margin: 0,
      size: [595.28, 841.89] // A4 size
    });
    
    const buffers = [];
    doc.on('data', buffers.push.bind(buffers));
    doc.on('end', async () => {
      const pdfBuffer = Buffer.concat(buffers);

      if (action === 'email') {
        try {
          await sendReceiptEmail(email, transaction, pdfBuffer);
          res.json({ success: true, message: 'Receipt sent to email' });
        } catch (error) {
          console.error('Failed to send receipt email:', error);
          res.status(500).json({ error: 'Failed to send receipt email' });
        }
      } else if (action === 'download') {
        res.setHeader('Content-Type', 'application/pdf');
        res.setHeader('Content-Disposition', `attachment; filename=receipt-${transaction.transactionId}.pdf`);
        res.send(pdfBuffer);
      } else {
        res.status(400).json({ error: 'Invalid action' });
      }
      await logTransactionActivity(req.user._id, 'receipt_generated', transaction, { action: action, recipient: email });
    });

    // === STYLED PDF CONTENT ===
    
    // Green header background
    doc.rect(0, 0, 595.28, 180)
       .fill('#C7DC5C');

    // Receipt generated timestamp at top right
    const now = new Date();
    const generatedDate = now.toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    });
    const generatedTime = now.toLocaleTimeString('en-US', {
      hour: '2-digit',
      minute: '2-digit',
      hour12: true
    });
    
    doc.fillColor('#1F2937')
       .fontSize(9)
       .font('Helvetica')
       .text(`Generated: ${generatedDate} at ${generatedTime}`, 420, 20, {
         width: 155,
         align: 'right'
       });

    // "LenDen Transaction Receipt" title in header
    doc.fillColor('#1F2937')
       .fontSize(42)
       .font('Helvetica-Bold')
       .text('LenDen Transaction Receipt', 0, 60, { align: 'center' });

    // White content box with rounded corners effect
    const boxX = 50;
    const boxY = 160;
    const boxWidth = 495.28;
    let boxHeight = 600; // Will be adjusted dynamically

    // Calculate required height based on content
    let estimatedHeight = 600;
    if (transaction.interestType && transaction.interestType !== 'none') {
      estimatedHeight += 150;
    }
    if (transaction.partialPayments && transaction.partialPayments.length > 0) {
      estimatedHeight += 50 + (transaction.partialPayments.length * 35);
    }
    boxHeight = Math.min(estimatedHeight, 650); // Cap at 650 to fit in page

    doc.rect(boxX, boxY, boxWidth, boxHeight)
       .fill('#FFFFFF');

    // Add shadow effect
    doc.rect(boxX - 2, boxY - 2, boxWidth + 4, boxHeight + 4)
       .strokeColor('#E5E7EB')
       .lineWidth(2)
       .stroke();

    // Content inside white box
    let yPos = boxY + 40;

    // "TRANSACTION RECEIPT" subtitle
    doc.fillColor('#000000')
       .fontSize(16)
       .font('Helvetica-Bold')
       .text('TRANSACTION RECEIPT', boxX + 20, yPos, { 
         width: boxWidth - 40,
         align: 'center' 
       });

    yPos += 50;

    // Receipt details
    const leftMargin = boxX + 40;
    const lineHeight = 35;
    const labelWidth = 180;

    // Format date and time
    const transactionDate = new Date(transaction.date).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric'
    });

    // Helper function to draw a field
    const drawField = (label, value, y) => {
      doc.fillColor('#000000')
         .fontSize(11)
         .font('Helvetica-Bold')
         .text(label + ':', leftMargin, y);
      
      doc.fillColor('#374151')
         .fontSize(11)
         .font('Helvetica')
         .text(value, leftMargin + labelWidth, y, {
           width: boxWidth - labelWidth - 80
         });
      
      // Underline
      doc.moveTo(leftMargin + labelWidth, y + 16)
         .lineTo(boxX + boxWidth - 40, y + 16)
         .strokeColor('#E5E7EB')
         .lineWidth(1)
         .stroke();
    };

    // Draw all basic fields
    drawField('Transaction ID', transaction.transactionId, yPos);
    yPos += lineHeight;

    drawField('Date (Transaction Created)', transactionDate, yPos);
    yPos += lineHeight;

    drawField('Time(Transaction Created)', transaction.time, yPos);
    yPos += lineHeight;

    drawField('Party 1 (Creator)', transaction.userEmail, yPos);
    yPos += lineHeight;

    drawField('Party 2 (Counterparty)', transaction.counterpartyEmail, yPos);
    yPos += lineHeight;

    drawField('Original Amount', `${transaction.amount} ${transaction.currency}`, yPos);
    yPos += lineHeight;

    // Show remaining amount if partially paid
    if (transaction.isPartiallyPaid) {
      drawField('Remaining Amount', `${transaction.remainingAmount.toFixed(2)} ${transaction.currency}`, yPos);
      yPos += lineHeight;
    }

    drawField('Place', transaction.place || 'Not specified', yPos);
    yPos += lineHeight;

    // Description (if exists)
    if (transaction.description) {
      const descText = transaction.description.length > 60 
        ? transaction.description.substring(0, 60) + '...' 
        : transaction.description;
      drawField('Description', descText, yPos);
      yPos += lineHeight;
    }

    // Interest details section (if applicable)
    if (transaction.interestType && transaction.interestType !== 'none') {
      yPos += 20;
      
      doc.fillColor('#000000')
         .fontSize(13)
         .font('Helvetica-Bold')
         .text('INTEREST DETAILS', leftMargin, yPos);
      
      yPos += 30;

      drawField('Interest Type', transaction.interestType.toUpperCase(), yPos);
      yPos += lineHeight;

      drawField('Interest Rate', `${transaction.interestRate}% per annum`, yPos);
      yPos += lineHeight;

      if (transaction.compoundingFrequency && transaction.interestType === 'compound') {
        drawField('Compounding Frequency', `${transaction.compoundingFrequency}x per year`, yPos);
        yPos += lineHeight;
      }

      if (transaction.expectedReturnDate) {
        const returnDate = new Date(transaction.expectedReturnDate).toLocaleDateString('en-US', {
          year: 'numeric',
          month: 'long',
          day: 'numeric'
        });
        drawField('Expected Return Date', returnDate, yPos);
        yPos += lineHeight;
      }

      if (transaction.totalAmountWithInterest && transaction.totalAmountWithInterest !== transaction.amount) {
        drawField('Total with Interest', `${transaction.totalAmountWithInterest.toFixed(2)} ${transaction.currency}`, yPos);
        yPos += lineHeight;
      }
    }

    // Partial Payments section (if applicable)
    if (transaction.partialPayments && transaction.partialPayments.length > 0) {
      yPos += 20;
      
      doc.fillColor('#000000')
         .fontSize(13)
         .font('Helvetica-Bold')
         .text('PARTIAL PAYMENTS', leftMargin, yPos);
      
      yPos += 30;

      // Show partial payments count and total paid
      const totalPaid = transaction.partialPayments.reduce((sum, p) => sum + p.amount, 0);
      drawField('Payments Made', `${transaction.partialPayments.length} payment(s)`, yPos);
      yPos += lineHeight;

      drawField('Total Paid', `${totalPaid.toFixed(2)} ${transaction.currency}`, yPos);
      yPos += lineHeight;

      // Add note about payment history
      doc.fillColor('#6B7280')
         .fontSize(9)
         .font('Helvetica-Oblique')
         .text('View full payment history in the app', leftMargin, yPos);
      yPos += 25;
    }

    // Status section
    yPos += 20;
    
    doc.fillColor('#000000')
       .fontSize(13)
       .font('Helvetica-Bold')
       .text('CLEARANCE STATUS', leftMargin, yPos);
    
    yPos += 30;

    drawField('User Cleared', transaction.userCleared ? 'Yes' : 'No', yPos);
    yPos += lineHeight;

    drawField('Counterparty Cleared', transaction.counterpartyCleared ? 'Yes' : 'No', yPos);
    yPos += lineHeight;

    const fullyCleared = transaction.userCleared && transaction.counterpartyCleared;
    drawField('Transaction Status', fullyCleared ? 'FULLY CLEARED' : 'PENDING', yPos);

    // Footer at the bottom
    doc.fillColor('#6B7280')
       .fontSize(10)
       .font('Helvetica')
       .text('Thank you for using LenDen!', 0, 780, { 
         align: 'center',
         width: 595.28
       });

    doc.end();

  } catch (err) {
    res.status(500).json({ error: 'Failed to generate receipt' });
  }
};

exports.createTransactionWithCoins = async (req, res) => {
  const pricing = await getCoinPricing();
  const TRANSACTION_COST = pricing.secureTransactionCost;
  const USER_TRANSACTION_DAILY_LIMIT = 2;
  try {
    const {
      amount,
      currency,
      date,
      time,
      place,
      counterpartyEmail,
      userEmail,
      role, // 'lender' or 'borrower'
      interestType,
      interestRate,
      expectedReturnDate,
      compoundingFrequency,
      description,
      category
    } = req.body;

    const user = await User.findById(req.user._id).select(
      'email blockedUsers lenDenCoins freeUserTransactionsRemaining'
    );
    if (!user) return res.status(400).json({ error: 'User not found' });

    if (user.email !== userEmail) {
      return res.status(403).json({ error: 'User email does not match authenticated user.' });
    }

    // Validate required fields
    if (!amount || !currency || !date || !time || !place || !counterpartyEmail || !userEmail || !role) {
      return res.status(400).json({ error: 'All fields are required' });
    }
    const parsedAmount = parseFloat(amount);
    if (!parsedAmount || parsedAmount <= 0 || !isFinite(parsedAmount)) {
      return res.status(400).json({ error: 'Amount must be a positive number' });
    }
    if (!['lender', 'borrower'].includes(role)) {
      return res.status(400).json({ error: 'Role must be lender or borrower' });
    }

    // Handle interest validation - make it optional
    if (interestType && !['simple', 'compound', 'none'].includes(interestType)) {
      return res.status(400).json({ error: 'Interest type must be simple, compound, or none' });
    }
    if (interestType === 'compound' && (!compoundingFrequency || isNaN(compoundingFrequency))) {
      return res.status(400).json({ error: 'Compounding frequency required for compound interest' });
    }
    
    // Set default interest type if not provided
    const finalInterestType = interestType || 'none';
    const finalInterestRate = (finalInterestType === 'none') ? null : interestRate;
    const finalExpectedReturnDate = expectedReturnDate || null;
    const finalCompoundingFrequency = (finalInterestType === 'none') ? null : compoundingFrequency;

    // Check if both emails exist
    const counterparty = await User.findOne({ email: counterpartyEmail }).select(
      'email blockedUsers'
    );
    if (!counterparty) return res.status(400).json({ error: 'Counterparty email not registered' });
    if (isBlockedBy(user, counterparty)) {
      return res.status(403).json({
        error: 'You have blocked this user. Unblock to proceed.',
      });
    }
    if (isBlockedBy(counterparty, user)) {
      return res.status(403).json({
        error: 'You cannot add this user because they have blocked you.',
      });
    }

    const subscribed = await isSubscribed(user._id);
    const { start, end } = getTodayRange();
    const todayCount = await Transaction.countDocuments({
      userEmail: user.email,
      createdAt: { $gte: start, $lte: end },
    });
    const accessError = validateCoinCreationAccess({
      subscribed,
      freeRemaining: user.freeUserTransactionsRemaining,
      dailyCount: todayCount,
      dailyLimit: USER_TRANSACTION_DAILY_LIMIT,
      dailyLimitMessage:
        'Daily limit reached: You can create 2 user transactions per day.',
      coinBalance: user.lenDenCoins,
      coinCost: TRANSACTION_COST,
      featureLabel: 'secure transaction',
    });
    if (accessError && accessError.error) {
      return res.status(accessError.status).json({ error: accessError.error });
    }
    const accessWarning = accessError?.warning;

    // Handle photos (images only)
    let photos = [];
    if (req.files && req.files.length > 0) {
      for (const file of req.files) {
        if (!allowedMimeTypes.includes(file.mimetype)) {
          return res.status(400).json({ error: 'Invalid file type. Only PNG, JPG, JPEG allowed.' });
        }
        photos.push(file.buffer.toString('base64'));
      }
    }

    // Calculate total amount with interest if applicable
    let totalAmountWithInterest = amount;
    if (finalInterestType && finalInterestRate) {
      if (finalInterestType === 'simple') {
        // For new transactions, no interest has accumulated yet
        totalAmountWithInterest = amount;
      } else if (finalInterestType === 'compound') {
        // For new transactions, no interest has accumulated yet
        totalAmountWithInterest = amount;
      }
    }

    const updatedUser = await User.findOneAndUpdate(
      { _id: user._id, lenDenCoins: { $gte: TRANSACTION_COST } },
      { $inc: { lenDenCoins: -TRANSACTION_COST } },
      { new: true }
    );
    if (!updatedUser) {
      return res.status(400).json({ error: 'Insufficient LenDen coins to create this transaction.' });
    }
    user.lenDenCoins = updatedUser.lenDenCoins;
    await recordCoinLedgerEntry({
      userId: user._id,
      direction: 'spent',
      coins: TRANSACTION_COST,
      source: 'secure_transaction_with_coins',
      title: 'Secure Transaction Created With Coins',
      description: `Spent ${TRANSACTION_COST} LenDen coins to create a secure transaction with ${counterpartyEmail}.`,
      metadata: {
        counterpartyEmail,
        amount,
        currency,
        role,
      },
    });

    // Save transaction — if this fails, refund coins so the user is not penalised.
    let transaction;
    try {
      transaction = await Transaction.create({
        amount,
        currency,
        date,
        time,
        place,
        photos,
        counterpartyEmail,
        userEmail,
        role,
        interestType: finalInterestType,
        interestRate: finalInterestRate,
        expectedReturnDate: finalExpectedReturnDate,
        compoundingFrequency: finalCompoundingFrequency,
        description: description || '',
        category: category || 'other',
        remainingAmount: totalAmountWithInterest,
        totalAmountWithInterest: totalAmountWithInterest
      });
    } catch (saveErr) {
      await User.findByIdAndUpdate(user._id, { $inc: { lenDenCoins: TRANSACTION_COST } });
      await recordCoinLedgerEntry({
        userId: user._id,
        direction: 'earned',
        coins: TRANSACTION_COST,
        source: 'refund_secure_transaction_with_coins',
        title: 'Refund: Secure Transaction Creation Failed',
        description: `Refunded ${TRANSACTION_COST} coins after transaction creation failed.`,
        metadata: { error: saveErr.message },
      });
      throw saveErr;
    }
    const referralReward = await processReferralRewardOnFirstCreation(req.user._id);

    // Log activity for both users with creator context
    try {
      const user = await User.findOne({ email: userEmail });
      const counterparty = await User.findOne({ email: counterpartyEmail });

      // Determine who created the transaction (the user making the request)
      const creatorInfo = {
        creatorId: user._id,
        creatorEmail: userEmail
      };

      if (user) {
        await logTransactionActivity(user._id, 'transaction_created_with_coins', transaction, {}, creatorInfo);
      }
      if (counterparty) {
        await logTransactionActivity(counterparty._id, 'transaction_created_with_coins', transaction, {}, creatorInfo);
      }
    } catch (e) {
      console.error('Failed to log transaction activity:', e);
    }
    
    res.status(201).json({ 
      success: true, 
      message: "Transaction created successfully with LenDen coins",
      transactionId: transaction.transactionId, 
      transaction,
      lenDenCoins: user.lenDenCoins,
      warning: accessWarning,
      referralReward
    });

    // Send receipt emails to both parties (fire and forget)
    try {
      sendTransactionReceipt(userEmail, transaction, counterpartyEmail);
      sendTransactionReceipt(counterpartyEmail, transaction, userEmail);
    } catch (e) {
      console.error('Failed to send transaction receipt:', e);
    }
  } catch (err) {
    res.status(500).json({ error: 'Failed to create transaction' });
  }
};

// Create a new transaction
exports.createTransaction = async (req, res) => {
  try {
    const {
      amount,
      currency,
      date,
      time,
      place,
      counterpartyEmail,
      userEmail,
      role, // 'lender' or 'borrower'
      interestType,
      interestRate,
      expectedReturnDate,
      compoundingFrequency,
      description,
      category
    } = req.body;

    const user = await User.findById(req.user._id).select('email blockedUsers freeUserTransactionsRemaining');
    if (!user) return res.status(400).json({ error: 'User not found' });

    if (user.email !== userEmail) {
      return res.status(403).json({ error: 'User email does not match authenticated user.' });
    }

    // Validate required fields
    if (!amount || !currency || !date || !time || !place || !counterpartyEmail || !userEmail || !role) {
      return res.status(400).json({ error: 'All fields are required' });
    }
    const parsedAmount = parseFloat(amount);
    if (!parsedAmount || parsedAmount <= 0 || !isFinite(parsedAmount)) {
      return res.status(400).json({ error: 'Amount must be a positive number' });
    }
    if (!['lender', 'borrower'].includes(role)) {
      return res.status(400).json({ error: 'Role must be lender or borrower' });
    }

    // Handle interest validation - make it optional
    if (interestType && !['simple', 'compound', 'none'].includes(interestType)) {
      return res.status(400).json({ error: 'Interest type must be simple, compound, or none' });
    }
    if (interestType === 'compound' && (!compoundingFrequency || isNaN(compoundingFrequency))) {
      return res.status(400).json({ error: 'Compounding frequency required for compound interest' });
    }
    
    // Set default interest type if not provided
    const finalInterestType = interestType || 'none';
    const finalInterestRate = (finalInterestType === 'none') ? null : interestRate;
    const finalExpectedReturnDate = expectedReturnDate || null;
    const finalCompoundingFrequency = (finalInterestType === 'none') ? null : compoundingFrequency;

    // Check if both emails exist
    const counterparty = await User.findOne({ email: counterpartyEmail }).select(
      'email blockedUsers'
    );
    if (!counterparty) return res.status(400).json({ error: 'Counterparty email not registered' });
    if (isBlockedBy(user, counterparty)) {
      return res.status(403).json({
        error: 'You have blocked this user. Unblock to proceed.',
      });
    }
    if (isBlockedBy(counterparty, user)) {
      return res.status(403).json({
        error: 'You cannot add this user because they have blocked you.',
      });
    }

    const subscribed = await isSubscribed(user._id);
    if (!subscribed) {
      const { start, end } = getTodayRange();
      const todayCount = await Transaction.countDocuments({
        userEmail: user.email,
        createdAt: { $gte: start, $lte: end },
      });
      if (todayCount >= 2) {
        return res.status(429).json({
          error: 'Daily limit reached: You can create 2 user transactions per day.',
        });
      }
    }

    // Handle photos (images only)
    let photos = [];
    if (req.files && req.files.length > 0) {
      for (const file of req.files) {
        if (!allowedMimeTypes.includes(file.mimetype)) {
          return res.status(400).json({ error: 'Invalid file type. Only PNG, JPG, JPEG allowed.' });
        }
        photos.push(file.buffer.toString('base64'));
      }
    }

    // Calculate total amount with interest if applicable
    let totalAmountWithInterest = amount;
    if (finalInterestType && finalInterestRate) {
      if (finalInterestType === 'simple') {
        // For new transactions, no interest has accumulated yet
        totalAmountWithInterest = amount;
      } else if (finalInterestType === 'compound') {
        // For new transactions, no interest has accumulated yet
        totalAmountWithInterest = amount;
      }
    }

    // Save transaction
    const transaction = await Transaction.create({
      amount,
      currency,
      date,
      time,
      place,
      photos,
      counterpartyEmail,
      userEmail,
      role,
      interestType: finalInterestType,
      interestRate: finalInterestRate,
      expectedReturnDate: finalExpectedReturnDate,
      compoundingFrequency: finalCompoundingFrequency,
      description: description || '',
      category: category || 'other',
      remainingAmount: totalAmountWithInterest,
      totalAmountWithInterest: totalAmountWithInterest
    });
    const referralReward = await processReferralRewardOnFirstCreation(req.user._id);
    
    // Decrement free-transaction counter in DB so the UI value stays accurate.
    let updatedFreeRemaining = user.freeUserTransactionsRemaining;
    if (!subscribed && user.freeUserTransactionsRemaining > 0) {
      const updatedUser = await User.findByIdAndUpdate(
        user._id,
        { $inc: { freeUserTransactionsRemaining: -1 } },
        { new: true }
      ).select('freeUserTransactionsRemaining');
      if (updatedUser) updatedFreeRemaining = updatedUser.freeUserTransactionsRemaining;
    }

    // Log activity for both users with creator context
    try {
      const [creatorDoc, cpDoc] = await Promise.all([
        User.findOne({ email: userEmail }).select('_id notificationSettings'),
        User.findOne({ email: counterpartyEmail }).select('_id notificationSettings'),
      ]);

      const creatorInfo = {
        creatorId: creatorDoc?._id ?? req.user._id,
        creatorEmail: userEmail
      };

      if (creatorDoc) {
        await logTransactionActivity(creatorDoc._id, 'transaction_created', transaction, {}, creatorInfo);
      }
      if (cpDoc) {
        await logTransactionActivity(cpDoc._id, 'transaction_created', transaction, {}, creatorInfo);
        if (cpDoc.notificationSettings?.transactionNotifications !== false) {
          await Notification.create({
            sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
            recipients: [cpDoc._id], recipientModel: 'User', category: 'transaction',
            message: `${userEmail} recorded a ${role} transaction of ₹${amount} with you.`,
          });
        }
        sendToUser(User, cpDoc._id, { title: 'New Transaction 🔐', body: `${userEmail} recorded a transaction with you.`, data: { type: 'quick_transaction' } });
      }
    } catch (e) {
      console.error('Failed to log transaction activity:', e);
    }

    // Award gift card every 5 user transactions (guaranteed, randomized within window)
    const userTxnCount = await Transaction.countDocuments({ userEmail });
    let awardedCard = null;
    if (shouldAwardGiftCard(user._id, userTxnCount, 5)) {
      awardedCard = await awardGiftCard(user._id, 'userTransaction');
    }

    res.json({
      success: true,
      message: "Transaction created successfully",
      transactionId: transaction.transactionId,
      transaction,
      freeUserTransactionsRemaining: updatedFreeRemaining,
      referralReward,
      giftCardAwarded: awardedCard ? true : false,
      awardedCard: awardedCard
    });

    // Send receipt emails to both parties (fire and forget)
    try {
      sendTransactionReceipt(userEmail, transaction, counterpartyEmail);
      sendTransactionReceipt(counterpartyEmail, transaction, userEmail);
    } catch (e) {
      console.error('Failed to send transaction receipt:', e);
    }
  } catch (err) {
    res.status(500).json({ error: 'Failed to create transaction' });
  }
};

// Check if email exists in user schema
exports.checkEmailExists = async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) return res.status(400).json({ error: 'Email is required' });
    const user = await User.findOne({ email });
    if (user) return res.json({ exists: true });
    return res.json({ exists: false });
  } catch (err) {
    handleRouteError(res, err);
  }
};

// Send OTP to counterparty email
exports.sendCounterpartyOTP = async (req, res) => {
  const { email } = req.body;
  if (!email) return res.status(400).json({ error: 'Email is required' });
  try {
    // Validate the target is a registered LenDen user — prevents using this as a spam vector.
    const target = await User.findOne({ email: email.toLowerCase().trim() }).select('_id');
    if (!target) return res.status(404).json({ error: 'No LenDen account found for this email.' });
    await lendingborrowingotp.resendOtp(email);
    res.json({ message: 'OTP sent to counterparty email' });
  } catch (err) {
    res.status(500).json({ error: 'Failed to send OTP' });
  }
};

// Verify counterparty OTP
exports.verifyCounterpartyOTP = async (req, res) => {
  const { email, otp } = req.body;
  if (!email || !otp) return res.status(400).json({ error: 'Email and OTP are required' });
  const valid = lendingborrowingotp.verifyLendingBorrowingOtp(email, otp);
  if (valid) return res.json({ verified: true });
  return res.status(400).json({ verified: false, error: 'Invalid or expired OTP' });
};

// Send OTP to logged-in user email
exports.sendUserOTP = async (req, res) => {
  const { email } = req.body;
  if (!email) return res.status(400).json({ error: 'Email is required' });
  // The OTP must go to the authenticated user's own email only.
  if (email.toLowerCase().trim() !== req.user.email.toLowerCase().trim()) {
    return res.status(403).json({ error: 'You can only request an OTP for your own account email.' });
  }
  try {
    await lendingborrowingotp.resendOtp(email);
    res.json({ message: 'OTP sent to user email' });
  } catch (err) {
    res.status(500).json({ error: 'Failed to send OTP' });
  }
};

// Verify logged-in user OTP
exports.verifyUserOTP = async (req, res) => {
  const { email, otp } = req.body;
  if (!email || !otp) return res.status(400).json({ error: 'Email and OTP are required' });
  const valid = lendingborrowingotp.verifyLendingBorrowingOtp(email, otp);
  if (valid) return res.json({ verified: true });
  return res.status(400).json({ verified: false, error: 'Invalid or expired OTP' });
};

// Get all transactions for a user, grouped by role
exports.getUserTransactions = async (req, res) => {
  try {
    const {
      filter = 'all',
      clearanceFilter = 'all',
      partialClearedType = 'my',
      interestTypeFilter = 'all',
      startDate,
      endDate,
      minAmount,
      maxAmount,
      search,
      sortBy = 'created',
      sortOrder = 'desc',
      favouritesOnly,
    } = req.query;

    // Always use the authenticated user's email â€” never trust the query param.
    const email = req.user.email;

    // Base query: user is party to the transaction (ownership clause, never overwritten)
    const ownershipClause = [{ userEmail: email }, { counterpartyEmail: email }];
    const baseQuery = { $or: ownershipClause };

    // Date range filter
    if (startDate || endDate) {
      baseQuery.date = {};
      if (startDate) baseQuery.date.$gte = new Date(startDate);
      if (endDate) baseQuery.date.$lte = new Date(endDate);
    }

    // Amount range filter
    if (minAmount || maxAmount) {
      baseQuery.amount = {};
      if (minAmount) baseQuery.amount.$gte = parseFloat(minAmount);
      if (maxAmount) baseQuery.amount.$lte = parseFloat(maxAmount);
    }

    // Interest type filter
    if (interestTypeFilter && interestTypeFilter !== 'all') {
      if (interestTypeFilter === 'with_interest') {
        baseQuery.interestType = { $nin: ['none', null, ''] };
      } else {
        baseQuery.interestType = interestTypeFilter;
      }
    }

    // Text search â€” combine with ownership via $and so the search
    // can never bypass the party-membership check.
    if (search && search.trim()) {
      const searchRegex = new RegExp(search.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
      delete baseQuery.$or; // move ownership into $and
      baseQuery.$and = [
        { $or: ownershipClause },
        { $or: [
          { description: searchRegex },
          { place: searchRegex },
          { transactionId: searchRegex },
          { userEmail: searchRegex },
          { counterpartyEmail: searchRegex },
        ]},
      ];
    }

    // Favourites only
    if (favouritesOnly === 'true') {
      baseQuery.favourite = email;
    }

    // Sort field mapping
    const sortFieldMap = {
      created: 'createdAt',
      transaction_date: 'date',
      amount: 'amount',
      status: 'userCleared',
    };
    const sortField = sortFieldMap[sortBy] || 'createdAt';
    const sortDir = sortOrder === 'asc' ? 1 : -1;

    const page = Math.max(1, parseInt(req.query.page) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit) || 20));
    const skip = (page - 1) * limit;

    const [transactions, totalCount] = await Promise.all([
      Transaction.find(baseQuery)
        .sort({ [sortField]: sortDir })
        .skip(skip)
        .limit(limit)
        .select('-photos'),
      Transaction.countDocuments(baseQuery),
    ]);

    // Group into lending and borrowing
    let lending = transactions.filter(
      (t) =>
        (t.role === 'lender' && t.userEmail === email) ||
        (t.role === 'borrower' && t.counterpartyEmail === email)
    );
    let borrowing = transactions.filter(
      (t) =>
        (t.role === 'borrower' && t.userEmail === email) ||
        (t.role === 'lender' && t.counterpartyEmail === email)
    );

    // Apply clearance filter
    const applyClearanceFilter = (list) => {
      if (!clearanceFilter || clearanceFilter === 'all') return list;
      return list.filter((t) => {
        const userCleared = t.userCleared === true;
        const counterpartyCleared = t.counterpartyCleared === true;
        const hasPartialPayment =
          t.isPartiallyPaid === true ||
          (Array.isArray(t.partialPayments) && t.partialPayments.length > 0);

        if (clearanceFilter === 'totally_cleared') {
          return userCleared && counterpartyCleared;
        }
        if (clearanceFilter === 'totally_uncleared') {
          return !userCleared && !counterpartyCleared && !hasPartialPayment;
        }
        if (clearanceFilter === 'partially_cleared') {
          // One side cleared but not both, OR has partial payments
          const oneSideCleared = userCleared !== counterpartyCleared;
          if (!oneSideCleared && !hasPartialPayment) return false;
          if (partialClearedType === 'my') {
            // My side cleared but other not
            if (t.userEmail === email) {
              return userCleared && !counterpartyCleared;
            } else {
              return counterpartyCleared && !userCleared;
            }
          } else {
            // Other side cleared but not mine
            if (t.userEmail === email) {
              return counterpartyCleared && !userCleared;
            } else {
              return userCleared && !counterpartyCleared;
            }
          }
        }
        return true;
      });
    };

    // Apply filter (lending/borrowing/all)
    const filterLower = (filter || 'all').toLowerCase();
    if (filterLower === 'lending') {
      borrowing = [];
    } else if (filterLower === 'borrowing') {
      lending = [];
    }

    lending = applyClearanceFilter(lending);
    borrowing = applyClearanceFilter(borrowing);

    res.json({
      lending,
      borrowing,
      totalTransactions: totalCount,
      page,
      limit,
      hasMore: skip + transactions.length < totalCount,
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch transactions' });
  }
};

// Clear transaction endpoint
exports.clearTransaction = async (req, res) => {
  try {
    const { transactionId, bothSides } = req.body;
    const email = req.user.email;
    if (!transactionId) return res.status(400).json({ error: 'transactionId required' });
    const transaction = await Transaction.findOne({ transactionId });
    if (!transaction) return res.status(404).json({ error: 'Transaction not found' });
    let updated = false;
    let otherPartyEmail = null;
    if (transaction.userEmail === email) {
      if (!transaction.userCleared) {
        transaction.userCleared = true;
        updated = true;
        otherPartyEmail = transaction.counterpartyEmail;
      }
    } else if (transaction.counterpartyEmail === email) {
      if (!transaction.counterpartyCleared) {
        transaction.counterpartyCleared = true;
        updated = true;
        otherPartyEmail = transaction.userEmail;
      }
    } else {
      return res.status(403).json({ error: 'You are not a party to this transaction' });
    }
    // When a real wallet payment was made, clear both sides at once.
    // Require paidAmount > 0 so a caller cannot dual-clear with amount:0.
    if (bothSides && updated) {
      const requestedAmount = req.body.amount ? Number(req.body.amount) : 0;
      const serverRemaining = transaction.remainingAmount ?? transaction.amount;
      const paidAmount = Math.min(requestedAmount, serverRemaining > 0 ? serverRemaining : requestedAmount);

      if (paidAmount <= 0) {
        return res.status(400).json({ error: 'A positive payment amount is required to clear both sides.' });
      }

      transaction.userCleared = true;
      transaction.counterpartyCleared = true;

      const lenderEmail = transaction.role === 'lender'
        ? transaction.userEmail
        : transaction.counterpartyEmail;
      const paidBy = email.toLowerCase() === lenderEmail.toLowerCase() ? 'lender' : 'borrower';
      const paymentMethod = req.body.paymentMethod || 'wallet';
      transaction.partialPayments.push({
        amount: paidAmount,
        paidBy,
        paidAt: new Date(),
        description: paymentMethod === 'wallet'
          ? 'Pay Now via LenDen Wallet'
          : 'Pay Now payment',
        paymentMethod,
      });
      transaction.isPartiallyPaid = true;
    }
    if (updated) {
      await transaction.save();
      try {
        sendTransactionClearedNotification(otherPartyEmail, transaction, email);
      } catch (e) {
        console.error('Failed to send cleared notification:', e);
      }
      try {
        const creatorInfo = { creatorId: req.user._id, creatorEmail: email };
        // req.user._id is the current user's ObjectId â€” only the counterparty needs a lookup
        const otherPartyDoc = await User.findOne({ email: otherPartyEmail }).select('_id');
        await logTransactionActivity(req.user._id, 'transaction_cleared', transaction, {
          clearedBy: email,
          otherParty: otherPartyEmail
        }, creatorInfo);
        if (otherPartyDoc) {
          await logTransactionActivity(otherPartyDoc._id, 'transaction_cleared', transaction, {
            clearedBy: email,
            otherParty: otherPartyEmail
          }, creatorInfo);
          // Notify the other party in-app
          const otherPartyFull = await User.findById(otherPartyDoc._id).select('notificationSettings');
          if (otherPartyFull?.notificationSettings?.transactionNotifications !== false) {
            await Notification.create({
              sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
              recipients: [otherPartyDoc._id], recipientModel: 'User', category: 'transaction',
              message: `${email} cleared their side of the transaction. It is now ${transaction.userCleared && transaction.counterpartyCleared ? 'fully cleared' : 'partially cleared'}.`,
            });
          }
          sendToUser(User, otherPartyDoc._id, { title: 'New Transaction 🔐', body: `${email} cleared their side of the transaction.`, data: { type: 'quick_transaction' } });
        }
      } catch (e) {
        console.error('Failed to log transaction activity:', e);
      }
    }
    res.json({ success: true, userCleared: transaction.userCleared, counterpartyCleared: transaction.counterpartyCleared, fullyCleared: transaction.userCleared && transaction.counterpartyCleared });
  } catch (err) {
    console.error('clearTransaction error:', err);
    if (err.name === 'VersionError') {
      return res.status(409).json({
        error: 'This transaction was updated elsewhere at the same time. Please try again.',
      });
    }
    res.status(500).json({ error: 'Failed to clear transaction' });
  }
};

// Delete transaction endpoint
exports.deleteTransaction = async (req, res) => {
  try {
    const { transactionId } = req.body;
    const email = req.user.email;
    if (!transactionId) {
      return res.status(400).json({ error: 'transactionId required' });
    }

    const transaction = await Transaction.findOne({ transactionId });
    if (!transaction) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    if (transaction.userEmail !== email && transaction.counterpartyEmail !== email) {
      return res.status(403).json({ error: 'You are not a party to this transaction' });
    }

    if (!transaction.userCleared || !transaction.counterpartyCleared) {
      return res.status(400).json({
        error: 'Cannot delete transaction. Both parties must clear the transaction first.',
        userCleared: transaction.userCleared,
        counterpartyCleared: transaction.counterpartyCleared
      });
    }

    await Transaction.deleteOne({ transactionId });

    res.json({ success: true, message: 'Transaction deleted successfully' });
  } catch (err) {
    console.error('deleteTransaction error:', err);
    res.status(500).json({ error: 'Failed to delete transaction' });
  }
};

// Send OTP for partial payment verification
// â”€â”€ Transaction PIN alternatives â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Verify the PAYER's own 6-digit transaction PIN as an alternative to their
// own email OTP step in the two-sided Secure-Transaction partial-payment flow.
// On success, marks the same server-side flag that verifyPartialPaymentOTP sets
// so processPartialPayment can proceed.
exports.verifyPartialPaymentPin = async (req, res) => {
  try {
    const { transactionId, pin } = req.body;
    if (!transactionId || !pin || !/^\d{6}$/.test(pin)) {
      return res.status(400).json({ error: 'transactionId and a 6-digit PIN are required' });
    }

    const transaction = await Transaction.findOne({ transactionId });
    if (!transaction) return res.status(404).json({ error: 'Transaction not found' });

    const cleanEmail = (req.user.email || '').toLowerCase().trim();
    let role;
    if (transaction.userEmail.toLowerCase() === cleanEmail) {
      role = transaction.role;
    } else if (transaction.counterpartyEmail.toLowerCase() === cleanEmail) {
      role = transaction.role === 'lender' ? 'borrower' : 'lender';
    } else {
      return res.status(403).json({ error: 'You are not a party to this transaction' });
    }

    const user = await User.findById(req.user._id).select('walletPin walletPinAttempts walletPinLockedUntil');
    if (!user || !user.walletPin) {
      return res.status(400).json({ error: 'No transaction PIN is set. Please use OTP or set a PIN in Settings first.' });
    }
    if (user.walletPinLockedUntil && user.walletPinLockedUntil > new Date()) {
      const mins = Math.ceil((user.walletPinLockedUntil - Date.now()) / 60000);
      return res.status(423).json({ error: `PIN is locked for ${mins} more minute${mins === 1 ? '' : 's'}.` });
    }

    const bcrypt = require('bcryptjs');
    const valid = await bcrypt.compare(String(pin), user.walletPin);
    if (!valid) {
      const newAttempts = (user.walletPinAttempts || 0) + 1;
      const lock = newAttempts >= 5
        ? { walletPinAttempts: 0, walletPinLockedUntil: new Date(Date.now() + 15 * 60 * 1000) }
        : { walletPinAttempts: newAttempts };
      await User.updateOne({ _id: user._id }, { $set: lock });
      const left = 5 - newAttempts;
      if (left <= 0) return res.status(423).json({ error: 'Too many wrong PINs. Locked for 15 minutes.' });
      return res.status(400).json({ error: `Incorrect PIN. ${left} attempt${left === 1 ? '' : 's'} remaining.` });
    }

    await User.updateOne({ _id: user._id }, { $set: { walletPinAttempts: 0 }, $unset: { walletPinLockedUntil: 1 } });
    lendingborrowingotp.markPartialPaymentVerified(transactionId, role);
    res.json({ verified: true, role });
  } catch (err) {
    res.status(500).json({ error: 'Failed to verify PIN' });
  }
};

// Verify the logged-in user's transaction PIN as an alternative to the
// self-OTP step during Secure Transaction CREATION. Returns { verified: true }
// on success so the frontend can set its _userVerified flag.
exports.verifyTransactionCreationPin = async (req, res) => {
  try {
    const { pin } = req.body;
    if (!pin || !/^\d{6}$/.test(pin)) {
      return res.status(400).json({ error: 'A 6-digit PIN is required' });
    }

    const user = await User.findById(req.user._id).select('walletPin walletPinAttempts walletPinLockedUntil');
    if (!user || !user.walletPin) {
      return res.status(400).json({ error: 'No transaction PIN is set. Please use OTP or set a PIN in Settings first.' });
    }
    if (user.walletPinLockedUntil && user.walletPinLockedUntil > new Date()) {
      const mins = Math.ceil((user.walletPinLockedUntil - Date.now()) / 60000);
      return res.status(423).json({ error: `PIN is locked for ${mins} more minute${mins === 1 ? '' : 's'}.` });
    }

    const bcrypt = require('bcryptjs');
    const valid = await bcrypt.compare(String(pin), user.walletPin);
    if (!valid) {
      const newAttempts = (user.walletPinAttempts || 0) + 1;
      const lock = newAttempts >= 5
        ? { walletPinAttempts: 0, walletPinLockedUntil: new Date(Date.now() + 15 * 60 * 1000) }
        : { walletPinAttempts: newAttempts };
      await User.updateOne({ _id: user._id }, { $set: lock });
      const left = 5 - newAttempts;
      if (left <= 0) return res.status(423).json({ error: 'Too many wrong PINs. Locked for 15 minutes.' });
      return res.status(400).json({ error: `Incorrect PIN. ${left} attempt${left === 1 ? '' : 's'} remaining.` });
    }

    await User.updateOne({ _id: user._id }, { $set: { walletPinAttempts: 0 }, $unset: { walletPinLockedUntil: 1 } });
    res.json({ verified: true });
  } catch (err) {
    res.status(500).json({ error: 'Failed to verify PIN' });
  }
};

exports.sendPartialPaymentOTP = async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) {
      return res.status(400).json({ error: 'Email is required' });
    }

    // Check if email exists in user schema
    const user = await User.findOne({ email });
    if (!user) {
      return res.status(400).json({ error: 'Email not registered' });
    }

    // Send OTP
    await lendingborrowingotp.resendOtp(email);
    res.json({ message: 'OTP sent successfully' });
  } catch (err) {
    res.status(500).json({ error: 'Failed to send OTP' });
  }
};

// Verify OTP for partial payment. Requires transactionId so we can record
// server-side which role ('lender'/'borrower') just verified â€” processPartialPayment
// checks this record rather than trusting client-sent booleans.
exports.verifyPartialPaymentOTP = async (req, res) => {
  try {
    const { email, otp, transactionId } = req.body;
    if (!email || !otp || !transactionId) {
      return res.status(400).json({ error: 'Email, OTP and transactionId are required' });
    }

    const transaction = await Transaction.findOne({ transactionId });
    if (!transaction) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    const cleanEmail = email.toLowerCase().trim();

    // Each party can only verify their own OTP — prevents one user from verifying the other's side.
    if (cleanEmail !== req.user.email.toLowerCase().trim()) {
      return res.status(403).json({ error: 'You can only verify your own email OTP.' });
    }

    let role;
    if (transaction.userEmail.toLowerCase() === cleanEmail) {
      role = transaction.role;
    } else if (transaction.counterpartyEmail.toLowerCase() === cleanEmail) {
      role = transaction.role === 'lender' ? 'borrower' : 'lender';
    } else {
      return res.status(403).json({ error: 'Email does not match this transaction' });
    }

    const valid = lendingborrowingotp.verifyLendingBorrowingOtp(email, otp);
    if (!valid) {
      return res.status(400).json({ verified: false, error: 'Invalid or expired OTP' });
    }

    lendingborrowingotp.markPartialPaymentVerified(transactionId, role);
    res.json({ verified: true, role });
  } catch (err) {
    res.status(500).json({ error: 'Failed to verify OTP' });
  }
};

// Process partial payment (and full "Pay Now" payments, which call this same
// endpoint with amount = remainingAmount). Both parties' OTP verification is
// checked server-side via lendingborrowingotp's short-lived verified-record
// store (set by verifyPartialPaymentOTP) rather than trusting client-sent
// booleans. The actual money movement is a real, atomic LenDen Wallet
// transfer between the lender and borrower â€” resolved from the transaction
// record itself, not from client-supplied emails â€” instead of just writing a
// ledger entry with no balance change.
exports.processPartialPayment = async (req, res) => {
  const session = await mongoose.startSession();
  try {
    const { transactionId, amount, description, paidBy } = req.body;

    if (!transactionId || !amount || !paidBy) {
      return res.status(400).json({ error: 'transactionId, amount and paidBy are required' });
    }

    if (!['lender', 'borrower'].includes(paidBy)) {
      return res.status(400).json({ error: 'paidBy must be lender or borrower' });
    }

    const transaction = await Transaction.findOne({ transactionId });
    if (!transaction) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    if (transaction.userCleared && transaction.counterpartyCleared) {
      return res.status(400).json({ error: 'This transaction has already been fully paid off.' });
    }

    // Resolve both parties from the transaction record itself â€” never from
    // client-supplied emails â€” so the payment can't be redirected.
    const lenderEmail = transaction.role === 'lender' ? transaction.userEmail : transaction.counterpartyEmail;
    const borrowerEmail = transaction.role === 'lender' ? transaction.counterpartyEmail : transaction.userEmail;

    // Atomically consume the verified flags before entering the session.
    // This prevents two concurrent requests from both passing the check and
    // both entering the session, which would cause a double-payment.
    const lenderVerified = lendingborrowingotp.isPartialPaymentVerified(transactionId, 'lender');
    const borrowerVerified = lendingborrowingotp.isPartialPaymentVerified(transactionId, 'borrower');
    if (!lenderVerified || !borrowerVerified) {
      return res.status(400).json({ error: 'Both parties must verify their OTP before payment can be processed' });
    }
    // Consume immediately — any concurrent duplicate request will now fail the check above.
    lendingborrowingotp.consumePartialPaymentVerified(transactionId);

    // Calculate interest on the current remaining amount (not the original amount)
    let currentRemainingAmount = transaction.remainingAmount || transaction.amount;
    let totalAmountWithInterest = currentRemainingAmount;
    
    if (transaction.interestType && transaction.interestRate) {
      // Get the last partial payment date or transaction date
      let lastPaymentDate = new Date(transaction.date);
      if (transaction.partialPayments && transaction.partialPayments.length > 0) {
        // Get the date of the last partial payment
        const lastPayment = transaction.partialPayments[transaction.partialPayments.length - 1];
        lastPaymentDate = new Date(lastPayment.paidAt);
      }
      
      const now = new Date();
      const daysDiff = Math.ceil((now - lastPaymentDate) / (1000 * 60 * 60 * 24));
      
      if (daysDiff > 0) { // Only calculate interest if time has passed
        if (transaction.interestType === 'simple') {
          totalAmountWithInterest = currentRemainingAmount + (currentRemainingAmount * transaction.interestRate * daysDiff / 365);
        } else if (transaction.interestType === 'compound') {
          // Standard formula: P*(1+r/n)^(n*t) where r=annual rate fraction, n=periods/yr, t=years
          const n = transaction.compoundingFrequency || 1;
          totalAmountWithInterest = currentRemainingAmount * Math.pow(1 + transaction.interestRate / 100 / n, n * daysDiff / 365);
        }
      }
    }

    // For display purposes, also calculate the total amount with interest from transaction date
    let displayTotalAmountWithInterest = transaction.amount;
    if (transaction.interestType && transaction.interestRate) {
      const transactionDate = new Date(transaction.date);
      const now = new Date();
      const daysDiff = Math.ceil((now - transactionDate) / (1000 * 60 * 60 * 24));

      if (daysDiff > 0) {
        if (transaction.interestType === 'simple') {
          displayTotalAmountWithInterest = transaction.amount + (transaction.amount * transaction.interestRate * daysDiff / 365);
        } else if (transaction.interestType === 'compound') {
          const n = transaction.compoundingFrequency || 1;
          displayTotalAmountWithInterest = transaction.amount * Math.pow(1 + transaction.interestRate / 100 / n, n * daysDiff / 365);
        }
      }
    }

    // Initialize remaining amount if not set (use == null to avoid treating 0 as unset)
    if (transaction.remainingAmount == null) {
      transaction.remainingAmount = totalAmountWithInterest;
      transaction.totalAmountWithInterest = totalAmountWithInterest;
    } else {
      // Update the total amount with interest for the current remaining amount
      transaction.totalAmountWithInterest = totalAmountWithInterest;
    }

    // Validate payment amount
    if (amount <= 0) {
      return res.status(400).json({ error: 'Payment amount must be greater than 0' });
    }

    if (amount > totalAmountWithInterest) {
      return res.status(400).json({ 
        error: 'Payment amount cannot exceed total amount with interest',
        totalAmountWithInterest: totalAmountWithInterest,
        remainingAmount: transaction.remainingAmount,
        currentAmountWithInterest: totalAmountWithInterest
      });
    }

    // Resolve payer/payee for the real wallet transfer. The wallet debit always
    // happens on the authenticated caller, so paidBy must match who's actually
    // calling â€” otherwise the ledger would record the wrong direction (and the
    // wrong party's wallet would be silently debited for what's labeled as the
    // other party's repayment).
    const payerEmail = (paidBy === 'lender' ? lenderEmail : borrowerEmail).toLowerCase().trim();
    const payeeEmail = (paidBy === 'lender' ? borrowerEmail : lenderEmail).toLowerCase().trim();
    if ((req.user.email || '').toLowerCase().trim() !== payerEmail) {
      return res.status(403).json({ error: 'You can only make a payment as yourself' });
    }
    const payee = await User.findOne({ email: payeeEmail }).select('_id email');
    if (!payee) {
      return res.status(404).json({ error: 'The other party is no longer on LenDen' });
    }

    let newBalance;
    await session.withTransaction(async () => {
      // Atomic check-and-debit â€” fails (returns null) if balance is insufficient,
      // so no partial state is possible under concurrent requests.
      const payer = await User.findOneAndUpdate(
        { _id: req.user._id, walletBalance: { $gte: amount } },
        { $inc: { walletBalance: -amount } },
        { new: true, session }
      );
      if (!payer) {
        throw Object.assign(new Error('Insufficient wallet balance'), {
          status: 400,
          userMessage: 'Insufficient LenDen wallet balance. Please top up your wallet and try again.',
        });
      }

      await User.findByIdAndUpdate(payee._id, { $inc: { walletBalance: amount } }, { session });

      await WalletTransaction.create([
        { user: payer._id, type: 'debit', amount, toEmail: payee.email, note: description || 'Secure transaction repayment', sourceType: 'secure' },
        { user: payee._id, type: 'credit', amount, fromEmail: payer.email, note: description || 'Secure transaction repayment', sourceType: 'secure' },
      ], { session });

      // Process the partial payment â€” round to 2 dp to avoid floating-point
      // artefacts (e.g. 100.5 - 100.5 = 1.77e-15) that would prevent clearing.
      const rawRemaining = totalAmountWithInterest - amount;
      transaction.remainingAmount = rawRemaining <= 0
        ? 0
        : Math.round(rawRemaining * 100) / 100;
      transaction.isPartiallyPaid = true;

      // Add to partial payments history
      transaction.partialPayments.push({
        amount: amount,
        paidBy: paidBy,
        paidAt: new Date(),
        description: description || '',
        paymentMethod: 'wallet',
      });

      // If remaining amount is 0 or effectively 0 (< 1 cent), mark as cleared
      if (transaction.remainingAmount <= 0) {
        transaction.userCleared = true;
        transaction.counterpartyCleared = true;
        transaction.remainingAmount = 0;
      }

      await transaction.save({ session });

      newBalance = payer.walletBalance;
    });

    // Log activity for partial payment - both parties get notified
    // req.user._id is the payer; payee._id was already fetched above (line ~1293).
    try {
      const creatorInfo = { creatorId: req.user._id, creatorEmail: payerEmail };
      await logTransactionActivity(req.user._id, 'partial_payment_made', transaction, {
        paymentAmount: amount,
        description: description || '',
        remainingAmount: transaction.remainingAmount
      }, creatorInfo);
      if (payee) {
        await logTransactionActivity(payee._id, 'partial_payment_received', transaction, {
          paymentAmount: amount,
          description: description || '',
          remainingAmount: transaction.remainingAmount
        }, creatorInfo);
      }
    } catch (e) {
      console.error('Failed to log transaction activity:', e);
    }

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
          message: `Partial payment of ₹${amount} sent to ${payeeEmail} successfully.`,
        }));
      }
      if (payeeUser?.notificationSettings?.transactionNotifications !== false) {
        notifs.push(Notification.create({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [payee._id], recipientModel: 'User', category: 'transaction',
          message: `You received a partial payment of ₹${amount} from ${payerEmail}.`,
        }));
      }
      sendToUser(User, payee._id, { title: 'New Transaction 🔐', body: `You received a partial payment of ₹${amount} from ${payerEmail}.`, data: { type: 'quick_transaction' } });
      return Promise.all(notifs);
    }).catch(() => {});

    res.json({
      success: true,
      message: 'Partial payment processed successfully',
      remainingAmount: transaction.remainingAmount,
      isFullyPaid: transaction.remainingAmount <= 0,
      displayTotalAmountWithInterest: displayTotalAmountWithInterest,
      balance: newBalance,
    });

  } catch (err) {
    res.status(err.status ?? 500).json({ error: err.userMessage || err.message || 'Failed to process partial payment' });
  } finally {
    session.endSession();
  }
};

// Get transaction details with partial payment history
exports.getTransactionDetails = async (req, res) => {
  try {
    const { transactionId } = req.params;
    if (!transactionId) {
      return res.status(400).json({ error: 'Transaction ID is required' });
    }

    const transaction = await Transaction.findOne({ transactionId });
    if (!transaction) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    const email = req.user.email;
    if (transaction.userEmail !== email && transaction.counterpartyEmail !== email) {
      return res.status(403).json({ error: 'You are not a party to this transaction' });
    }

    res.json({ transaction });
  } catch (err) {
    console.error('getTransactionDetails error:', err);
    res.status(500).json({ error: 'Failed to fetch transaction details' });
  }
};

// Toggle favourite status of a transaction
exports.toggleFavourite = async (req, res) => {
  try {
    const { transactionId } = req.params;
    const email = req.user.email; // always use authenticated identity

    if (!transactionId) {
      return res.status(400).json({ error: 'Transaction ID is required' });
    }

    const transaction = await Transaction.findOne({ transactionId });
    if (!transaction) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    // Check if the user is a party to this transaction
    if (transaction.userEmail !== email && transaction.counterpartyEmail !== email) {
      return res.status(403).json({ error: 'You are not a party to this transaction' });
    }

    const isFavourited = transaction.favourite.includes(email);

    if (isFavourited) {
      // Remove from favourites
      transaction.favourite = transaction.favourite.filter(favEmail => favEmail !== email);
    } else {
      // Add to favourites
      transaction.favourite.push(email);
    }

    await transaction.save();

    res.json({ 
      success: true, 
      message: `Transaction ${isFavourited ? 'removed from' : 'added to'} favourites`,
      favourite: transaction.favourite 
    });

  } catch (err) {
    res.status(500).json({ error: 'Failed to toggle favourite status' });
  }
};

