const AppRating = require('../models/Apprating');

// POST /api/rating - Submit app rating (one per user)
exports.submitRating = async (req, res) => {
  try {
    const { rating } = req.body;
    const userId = req.user._id;
    // Only allow one rating per user
    const existing = await AppRating.findOne({ user: userId });
    if (existing) {
      return res.status(400).json({ message: 'You have already rated the app.' });
    }
    const newRating = new AppRating({ user: userId, rating });
    await newRating.save();
    // Log activity for app rating
    try {
      const { createActivityLog } = require('./activityController');
      await createActivityLog(userId, 'app_rated', 'App Rated', `User rated the app with ${rating} stars.`, { rating });
    } catch (err) {
      // Ignore activity log errors
    }
    res.json({ message: 'Rating submitted successfully.' });
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
};

// GET /api/rating/my - Get my app rating
exports.getMyRating = async (req, res) => {
  try {
    const userId = req.user._id;
    const ratingObj = await AppRating.findOne({ user: userId });
    res.json({ rating: ratingObj ? ratingObj.rating : null });
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
};

// GET /api/rating/app-ratings - Return average app rating and total ratings count
exports.getAppRatings = async (req, res) => {
  try {
    const ratings = await AppRating.find();
    if (!ratings.length) {
      return res.json({ average: 0, count: 0 });
    }
    const total = ratings.reduce((sum, r) => sum + (r.rating || 0), 0);
    const avg = total / ratings.length;
    res.json({ average: Number(avg.toFixed(2)), count: ratings.length });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// GET /api/rating/all - Get all ratings (admin)
exports.getAllRatings = async (req, res) => {
  try {
    // Populate all user info except password for admin UI
    const ratings = await AppRating.find().sort({ createdAt: -1 }).populate('user', '-password');
    const ratingsWithUser = ratings.map(r => {
      const u = r.user || {};
      return {
        _id: r._id,
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
        rating: r.rating,
        createdAt: r.createdAt,
      };
    });
    res.json({ ratings: ratingsWithUser });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};
