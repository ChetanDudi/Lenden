const ContactConfig = require('../models/contactConfig');
const ContactMessage = require('../models/contactMessage');
const { CONTACT_CATEGORIES } = require('../models/contactMessage');
const Notification = require('../models/notification');
const User = require('../models/user');
const { sendContactReplyEmail } = require('../utils/email/contactReplyEmail');
const { sendToUser } = require('../services/notificationService');
const { handleRouteError } = require('../utils/apiError');

const ensureContactConfig = async () =>
  ContactConfig.findOneAndUpdate(
    { singletonKey: 'default' },
    { $setOnInsert: { singletonKey: 'default' } },
    { upsert: true, new: true, setDefaultsOnInsert: true }
  );

const normalizeText = (value, fallback = '') => {
  if (typeof value !== 'string') return fallback;
  return value.trim();
};

const normalizeChannel = (input = {}, fallback = {}) => ({
  label: normalizeText(input.label, fallback.label || ''),
  value: normalizeText(input.value, fallback.value || ''),
  url: normalizeText(input.url, fallback.url || ''),
  enabled: input.enabled !== false,
});

const ALL_CHANNELS = ['email', 'facebook', 'whatsapp', 'instagram', 'phone', 'twitter', 'linkedin', 'youtube'];

const serializeConfig = (config) => ({
  heroTitle: config.heroTitle || '',
  heroDescription: config.heroDescription || '',
  ...Object.fromEntries(
    ALL_CHANNELS.map((key) => [key, normalizeChannel(config[key], { label: key.charAt(0).toUpperCase() + key.slice(1) })])
  ),
});

exports.getPublicContactConfig = async (_req, res) => {
  try {
    const config = await ensureContactConfig();
    res.json(serializeConfig(config));
  } catch (err) {
    handleRouteError(res, err);
  }
};

exports.getAdminContactConfig = async (_req, res) => {
  try {
    const config = await ensureContactConfig();
    res.json(serializeConfig(config));
  } catch (err) {
    handleRouteError(res, err);
  }
};

exports.updateAdminContactConfig = async (req, res) => {
  try {
    const config = await ensureContactConfig();
    const payload = req.body || {};

    if (payload.heroTitle !== undefined) {
      const heroTitle = normalizeText(payload.heroTitle);
      if (!heroTitle) return res.status(400).json({ error: 'heroTitle is required.' });
      config.heroTitle = heroTitle;
    }

    if (payload.heroDescription !== undefined) {
      const heroDescription = normalizeText(payload.heroDescription);
      if (!heroDescription) return res.status(400).json({ error: 'heroDescription is required.' });
      config.heroDescription = heroDescription;
    }

    ALL_CHANNELS.forEach((key) => {
      if (payload[key] !== undefined) {
        config[key] = normalizeChannel(payload[key], config[key] || {});
      }
    });

    await config.save();

    res.json({
      success: true,
      message: 'Contact information updated.',
      ...serializeConfig(config),
    });
  } catch (err) {
    handleRouteError(res, err);
  }
};

exports.getContactCategories = (_req, res) => {
  res.json({ categories: CONTACT_CATEGORIES });
};

exports.submitContactMessage = async (req, res) => {
  try {
    const { name, email, subject, message, category } = req.body || {};

    if (!name || !name.trim()) return res.status(400).json({ error: 'Name is required.' });
    if (!email || !email.trim()) return res.status(400).json({ error: 'Email is required.' });
    if (!message || !message.trim()) return res.status(400).json({ error: 'Message is required.' });

    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email.trim())) return res.status(400).json({ error: 'Invalid email address.' });
    if (message.trim().length < 10) return res.status(400).json({ error: 'Message is too short.' });

    const validCategory = category && CONTACT_CATEGORIES.includes(category) ? category : 'General Inquiry';

    const doc = await ContactMessage.create({
      name: name.trim().slice(0, 100),
      email: email.trim().toLowerCase(),
      subject: subject ? subject.trim().slice(0, 200) : 'General Inquiry',
      message: message.trim().slice(0, 2000),
      category: validCategory,
      userId: req.user?._id || req.user?.userId || null,
      userEmail: req.user?.email || null,
      ipAddress: req.ip || req.headers['x-forwarded-for'] || null,
    });

    res.status(201).json({ success: true, message: 'Your message has been received. We will get back to you within 24 hours.', id: doc._id });
  } catch (err) {
    console.error('âŒ submitContactMessage error:', err);
    res.status(500).json({ error: 'Failed to submit message. Please try again.' });
  }
};

