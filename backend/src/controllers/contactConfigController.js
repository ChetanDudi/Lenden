const ContactConfig = require('../models/contactConfig');
const ContactMessage = require('../models/contactMessage');

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

exports.submitContactMessage = async (req, res) => {
  try {
    const { name, email, subject, message } = req.body || {};

    if (!name || !name.trim()) return res.status(400).json({ error: 'Name is required.' });
    if (!email || !email.trim()) return res.status(400).json({ error: 'Email is required.' });
    if (!message || !message.trim()) return res.status(400).json({ error: 'Message is required.' });

    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email.trim())) return res.status(400).json({ error: 'Invalid email address.' });
    if (message.trim().length < 10) return res.status(400).json({ error: 'Message is too short.' });

    const doc = await ContactMessage.create({
      name: name.trim().slice(0, 100),
      email: email.trim().toLowerCase(),
      subject: subject ? subject.trim().slice(0, 200) : 'General Inquiry',
      message: message.trim().slice(0, 2000),
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

exports.getAdminMessages = async (req, res) => {
  try {
    const { status, page = 1, limit = 20 } = req.query;
    const filter = {};
    if (status) filter.status = status;

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
