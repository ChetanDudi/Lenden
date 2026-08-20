const Note = require('../models/note');
const User = require('../models/user');
const Admin = require('../models/admin');
const { logNoteActivity } = require('./activityController');

// ── Helpers ──────────────────────────────────────────────────────────────────

function _ctx(req) {
  const user = req.user;
  const role = user.role === 'admin' ? 'Admin' : 'User';
  const userId = user._id || user.id;
  return { user, role, userId };
}

async function _findRecipient(senderRole, targetEmail) {
  if (senderRole === 'Admin') {
    const admin = await Admin.findOne({ email: targetEmail }).select('_id name email');
    return admin ? { recipient: admin, targetRole: 'Admin' } : null;
  }
  const user = await User.findOne({ email: targetEmail }).select('_id name email');
  return user ? { recipient: user, targetRole: 'User' } : null;
}

// ── Own notes ─────────────────────────────────────────────────────────────────

exports.createNote = async (req, res) => {
  try {
    const { title, content } = req.body;
    if (!title || !content) return res.status(400).json({ error: 'Title and content are required' });
    const { user, role, userId } = _ctx(req);
    const note = await Note.create({ user: userId, role, title, content });
    try {
      await logNoteActivity(userId, 'note_created', note, {}, { creatorId: userId, creatorEmail: user.email });
    } catch (e) { console.error('Failed to log note activity:', e); }
    res.status(201).json({ note });
  } catch (err) {
    console.error('Failed to create note:', err.message);
    res.status(500).json({ error: 'Failed to create note' });
  }
};

exports.getNotes = async (req, res) => {
  try {
    const { role, userId } = _ctx(req);
    const notes = await Note.find({ user: userId, role, isShared: { $ne: true } }).sort({ updatedAt: -1 });
    res.json({ notes });
  } catch (err) {
    console.error('Failed to fetch notes:', err.message);
    res.status(500).json({ error: 'Failed to fetch notes' });
  }
};

exports.updateNote = async (req, res) => {
  try {
    const { id } = req.params;
    const { title, content } = req.body;
    if (!title && !content) return res.status(400).json({ error: 'Title or content required' });
    const { user, role, userId } = _ctx(req);
    const update = {};
    if (title) update.title = title;
    if (content) update.content = content;
    // Allow editing both own and shared notes
    const note = await Note.findOneAndUpdate({ _id: id, user: userId, role }, update, { new: true });
    if (!note) return res.status(404).json({ error: 'Note not found' });
    try {
      await logNoteActivity(userId, 'note_edited', note, {}, { creatorId: userId, creatorEmail: user.email });
    } catch (e) { console.error('Failed to log note activity:', e); }
    res.json({ note });
  } catch (err) {
    res.status(500).json({ error: 'Failed to update note' });
  }
};

exports.deleteNote = async (req, res) => {
  try {
    const { id } = req.params;
    const { user, role, userId } = _ctx(req);
    // Allow deleting both own and shared notes
    const note = await Note.findOneAndDelete({ _id: id, user: userId, role });
    if (!note) return res.status(404).json({ error: 'Note not found' });
    try {
      await logNoteActivity(userId, 'note_deleted', note, {}, { creatorId: userId, creatorEmail: user.email });
    } catch (e) { console.error('Failed to log note activity:', e); }
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: 'Failed to delete note' });
  }
};

// ── Shared notes ──────────────────────────────────────────────────────────────

exports.getSharedNotes = async (req, res) => {
  try {
    const { role, userId } = _ctx(req);
    const notes = await Note.find({ user: userId, role, isShared: true }).sort({ updatedAt: -1 });
    res.json({ notes });
  } catch (err) {
    console.error('Failed to fetch shared notes:', err.message);
    res.status(500).json({ error: 'Failed to fetch shared notes' });
  }
};

