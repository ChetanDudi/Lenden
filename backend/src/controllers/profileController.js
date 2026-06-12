const User = require('../models/user');
const Admin = require('../models/admin');

exports.getUserProfile = async (req, res) => {
  try {
    const user = await User.findById(req.user._id).select('-password');
    const userObj = user.toObject();
    userObj.deactivatedAccount = user.deactivatedAccount;
    if (userObj.profileImage) {
      userObj.profileImage = `${req.protocol}://${req.get('host')}/api/users/${userObj._id}/profile-image`;
    }
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

exports.getUserProfileImage = async (req, res) => {
  try {
    const user = await User.findById(req.params.id).select('profileImage');
    if (!user || !user.profileImage || user.profileImage.length === 0) return res.status(404).send('Not found');
    res.set('Content-Type', 'image/jpeg'); // You may want to store the type in DB for flexibility
    res.send(user.profileImage);
  } catch (err) {
    res.status(500).send('Error');
  }
};

exports.getAdminProfileImage = async (req, res) => {
  try {
    const admin = await Admin.findById(req.params.id).select('profileImage');
    if (!admin || !admin.profileImage) return res.status(404).send('Not found');
    res.set('Content-Type', 'image/jpeg');
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
    res.json(userObj);
  } catch (err) {
    console.error('Error in getUserProfileByEmail:', err);
    res.status(500).json({ error: 'Server error' });
  }
};
