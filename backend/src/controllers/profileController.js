const User = require('../models/user');
const Admin = require('../models/admin');
const QuickTransaction = require('../models/quickTransaction');
const Transaction = require('../models/transaction');
const { computeTrustScore } = require('../utils/trustScore');
const { FEATURES, hasFeature } = require('../utils/subscriptionFeatures');

const SENSITIVE_USER_FIELDS = [
  'password', 'walletPin', 'walletPinAttempts', 'walletPinLockedUntil',
  'walletPayOTP', 'resetOTP', 'loginOTP', 'setPasswordOTP',
  'changePasswordOTP', 'altEmailOTP', 'fcmToken', 'adminNotes',
];

exports.getUserProfile = async (req, res) => {
  try {
    const user = await User.findById(req.user._id);
    if (!user) return res.status(404).json({ error: 'User not found' });
    const userObj = user.toObject();
    // Expose whether a password is set (needed for Google users who may set one later)
    // without sending the actual hash to the client.
    userObj.hasPassword = !!userObj.password;
    for (const field of SENSITIVE_USER_FIELDS) delete userObj[field];
    userObj.deactivatedAccount = user.deactivatedAccount;
    if (userObj.profileImage) {
      userObj.profileImage = `${req.protocol}://${req.get('host')}/api/users/${userObj._id}/profile-image`;
    }
    const [quickCount, secureCount, trustScore] = await Promise.all([
      QuickTransaction.countDocuments({ users: user.email }),
      Transaction.countDocuments({ userEmail: user.email }),
      computeTrustScore(user.email),
    ]);
    userObj.trustScore = trustScore;
    userObj.friendCount = user.friends?.length ?? 0;
    userObj.quickTransactionCount = quickCount;
    userObj.secureTransactionCount = secureCount;
    res.json(userObj);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getAdminProfile = async (req, res) => {
  try {
    const adminId = req.user?._id || req.user?.userId || req.user?.id;
    let admin = null;

    if (adminId) {
      admin = await Admin.findById(adminId).select('-password');
    }
    if (!admin && req.user?.email) {
      admin = await Admin.findOne({ email: req.user.email }).select('-password');
    }

    if (!admin) return res.status(404).json({ error: 'Admin not found' });
    const adminObj = admin.toObject();
    adminObj.role = 'admin';
    if (adminObj.profileImage) {
      adminObj.profileImage = `${req.protocol}://${req.get('host')}/api/admins/${adminObj._id}/profile-image`;
    }
    res.json(adminObj);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Server error' });
  }
};

function detectImageMime(buf) {
  if (!buf || buf.length < 4) return 'image/jpeg';
  if (buf[0] === 0x89 && buf[1] === 0x50) return 'image/png';
  if (buf[0] === 0x47 && buf[1] === 0x49) return 'image/gif';
  if (buf[0] === 0x52 && buf[1] === 0x49) return 'image/webp';
  return 'image/jpeg';
}

exports.getUserProfileImage = async (req, res) => {
  try {
    const user = await User.findById(req.params.id).select('profileImage');
    if (!user || !user.profileImage || user.profileImage.length === 0) return res.status(404).send('Not found');
    res.set('Content-Type', detectImageMime(user.profileImage));
    res.set('Cache-Control', 'public, max-age=86400');
    res.send(user.profileImage);
  } catch (err) {
    res.status(500).send('Error');
  }
};

exports.getAdminProfileImage = async (req, res) => {
  try {
    const admin = await Admin.findById(req.params.id).select('profileImage');
    if (!admin || !admin.profileImage) return res.status(404).send('Not found');
    res.set('Content-Type', detectImageMime(admin.profileImage));
    res.set('Cache-Control', 'public, max-age=86400');
    res.send(admin.profileImage);
  } catch (err) {
    res.status(500).send('Error');
  }
};

exports.getUserProfileByEmail = async (req, res) => {
  try {
    const { email } = req.query;
    const requesterEmail = req.user?.email;

    if (!email) {
      console.error('Email query param missing');
      return res.status(400).json({ error: 'Email is required' });
    }

    const safeEmail = email.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const user = await User.findOne({ email: { $regex: new RegExp('^' + safeEmail + '$', 'i') } }).select('-password');

    if (!user) {
      console.error(`User not found for email: ${email}`);
      return res.status(404).json({ error: 'User not found' });
    }


    const privacySettings = user.privacySettings || {};

    // If profile is private and requester is not the user, return only minimal info
    if (
      privacySettings.profileVisibility === false &&
      (!requesterEmail || email.toLowerCase() !== requesterEmail.toLowerCase())
    ) {
      return res.json({
        _id: user._id,
        name: user.name,
        profileIsPrivate: true
        // Do not include email, phone, gender, or profileImage
      });
    }

    // Prepare user object for response
    const userObj = user.toObject();
    userObj.deactivatedAccount = user.deactivatedAccount;

    // Hide phone if contactSharing is false and requester is not the user
    if (
      privacySettings.contactSharing === false &&
      (!requesterEmail || email.toLowerCase() !== requesterEmail.toLowerCase())
    ) {
      userObj.phone = undefined;
    }

    if (userObj.profileImage) {
      userObj.profileImage = `${req.protocol}://${req.get('host')}/api/users/${userObj._id}/profile-image`;
    }

    // Ratings and trust score are premium features: always visible on your
    // own profile or to admins, otherwise only if the requester's plan
    // includes view_rankings.
    const isOwnProfile = requesterEmail && email.toLowerCase() === requesterEmail.toLowerCase();
    const isAdminRequester = req.user?.role === 'admin';
    const canViewRankings = isOwnProfile || isAdminRequester ||
      (req.user?._id && (await hasFeature(req.user._id, FEATURES.VIEW_RANKINGS)));

    if (canViewRankings) {
      userObj.trustScore = await computeTrustScore(user.email);
    } else {
      userObj.avgRating = undefined;
    }
    res.json(userObj);
  } catch (err) {
    console.error('Error in getUserProfileByEmail:', err);
    res.status(500).json({ error: 'Server error' });
  }
};
