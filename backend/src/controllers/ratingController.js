const Rating = require('../models/rating');
const User = require('../models/user');

// GET /api/ratings/user-avg?usernameOrEmail=... - Get avg rating for any user by username or email
exports.getUserAvgRating = async (req, res) => {
  try {
    const { usernameOrEmail } = req.query;
    if (!usernameOrEmail) {
      return res.status(400).json({ error: 'Username or email is required.' });
    }
    const user = await User.findOne({
      $or: [
        { username: usernameOrEmail },
        { email: usernameOrEmail }
      ]
    });
    if (!user) {
      return res.status(404).json({ error: 'User not found.' });
    }
    const ratings = await Rating.find({ ratee: user._id });
    const totalRatings = ratings.length;
    let avg = 0;
    const distribution = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
    if (totalRatings > 0) {
      avg = ratings.reduce((sum, r) => { distribution[r.rating] = (distribution[r.rating] || 0) + 1; return sum + r.rating; }, 0) / totalRatings;
    }
    user.avgRating = avg;
    await user.save();
    return res.json({
      username: user.username,
      name: user.name,
      email: user.email,
      avgRating: user.avgRating || 0,
      totalRatings,
      distribution,
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// POST /api/ratings - Rate a user
exports.rateUser = async (req, res) => {
  try {
    const raterId = req.user._id;
    const { usernameOrEmail, rating, comment } = req.body;
    if (!usernameOrEmail || !rating) {
      return res.status(400).json({ error: 'Username/email and rating are required.' });
    }
    // Find user by username or email
    const ratee = await User.findOne({
      $or: [
        { username: usernameOrEmail },
        { email: usernameOrEmail }
      ]
    });
    if (!ratee) {
      return res.status(404).json({ error: 'User not found.' });
    }
    if (ratee._id.equals(raterId)) {
      return res.status(400).json({ error: 'You cannot rate yourself.' });
    }
    // Only allow one rating per rater-ratee
    let ratingDoc = await Rating.findOne({ rater: raterId, ratee: ratee._id });
    if (ratingDoc) {
      return res.status(400).json({ error: 'You have already rated this user.' });
    }
    ratingDoc = new Rating({ rater: raterId, ratee: ratee._id, rating, comment: comment?.toString().trim() || undefined });
    await ratingDoc.save();
    // Update avgRating for the ratee
    const ratings = await Rating.find({ ratee: ratee._id });
    const avg = ratings.reduce((sum, r) => sum + r.rating, 0) / ratings.length;
    ratee.avgRating = avg;
    await ratee.save();

    // Log activity for rater and ratee
    const ActivityController = require('./activityController');
    // For rater: user_rated
    await ActivityController.createActivityLog(
      raterId,
      'user_rated',
      `Rated user ${ratee.name || ratee.username}`,
      `You rated ${ratee.name || ratee.username} with ${rating} stars`,
      { rating, ratee: ratee._id }
    );
    // For ratee: user_rating_received
    await ActivityController.createActivityLog(
      ratee._id,
      'user_rating_received',
      `Received rating from ${req.user.name || req.user.username}`,
      `You received a rating of ${rating} stars from ${req.user.name || req.user.username}`,
      { rating, rater: raterId }
    );

    res.status(201).json({ message: 'Rating submitted.' });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// GET /api/ratings/me - Get my ratings and avg
exports.getMyRatings = async (req, res) => {
  try {
    const userId = req.user._id;
    const user = await User.findById(userId);
    // Recalculate avgRating from ratings collection
    const ratingsReceived = await Rating.find({ ratee: userId });
    let avg = 0;
    if (ratingsReceived.length > 0) {
      avg = ratingsReceived.reduce((sum, r) => sum + r.rating, 0) / ratingsReceived.length;
    }
    user.avgRating = avg;
    await user.save();
    // Ratings received
    const received = await Rating.find({ ratee: userId }).populate('rater', 'username name');
    // Ratings given
    const given = await Rating.find({ rater: userId }).populate('ratee', 'username name');
    res.json({
      avgRating: user.avgRating || 0,
      ratingsReceived: received.map(r => ({
        rater: r.rater._id,
        raterName: r.rater.name || r.rater.username,
        rating: r.rating,
        comment: r.comment,
        createdAt: r.createdAt
      })),
      ratingsGiven: given.map(r => ({
        _id: r._id,
        ratee: r.ratee._id,
        rateeName: r.ratee.name || r.ratee.username,
        rating: r.rating,
        comment: r.comment,
        createdAt: r.createdAt
      }))
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// PATCH /api/ratings/:ratingId - Edit your own given rating
exports.updateRating = async (req, res) => {
  try {
    const { ratingId } = req.params;
    const { rating, comment } = req.body;
    if (!rating || rating < 1 || rating > 5) {
      return res.status(400).json({ error: 'Rating must be between 1 and 5.' });
    }
    const ratingDoc = await Rating.findOne({ _id: ratingId, rater: req.user._id });
    if (!ratingDoc) {
      return res.status(404).json({ error: 'Rating not found or not yours.' });
    }
    ratingDoc.rating = rating;
    ratingDoc.comment = comment?.toString().trim() || undefined;
    await ratingDoc.save();

    // Recalculate ratee's average
    const ratee = await User.findById(ratingDoc.ratee);
    if (ratee) {
      const all = await Rating.find({ ratee: ratee._id });
      ratee.avgRating = all.reduce((s, r) => s + r.rating, 0) / all.length;
      await ratee.save();
    }
    res.json({ message: 'Rating updated.' });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};
