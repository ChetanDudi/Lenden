const Dispute = require('../models/dispute');
const User = require('../models/user');
const Admin = require('../models/admin');
const Notification = require('../models/notification');
const Transaction = require('../models/transaction');
const QuickTransaction = require('../models/quickTransaction');
const GroupTransaction = require('../models/groupTransaction');
const { logAdminAudit } = require('../utils/adminAuditLogger');

const MODEL_BY_TYPE = {
  secure: Transaction,
  quick: QuickTransaction,
  group: GroupTransaction,
};

async function resolveRespondentEmail(transactionType, transactionId, raisedByEmail) {
  const Model = MODEL_BY_TYPE[transactionType];
  if (!Model) return null;

  if (transactionType === 'secure') {
    const t = await Model.findById(transactionId).select('userEmail counterpartyEmail');
    if (!t) return null;
    return t.userEmail?.toLowerCase() === raisedByEmail.toLowerCase()
      ? t.counterpartyEmail
      : t.userEmail;
  }
  if (transactionType === 'quick') {
    const t = await Model.findById(transactionId).select('users creatorEmail');
    if (!t) return null;
    return (t.users || []).find(
      (email) => email.toLowerCase() !== raisedByEmail.toLowerCase()
    ) || null;
  }
  // group: respondent is the group itself, not a single person — leave null,
  // the dispute is visible to admins via the group's transactionId.
  return null;
}

exports.createDispute = async (req, res) => {
  try {
    const { transactionType, transactionId, reason, description, evidence } = req.body;
    if (!transactionType || !transactionId || !reason || !description) {
      return res.status(400).json({ error: 'transactionType, transactionId, reason, and description are required.' });
    }
    if (!MODEL_BY_TYPE[transactionType]) {
      return res.status(400).json({ error: 'Invalid transactionType.' });
    }

    const raisedByEmail = req.user.email;
    const respondentEmail = await resolveRespondentEmail(transactionType, transactionId, raisedByEmail);

    const dispute = await Dispute.create({
      transactionType,
      transactionId,
      raisedBy: req.user._id,
      raisedByEmail,
      respondentEmail: respondentEmail || '',
      reason,
      description,
      evidence: Array.isArray(evidence) ? evidence.slice(0, 5) : [],
    });

    res.status(201).json({ message: 'Dispute submitted for review.', dispute });
  } catch (err) {
    console.error('Error creating dispute:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getMyDisputes = async (req, res) => {
  try {
    const email = req.user.email;
    const disputes = await Dispute.find({
      $or: [{ raisedByEmail: email }, { respondentEmail: email }],
    }).sort({ createdAt: -1 });
    res.json({ disputes });
  } catch (err) {
    console.error('Error fetching disputes:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getDisputeById = async (req, res) => {
  try {
    const dispute = await Dispute.findById(req.params.id);
    if (!dispute) return res.status(404).json({ error: 'Dispute not found' });
    const email = req.user.email;
    if (dispute.raisedByEmail !== email && dispute.respondentEmail !== email) {
      return res.status(403).json({ error: 'Not authorized to view this dispute.' });
    }
    res.json({ dispute });
  } catch (err) {
    console.error('Error fetching dispute:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

exports.adminListDisputes = async (req, res) => {
  try {
    const { status } = req.query;
    const filter = {};
    if (status && status !== 'all') filter.status = status;
    const disputes = await Dispute.find(filter).sort({ createdAt: -1 });
    res.json({ disputes });
  } catch (err) {
    console.error('Error listing disputes:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

exports.adminResolveDispute = async (req, res) => {
  try {
    const { status, resolution } = req.body;
    if (!['under_review', 'resolved', 'rejected'].includes(status)) {
      return res.status(400).json({ error: 'Invalid status.' });
    }

    const dispute = await Dispute.findById(req.params.id);
    if (!dispute) return res.status(404).json({ error: 'Dispute not found' });

    dispute.status = status;
    if (resolution) dispute.resolution = resolution;
    if (status === 'resolved' || status === 'rejected') {
      dispute.resolvedBy = req.user._id;
      dispute.resolvedAt = new Date();
    }
    await dispute.save();

    // Notify both parties.
    const recipients = await User.find({
      email: { $in: [dispute.raisedByEmail, dispute.respondentEmail].filter(Boolean) },
    }).select('_id');

    if (recipients.length) {
      const admin = await Admin.findById(req.user._id).select('_id');
      await Notification.create({
        sender: admin?._id || req.user._id,
        senderModel: 'Admin',
        recipientType: 'specific-users',
        recipients: recipients.map((r) => r._id),
        recipientModel: 'User',
        category: 'transaction',
        message: `Your dispute (${dispute.reason}) has been marked as ${status.replace('_', ' ')}.${resolution ? ` Resolution: ${resolution}` : ''}`,
      });
    }

    await logAdminAudit({
      req,
      admin: req.user,
      action: 'dispute_resolved',
      targetType: 'dispute',
      targetId: dispute._id,
      summary: `Dispute ${dispute._id} marked as ${status}`,
      details: { resolution },
    });

    res.json({ message: 'Dispute updated.', dispute });
  } catch (err) {
    console.error('Error resolving dispute:', err);
    res.status(500).json({ error: 'Server error' });
  }
};