exports.getUserMessages = async (req, res) => {
  try {
    const userId = req.user?._id || req.user?.userId;
    const userEmail = req.user?.email;

    const orConditions = [];
    if (userId) orConditions.push({ userId: userId });
    if (userEmail) {
      orConditions.push({ userEmail: userEmail });
      orConditions.push({ email: userEmail });
    }

    if (orConditions.length === 0) return res.json({ messages: [] });

    const messages = await ContactMessage.find({ $or: orConditions })
      .sort({ createdAt: -1 })
      .limit(20)
      .lean();

    res.json({ messages });
  } catch (err) {
    handleRouteError(res, err);
  }
};

exports.getAdminMessages = async (req, res) => {
  try {
    const { status, category, page = 1, limit = 20 } = req.query;
    const filter = {};
    if (status) filter.status = status;
    if (category && CONTACT_CATEGORIES.includes(category)) filter.category = category;

    const skip = (Number(page) - 1) * Number(limit);
    const [messages, total] = await Promise.all([
      ContactMessage.find(filter).sort({ createdAt: -1 }).skip(skip).limit(Number(limit)).lean(),
      ContactMessage.countDocuments(filter),
    ]);

    res.json({ messages, total, page: Number(page), limit: Number(limit), pages: Math.ceil(total / Number(limit)) });
  } catch (err) {
    handleRouteError(res, err);
  }
};

exports.updateMessageStatus = async (req, res) => {
  try {
    const { id } = req.params;
    const { status, replyNote } = req.body || {};

    const validStatuses = ['new', 'read', 'replied', 'closed'];
    if (!validStatuses.includes(status)) return res.status(400).json({ error: 'Invalid status.' });

    const update = { status };
    if (replyNote !== undefined) update.replyNote = replyNote.toString().trim();
    if (status === 'replied') update.repliedAt = new Date();

    const doc = await ContactMessage.findByIdAndUpdate(id, update, { new: true });
    if (!doc) return res.status(404).json({ error: 'Message not found.' });

    res.json({ success: true, message: doc });
  } catch (err) {
    handleRouteError(res, err);
  }
};

exports.replyToMessage = async (req, res) => {
  try {
    const { id } = req.params;
    const { replyText } = req.body || {};

    if (!replyText || !replyText.trim()) {
      return res.status(400).json({ error: 'Reply text is required.' });
    }

    const doc = await ContactMessage.findById(id);
    if (!doc) return res.status(404).json({ error: 'Message not found.' });

    if (doc.status === 'replied' || doc.replyNote) {
      return res.status(409).json({ error: 'A reply has already been sent for this message.' });
    }

    await sendContactReplyEmail({
      name: doc.name,
      email: doc.email,
      subject: doc.subject,
      originalMessage: doc.message,
      replyText,
    });

    const updated = await ContactMessage.findByIdAndUpdate(
      id,
      { status: 'replied', replyNote: replyText.trim(), repliedAt: new Date() },
      { new: true }
    );

    // Send in-app notification if the message was from a logged-in user
    if (doc.userId) {
      await Notification.create({
        sender: req.user._id,
        senderModel: 'Admin',
        recipientType: 'specific-users',
        recipients: [doc.userId],
        recipientModel: 'User',
        title: 'Reply to your inquiry',
        message: `Your message "${doc.subject || 'General Inquiry'}" has been replied to. Open Contact Us to read the response.`,
        category: 'system',
        deliveryStatus: 'sent',
        sentAt: new Date(),
      });
      sendToUser(User, doc.userId, { title: 'Support Reply 📩', body: 'Your message has been replied to.', data: { type: 'support_reply' } });
    }

    res.json({ success: true, message: updated });
  } catch (err) {
    console.error('âŒ replyToMessage error:', err);
    if (err.message && err.message.includes('SendGrid')) {
      return res.status(502).json({ error: `Email delivery failed: ${err.message}` });
    }
    res.status(500).json({ error: 'Failed to send reply.' });
  }
};

