const GiftCard = require('../models/giftCard');
const Admin = require('../models/admin');

const normalizePermissions = (permissions = {}) => ({
    canManageUsers: permissions.canManageUsers !== false,
    canManageTransactions: permissions.canManageTransactions !== false,
    canManageSupport: permissions.canManageSupport !== false,
    canManageContent: permissions.canManageContent !== false,
    canManageDigitise: permissions.canManageDigitise !== false,
    canManageSettings: permissions.canManageSettings !== false,
    canViewAuditLogs: permissions.canViewAuditLogs !== false,
});

const getCurrentAdmin = async (req) => {
    const adminId = req.user?._id || req.user?.userId || req.user?.id;
    let admin = null;

    if (adminId) {
        admin = await Admin.findById(adminId).select('_id email isSuperAdmin permissions').lean();
    }
    if (!admin && req.user?.email) {
        admin = await Admin.findOne({ email: req.user.email })
            .select('_id email isSuperAdmin permissions')
            .lean();
    }

    return admin;
};

const canManageGiftCard = (admin, giftCard) => {
    if (!admin || !giftCard) return false;
    if (admin.isSuperAdmin === true) return true;
    return giftCard.createdBy?.toString() === admin._id?.toString();
};

const ensureDigitisePermission = async (req, res) => {
    const currentAdmin = await getCurrentAdmin(req);
    if (
        !currentAdmin ||
        !(currentAdmin.isSuperAdmin === true ||
            normalizePermissions(currentAdmin.permissions || {}).canManageDigitise === true)
    ) {
        res.status(403).json({ message: 'You do not have permission to manage gift cards.' });
        return null;
    }
    return currentAdmin;
};

// Create a new gift card
exports.createGiftCard = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const { name, value } = req.body;
        const createdBy = req.user._id; // Admin ID from auth middleware

        if (!name || !value) {
            return res.status(400).json({ message: 'Name and value are required.' });
        }

        const newGiftCard = new GiftCard({
            name,
            value,
            createdBy,
        });

        await newGiftCard.save();

        res.status(201).json({ message: 'Gift card created successfully', giftCard: newGiftCard });
    } catch (error) {
        res.status(500).json({ message: 'Error creating gift card' });
    }
};

// Get all gift cards
exports.getGiftCards = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const giftCards = await GiftCard.find().populate('createdBy', 'name');
        res.status(200).json(giftCards);
    } catch (error) {
        res.status(500).json({ message: 'Error fetching gift cards' });
    }
};

// Update a gift card
exports.updateGiftCard = async (req, res) => {
    try {
        const { id } = req.params;
        const { name, value } = req.body;
        const currentAdmin = await ensureDigitisePermission(req, res);
        if (!currentAdmin) return;

        const giftCard = await GiftCard.findById(id);

        if (!giftCard) {
            return res.status(404).json({ message: 'Gift card not found' });
        }

        if (!canManageGiftCard(currentAdmin, giftCard)) {
            return res.status(403).json({ message: 'You are not authorized to edit this gift card.' });
        }

        giftCard.name = name || giftCard.name;
        giftCard.value = value || giftCard.value;

        const updatedGiftCard = await giftCard.save();

        res.status(200).json({ message: 'Gift card updated successfully', giftCard: updatedGiftCard });
    } catch (error) {
        res.status(500).json({ message: 'Error updating gift card' });
    }
};

// Delete a gift card
exports.deleteGiftCard = async (req, res) => {
    try {
        const { id } = req.params;
        const currentAdmin = await ensureDigitisePermission(req, res);
        if (!currentAdmin) return;

        const giftCard = await GiftCard.findById(id);

        if (!giftCard) {
            return res.status(404).json({ message: 'Gift card not found' });
        }

        if (!canManageGiftCard(currentAdmin, giftCard)) {
            return res.status(403).json({ message: 'You are not authorized to delete this gift card.' });
        }

        await giftCard.deleteOne();

        res.status(200).json({ message: 'Gift card deleted successfully' });
    } catch (error) {
        res.status(500).json({ message: 'Error deleting gift card' });
    }
};
