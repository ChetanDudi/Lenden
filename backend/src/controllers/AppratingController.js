const AppRating = require('../models/Apprating');
const User = require('../models/user');

// POST /api/rating - Submit app rating (one per user)
exports.submitRating = async (req, res) => {
  try {
    const { rating } = req.body;
    const userId = req.user._id;
    const existing = await AppRating.findOne({ user: userId });
    if (existing) {
      return res.status(400).json({ message: 'You have already rated the app.' });
    }

    // Snapshot user info so the rating survives account deletion
    const user = await User.findById(userId).select('name email username').lean();
    const newRating = new AppRating({
      user: userId,
      userName: user?.name || '',
      userEmail: user?.email || '',
      username: user?.username || '',
      rating,
    });
    await newRating.save();

    try {
      const { createActivityLog } = require('./activityController');
      await createActivityLog(userId, 'app_rated', 'App Rated', `User rated the app with ${rating} stars.`, { rating });
    } catch (_) {}

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

// GET /api/rating/app-ratings - Average + total count
exports.getAppRatings = async (req, res) => {
  try {
    const [result] = await AppRating.aggregate([
      { $group: { _id: null, average: { $avg: '$rating' }, count: { $sum: 1 } } },
    ]);
    if (!result) return res.json({ average: 0, count: 0 });
    res.json({ average: Number(result.average.toFixed(2)), count: result.count });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// GET /api/rating/all - All ratings (admin)
exports.getAllRatings = async (req, res) => {
  try {
    const ratings = await AppRating.find()
      .sort({ createdAt: -1 })
      .populate('user', '-password')
      .lean();

    const ratingsWithUser = ratings.map(r => {
      if (r.userDeleted || !r.user) {
        // User deleted — use denormalized snapshot
        return {
          _id: r._id,
          userName: r.userName || '[Deleted User]',
          userEmail: r.userEmail || '',
          username: r.username || '',
          userDeleted: true,
          rating: r.rating,
          createdAt: r.createdAt,
        };
      }
      const u = r.user;
      return {
        _id: r._id,
        userName: u.name || u.email || r.userName || 'User',
        userEmail: u.email || r.userEmail || '',
        username: u.username || r.username || '',
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
        userDeleted: false,
        rating: r.rating,
        createdAt: r.createdAt,
      };
    });

    res.json({ ratings: ratingsWithUser });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// Called by account-deletion flows to detach the user reference
// while preserving the rating and the denormalized snapshot.
exports.markRatingUserDeleted = async (userId) => {
  try {
    await AppRating.findOneAndUpdate(
      { user: userId },
      { $set: { userDeleted: true, user: null } }
    );
  } catch (_) {}
};
