const mongoose = require('mongoose');

const groupChatSchema = new mongoose.Schema({
    groupTransactionId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'GroupTransaction',
        required: true,
    },
    senderId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
    },
    message: {
        type: String,
        default: null,
    },
    senderPublicKey: {
        type: String,
        default: null,
    },
    encryptionVersion: {
        type: Number,
        default: 1,
    },
    encryptedPayloads: [{
        recipientUserId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User',
            required: true,
        },
        nonce: {
            type: String,
            required: true,
        },
        cipherText: {
            type: String,
            required: true,
        },
        mac: {
            type: String,
            required: true,
        }
    }],
    parentMessageId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'GroupChat',
        default: null,
    },
    mentions: [{
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
    }],
    mentionsAll: {
        type: Boolean,
        default: false,
    },
    reactions: [{
        emoji: String,
        userId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        }
    }],
    isEdited: {
        type: Boolean,
        default: false,
    },
    deletedFor: [{
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    }]
}, { timestamps: true });

groupChatSchema.index({ groupTransactionId: 1, createdAt: -1 });
groupChatSchema.index({ groupTransactionId: 1, senderId: 1, createdAt: 1 });

const GroupChat = mongoose.model('GroupChat', groupChatSchema);

module.exports = GroupChat;
