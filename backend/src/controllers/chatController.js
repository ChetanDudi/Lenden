const Transaction = require('../models/transaction');
const User = require('../models/user');
const Notification = require('../models/notification');
const { FEATURES, hasFeature } = require('../utils/subscriptionFeatures');
const Chat = require('../models/chat');
const {
    decodeChatMessage,
    normalizeStoredChatMessage,
    toChatResponse
} = require('../utils/chatCodec');
const { recordCoinLedgerEntry } = require('../utils/coinLedgerService');
const { getCoinPricing } = require('../utils/coinPricing');
const { sendToUser } = require('../services/notificationService');

function hasEncryptedPayloads(encryptedPayloads) {
    return Array.isArray(encryptedPayloads) && encryptedPayloads.length > 0;
}

module.exports = (io) => {
    let users = {};

    io.on('connection', (socket) => {
        socket.on('join', (userId) => {
            if (userId) {
                users[userId] = socket.id;
                socket.join(userId);
            }
        });

        socket.on('disconnect', () => {
            for (let userId in users) {
                if (users[userId] === socket.id) {
                    delete users[userId];
                    break;
                }
            }
        });

        socket.on('createMessage', async (data) => {
            try {
                const {
                    transactionId,
                    senderId,
                    receiverId,
                    message,
                    parentMessageId,
                    encryptedPayloads,
                    senderPublicKey,
                    encryptionVersion,
                } = data;
                const decodedMessage = typeof message === 'string'
                    ? decodeChatMessage(message)
                    : '';
                const usingEncryptedPayloads = hasEncryptedPayloads(encryptedPayloads);

                if (!usingEncryptedPayloads && (!decodedMessage || !decodedMessage.trim())) {
                    socket.emit('createMessageError', { ...data, error: 'Message cannot be empty.' });
                    return;
                }

                const transaction = await Transaction.findById(transactionId);
                if (!transaction) {
                    socket.emit('createMessageError', { ...data, error: 'Transaction not found' });
                    return;
                }

                const sender = await User.findById(senderId);
                const receiver = await User.findById(receiverId);
                if (!sender || !receiver) {
                    socket.emit('createMessageError', { ...data, error: 'User not found' });
                    return;
                }

                if (usingEncryptedPayloads) {
                    const isRegisteredDeviceKey = (sender.chatEncryptionDevices || [])
                        .some(d => d.publicKey === senderPublicKey);
                    if (!senderPublicKey || !isRegisteredDeviceKey) {
                        socket.emit('createMessageError', { ...data, error: 'Encrypted chat key mismatch. Please refresh and try again.' });
                        return;
                    }
                }

                const isSubscribed = await hasFeature(senderId, FEATURES.PRIVATE_CHAT);

                let start;
                let end;
                let todayCount = 0;
                if (!isSubscribed) {
                    start = new Date();
                    start.setHours(0, 0, 0, 0);
                    end = new Date();
                    end.setHours(23, 59, 59, 999);
                    todayCount = await Chat.countDocuments({
                        transactionId,
                        senderId,
                        createdAt: { $gte: start, $lte: end },
                    });
                }

                const userMessageCount = transaction.messageCounts.find(mc => mc.user.toString() === senderId);
                if (!isSubscribed) {
                    const pricing = await getCoinPricing();
                    const MESSAGE_COST = pricing.privateChatMessageCost;
                    const dailyLimitReached = todayCount >= 3;
                    const totalFreeUsed = userMessageCount && userMessageCount.count >= 5;
                    const needsCoins = dailyLimitReached || totalFreeUsed;

                    if (needsCoins) {
                        const updatedSender = await User.findOneAndUpdate(
                            { _id: sender._id, lenDenCoins: { $gte: MESSAGE_COST } },
                            { $inc: { lenDenCoins: -MESSAGE_COST } },
                            { new: true }
                        );
                        if (!updatedSender) {
                            socket.emit('createMessageError', { ...data, error: 'Insufficient LenDen coins to send a message. Please subscribe or earn more coins.' });
                            return;
                        }
                        sender.lenDenCoins = updatedSender.lenDenCoins;
                        await recordCoinLedgerEntry({
                            userId: sender._id,
                            direction: 'spent',
                            coins: MESSAGE_COST,
                            source: 'private_chat_with_coins',
                            title: 'Private Chat Message Sent With Coins',
                            description: `Spent ${MESSAGE_COST} LenDen coins to send a private chat message.`,
                            metadata: {
                                transactionId,
                                receiverId,
                            },
                        });
                    }
                }

                if (userMessageCount) {
                    await Transaction.updateOne(
                        { _id: transactionId, 'messageCounts.user': senderId },
                        { $inc: { 'messageCounts.$.count': 1 } }
                    );
                } else {
                    await Transaction.updateOne(
                        { _id: transactionId },
                        { $push: { messageCounts: { user: senderId, count: 1 } } }
                    );
                }

                let chat = new Chat({
                    transactionId,
                    senderId,
                    receiverId,
                    message: usingEncryptedPayloads
                        ? null
                        : normalizeStoredChatMessage(decodedMessage.trim()),
                    senderPublicKey: usingEncryptedPayloads ? senderPublicKey : null,
                    encryptionVersion: usingEncryptedPayloads ? (Number(encryptionVersion) || 1) : 0,
                    encryptedPayloads: usingEncryptedPayloads ? encryptedPayloads : [],
                    parentMessageId,
                });

                await chat.save();

                chat = await Chat.findById(chat._id)
                    .populate('senderId', 'name')
                    .populate('receiverId', 'name')
                    .populate({
                        path: 'parentMessageId',
                        populate: {
                            path: 'senderId',
                            select: 'name'
                        }
                    });
                
                const updatedTransaction = await Transaction.findById(transactionId).populate('messageCounts.user', 'name');

                io.to(senderId).to(receiverId).emit('newMessage', {
                    chat: toChatResponse(chat),
                    messageCounts: updatedTransaction.messageCounts,
                    lenDenCoins: sender.lenDenCoins
                });

                // Create in-app notification only when receiver is offline so they
                // see the missed message in their notification bell on next open.
                if (!users[receiverId.toString()] && receiver.notificationSettings?.chatNotifications !== false) {
                    Notification.create({
                        sender: sender._id,
                        senderModel: 'User',
                        recipientType: 'specific-users',
                        recipients: [receiver._id],
                        recipientModel: 'User',
                        category: 'general',
                        message: `New message from ${sender.name || sender.username || sender.email}`,
                    }).catch(() => {});
                    sendToUser(User, receiver._id, { title: 'New Message 💬', body: `${sender.name || sender.username || sender.email} sent you a message.`, data: { type: 'chat_message', transactionId: transactionId.toString() } });
                }
            } catch (error) {
                console.error('Error in createMessage socket handler:', error);
                socket.emit('createMessageError', { ...data, error: 'An error occurred while sending the message.' });
            }
        });

        socket.on('editMessage', async (data) => {
            try {
                const {
                    messageId,
                    userId,
                    message,
                    encryptedPayloads,
                    senderPublicKey,
                    encryptionVersion,
                } = data;
                const decodedMessage = typeof message === 'string'
                    ? decodeChatMessage(message)
                    : '';
                const usingEncryptedPayloads = hasEncryptedPayloads(encryptedPayloads);
                let chat = await Chat.findById(messageId);
                if (!chat || chat.senderId.toString() !== userId) return;

                if (!usingEncryptedPayloads && (!decodedMessage || !decodedMessage.trim())) {
                    socket.emit('editMessageError', { messageId, error: 'Message cannot be empty.' });
                    return;
                }

                const sender = await User.findById(userId).select('chatEncryptionDevices');
                const isRegisteredDeviceKey = (sender?.chatEncryptionDevices || [])
                    .some(d => d.publicKey === senderPublicKey);
                if (usingEncryptedPayloads && (!senderPublicKey || !isRegisteredDeviceKey)) {
                    socket.emit('editMessageError', { messageId, error: 'Encrypted chat key mismatch. Please refresh and try again.' });
                    return;
                }

                const senderIdStr = chat.senderId.toString();
                const receiverIdStr = chat.receiverId.toString();

                const now = new Date();
                const messageTime = new Date(chat.createdAt);
                const diffInMinutes = (now.getTime() - messageTime.getTime()) / 60000;

                if (diffInMinutes > 2) {
                    socket.emit('editMessageError', { messageId, error: 'You can no longer edit this message.' });
                    return;
                }

                chat.message = usingEncryptedPayloads
                    ? null
                    : normalizeStoredChatMessage(decodedMessage.trim());
                chat.senderPublicKey = usingEncryptedPayloads ? senderPublicKey : chat.senderPublicKey;
                chat.encryptionVersion = usingEncryptedPayloads ? (Number(encryptionVersion) || 1) : 0;
                chat.encryptedPayloads = usingEncryptedPayloads ? encryptedPayloads : [];
                chat.isEdited = true;
                await chat.save();
                let populatedChat = await Chat.findById(chat._id)
                    .populate('senderId', 'name')
                    .populate('receiverId', 'name')
                    .populate({
                        path: 'parentMessageId',
                        populate: {
                            path: 'senderId',
                            select: 'name'
                        }
                    });

                io.to(senderIdStr).to(receiverIdStr).emit('messageUpdated', toChatResponse(populatedChat));
            } catch (error) {
                console.error('Error in editMessage socket handler:', error);
            }
        });

        socket.on('deleteMessage', async (data) => {
            try {
                const { messageId, userId, forEveryone } = data;
                const chat = await Chat.findById(messageId);
                if (!chat) return;

                const senderId = chat.senderId.toString();
                const receiverId = chat.receiverId.toString();

                if (forEveryone && senderId === userId) {
                    await Chat.findByIdAndDelete(messageId);
                    io.to(senderId).to(receiverId).emit('messageDeleted', { messageId, forEveryone: true, transactionId: chat.transactionId });
                } else {
                    chat.deletedFor.push(userId);
                    await chat.save();
                    io.to(userId).emit('messageDeleted', { messageId, forEveryone: false, transactionId: chat.transactionId });
                }
            } catch (error) {
                console.error('Error in deleteMessage socket handler:', error);
            }
        });

        socket.on('addReaction', async (data) => {
            try {
                const { messageId, userId, emoji } = data;
                let chat = await Chat.findById(messageId);
                if (!chat) return;

                const senderIdStr = chat.senderId.toString();
                const receiverIdStr = chat.receiverId.toString();

                const existingReactionIndex = chat.reactions.findIndex(r => r.userId.toString() === userId);

                if (existingReactionIndex > -1) {
                    if (chat.reactions[existingReactionIndex].emoji === emoji) {
                        chat.reactions.splice(existingReactionIndex, 1);
                    } else {
                        chat.reactions[existingReactionIndex].emoji = emoji;
                    }
                } else {
                    chat.reactions.push({ userId, emoji });
                }

                await chat.save();
                let populatedChat = await Chat.findById(chat._id)
                    .populate('senderId', 'name')
                    .populate('receiverId', 'name')
                    .populate({
                        path: 'parentMessageId',
                        populate: {
                            path: 'senderId',
                            select: 'name'
                        }
                    });

                io.to(senderIdStr).to(receiverIdStr).emit('messageUpdated', populatedChat);
            } catch (error) {
                console.error('Error in addReaction socket handler:', error);
            }
        });
    });

    const exports = {};

    exports.getMessages = async (req, res) => {
        try {
            const { transactionId } = req.params;
            const { userId } = req.query;

            const transaction = await Transaction.findById(transactionId).populate('messageCounts.user', 'name');

            const messages = await Chat.find({
                transactionId,
                deletedFor: { $ne: userId }
            })
            .populate('senderId', 'name')
            .populate('receiverId', 'name')
            .populate({
                path: 'parentMessageId',
                populate: {
                    path: 'senderId',
                    select: 'name'
                }
            })
            .sort({ createdAt: 'asc' });

            res.status(200).json({
                messages: messages.map((message) => toChatResponse(message)),
                messageCounts: transaction.messageCounts
            });
        } catch (error) {
            res.status(500).json({ message: 'Error fetching messages', error });
        }
    };

    return exports;
};
