const mongoose = require('mongoose');

const chatSchema = new mongoose.Schema({
    transactionId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Transaction',
        required: true,
    },
    senderId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
    },
    receiverId: {
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
        ref: 'Chat',
        default: null,
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

// Primary fetch pattern: all messages for a transaction, newest-first
chatSchema.index({ transactionId: 1, createdAt: -1 });
// Lookup messages not yet seen by a participant (deletedFor filter)
chatSchema.index({ transactionId: 1, deletedFor: 1 });
// Sender-based queries (edit/delete own messages)
chatSchema.index({ senderId: 1, createdAt: -1 });

const Chat = mongoose.model('Chat', chatSchema);

module.exports = Chat;