// Share an existing note with another user (creates a copy for the recipient)
exports.shareNote = async (req, res) => {
  try {
    const { id } = req.params;
    const { targetEmail } = req.body;
    const { user, role, userId } = _ctx(req);
    if (!targetEmail) return res.status(400).json({ error: 'Target email is required' });

    const note = await Note.findOne({ _id: id, user: userId, role });
    if (!note) return res.status(404).json({ error: 'Note not found' });

    const found = await _findRecipient(role, targetEmail);
    if (!found) return res.status(404).json({ error: 'Recipient not found on LenDen' });
    const { recipient, targetRole } = found;
    if (recipient._id.toString() === userId.toString()) {
      return res.status(400).json({ error: 'Cannot share a note with yourself' });
    }

    const sharedNote = await Note.create({
      user: recipient._id,
      role: targetRole,
      title: note.title,
      content: note.content,
      isShared: true,
      sharedFrom: {
        noteId:      note._id,
        senderEmail: user.email,
        senderName:  user.name || user.email,
        sharedAt:    new Date(),
      },
    });

    try {
      await logNoteActivity(userId, 'note_shared', note, { targetEmail }, { creatorId: userId, creatorEmail: user.email });
    } catch (e) { console.error('Failed to log note share activity:', e); }

    res.status(201).json({ note: sharedNote, message: 'Note shared successfully' });
  } catch (err) {
    console.error('Failed to share note:', err.message);
    res.status(500).json({ error: 'Failed to share note' });
  }
};

// Share arbitrary content as a note to another user
exports.shareContentAsNote = async (req, res) => {
  try {
    const { title, content, targetEmail } = req.body;
    const { user, role, userId } = _ctx(req);
    if (!title || !content) return res.status(400).json({ error: 'Title and content are required' });
    if (!targetEmail) return res.status(400).json({ error: 'Target email is required' });

    const found = await _findRecipient(role, targetEmail);
    if (!found) return res.status(404).json({ error: 'Recipient not found on LenDen' });
    const { recipient, targetRole } = found;
    if (recipient._id.toString() === userId.toString()) {
      return res.status(400).json({ error: 'Cannot share with yourself' });
    }

    const sharedNote = await Note.create({
      user: recipient._id,
      role: targetRole,
      title,
      content,
      isShared: true,
      sharedFrom: {
        noteId:      null,
        senderEmail: user.email,
        senderName:  user.name || user.email,
        sharedAt:    new Date(),
      },
    });

    try {
      await logNoteActivity(userId, 'note_shared', sharedNote, { targetEmail }, { creatorId: userId, creatorEmail: user.email });
    } catch (e) { console.error('Failed to log note share activity:', e); }

    res.status(201).json({ note: sharedNote, message: 'Content shared as note successfully' });
  } catch (err) {
    console.error('Failed to share content as note:', err.message);
    res.status(500).json({ error: 'Failed to share content as note' });
  }
};

// Search LenDen users/admins to share notes with
exports.searchNoteRecipients = async (req, res) => {
  try {
    const q = (req.query.q || '').toString().trim();
    const { role, userId } = _ctx(req);

    if (role === 'Admin') {
      const filter = { _id: { $ne: userId } };
      if (q) {
        const regex = new RegExp(q, 'i');
        filter.$or = [{ email: regex }, { name: regex }];
      }
      const admins = await Admin.find(filter).select('_id name email').limit(20);
      return res.json({ users: admins });
    }

    // User: return friends when no query, otherwise search all users
    if (!q) {
      const me = await User.findById(userId).populate('friends', 'name username email').select('friends');
      return res.json({ users: (me?.friends || []).map(({ _id, name, username, email }) => ({ _id, name, username, email })) });
    }

    if (q.length < 2) {
      return res.json({ users: [] });
    }
    const escaped = q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const regex = new RegExp(escaped, 'i');
    const users = await User.find({
      _id: { $ne: userId },
      $or: [{ email: regex }, { username: regex }, { name: regex }],
    }).select('_id name username email').limit(20);
    res.json({ users });
  } catch (err) {
    console.error('Failed to search note recipients:', err.message);
    res.status(500).json({ error: 'Failed to search recipients' });
  }
};
