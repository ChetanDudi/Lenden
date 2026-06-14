const ContactConfig = require('../models/contactConfig');
const ContactMessage = require('../models/contactMessage');
const { CONTACT_CATEGORIES } = require('../models/contactMessage');
const Notification = require('../models/notification');
const { sendEmail } = require('../utils/sendEmailApi');

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
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getAdminContactConfig = async (_req, res) => {
  try {
    const config = await ensureContactConfig();
    res.json(serializeConfig(config));
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
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
    res.status(500).json({ error: 'Server error' });
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
    console.error('❌ submitContactMessage error:', err);
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
    res.status(500).json({ error: 'Server error' });
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
    res.status(500).json({ error: 'Server error' });
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
    res.status(500).json({ error: 'Server error' });
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

    await sendEmail({
      to: doc.email,
      subject: `Re: ${doc.subject || 'Your Inquiry'} - Lenden Support`,
      html: `
        <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;">
          <div style="background:linear-gradient(135deg,#00B4D8,#48CAE4);padding:24px;border-radius:12px 12px 0 0;">
            <h2 style="color:white;margin:0;">Lenden Support</h2>
          </div>
          <div style="padding:24px;background:#fff;border-radius:0 0 12px 12px;border:1px solid #e0e0e0;">
            <p style="color:#555;margin:0 0 16px;">Hi ${doc.name},</p>
            <p style="color:#333;margin:0 0 20px;">Thank you for reaching out. Here is our response:</p>
            <div style="background:#f0f9fc;border-left:4px solid #00B4D8;padding:16px;border-radius:4px;margin:0 0 24px;">
              <p style="color:#333;margin:0;line-height:1.6;">${replyText.trim().replace(/\n/g, '<br>')}</p>
            </div>
            <p style="color:#999;font-size:12px;margin:0 0 4px;"><strong>Your original message:</strong></p>
            <p style="color:#aaa;font-size:12px;font-style:italic;margin:0 0 24px;">"${doc.message}"</p>
            <p style="color:#555;margin:0;">Best regards,<br><strong>Lenden Support Team</strong></p>
          </div>
        </div>
      `,
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
    }

    res.json({ success: true, message: updated });
  } catch (err) {
    console.error('❌ replyToMessage error:', err);
    if (err.message && err.message.includes('SendGrid')) {
      return res.status(502).json({ error: `Email delivery failed: ${err.message}` });
    }
    res.status(500).json({ error: 'Failed to send reply.' });
  }
};
