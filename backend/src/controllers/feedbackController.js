const Feedback = require('../models/feedback');

exports.submitFeedback = async (req, res) => {
  try {
    const { feedback } = req.body;
    if (!feedback) {
      return res.status(400).json({ error: 'Feedback is required.' });
    }
    const newFeedback = new Feedback({
      user: req.user._id,
      feedback,
    });
    await newFeedback.save();
    // Log activity for feedback submission
    try {
      const { createActivityLog } = require('./activityController');
      await createActivityLog(req.user._id, 'feedback_submitted', 'Feedback Submitted', 'User submitted feedback.', { feedback });
    } catch (err) {
      // Ignore activity log errors
    }
    res.json({ success: true, message: 'Feedback submitted successfully.' });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getUserFeedbacks = async (req, res) => {
  try {
    const feedbacks = await Feedback.find({ user: req.user._id }).sort({ createdAt: -1 });
    res.json({ feedbacks });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getAllFeedbacks = async (req, res) => {
  try {
    // Populate all user info except password for admin UI
    const feedbacks = await Feedback.find().sort({ createdAt: -1 }).populate('user', '-password');
    const feedbacksWithUser = feedbacks.map(fb => {
      const u = fb.user || {};
      return {
        _id: fb._id,
        userName: u.name || u.email || 'User',
        userEmail: u.email || '',
        userProfileImage: u.profileImage || '',
        username: u.username,
        gender: u.gender,
        birthday: u.birthday,
        address: u.address,
        phone: u.phone,
        altEmail: u.altEmail,
        memberSince: u.memberSince,
        avgRating: u.avgRating,
        role: u.role,
        isActive: u.isActive,
        isVerified: u.isVerified,
        // notificationSettings: u.notificationSettings, // omit
        // privacySettings: u.privacySettings, // omit
        feedback: fb.feedback,
        createdAt: fb.createdAt,
      };
    });
    res.json({ feedbacks: feedbacksWithUser });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};


