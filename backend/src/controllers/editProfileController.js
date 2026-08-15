const User = require('../models/user');
const Admin = require('../models/admin');
const bcrypt = require('bcrypt');
const { logProfileActivity } = require('./activityController');

// Update user profile
exports.updateUserProfile = async (req, res) => {
  try {
    const userId = req.user._id;
    const update = {};
    const allowedFields = ['name', 'birthday', 'address', 'phone', 'phoneCountryCode', 'gender', 'email'];
    allowedFields.forEach(field => {
      if (req.body[field] !== undefined) update[field] = req.body[field];
    });

    if (update.phone !== undefined && update.phone !== '') {
      if (!/^\d{7,15}$/.test(update.phone)) {
        return res.status(400).json({ error: 'Phone number must be 7–15 digits' });
      }
    }

    if (req.body.password) {
      update.password = await bcrypt.hash(req.body.password, 10);
    }
    if (req.body.removeImage) {
      update.$unset = { profileImage: 1 };
    } else if (req.file) {
      const mt = req.file.mimetype || '';
      if (mt && mt !== 'application/octet-stream' && !mt.startsWith('image/')) {
        return res.status(400).json({ error: 'Profile image must be an image file.' });
      }
      update.profileImage = req.file.buffer;
    }

    const user = await User.findByIdAndUpdate(userId, update, { new: true, runValidators: true }).select('-password');
    // Return user object with profileImage as URL if exists
    const userObj = user.toObject();
    if (userObj.profileImage) {
      userObj.profileImage = `${req.protocol}://${req.get('host')}/api/users/${userObj._id}/profile-image`;
    }
    res.json(userObj);
    logProfileActivity(userId, 'profile_updated').catch(() => {});
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
};

// Update admin profile
exports.updateAdminProfile = async (req, res) => {
  try {
    const adminId = req.user._id;
    const update = {};
    const allowedFields = ['name', 'birthday', 'address', 'phone', 'gender', 'email'];
    allowedFields.forEach(field => {
      if (req.body[field] !== undefined) update[field] = req.body[field];
    });
    if (req.body.password) {
      update.password = await bcrypt.hash(req.body.password, 10);
    }
    if (req.body.removeImage) {
      update.$unset = { profileImage: 1 };
    } else if (req.file) {
      const mt = req.file.mimetype || '';
      if (mt && mt !== 'application/octet-stream' && !mt.startsWith('image/')) {
        return res.status(400).json({ error: 'Profile image must be an image file.' });
      }
      update.profileImage = req.file.buffer;
    }

    const admin = await Admin.findByIdAndUpdate(adminId, update, { new: true, runValidators: true }).select('-password');
    // Return admin object with profileImage as URL if exists
    const adminObj = admin.toObject();
    if (adminObj.profileImage) {
      adminObj.profileImage = `${req.protocol}://${req.get('host')}/api/admins/${adminObj._id}/profile-image`;
    }
    res.json(adminObj);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
}; 