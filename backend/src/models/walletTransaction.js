const mongoose = require('mongoose');

const walletTransactionSchema = new mongoose.Schema({
  user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  type: { type: String, enum: ['credit', 'debit', 'topup', 'withdrawal'], required: true },
  amount: { type: Number, required: true },
  fromEmail: { type: String, default: null },
  toEmail: { type: String, default: null },
  note: { type: String, default: '' },
  razorpayOrderId: { type: String },
  // No default — field must be absent (not null) on wallet-payment records so the
  // sparse unique index below ignores them. null != absent for sparse indexes.
  razorpayPaymentId: { type: String },
  // Only set on type:'withdrawal'/'debit' (QR scan payment) records — lets the
  // admin's process/reject actions update this same entry's status so the
  // user's transaction history reflects it, instead of only being visible via
  // a separate refund entry.
  withdrawalRequestId: { type: mongoose.Schema.Types.ObjectId, ref: 'WithdrawalRequest', default: null },
  scanPaymentRequestId: { type: mongoose.Schema.Types.ObjectId, ref: 'ScanPaymentRequest', default: null },
  // Stable category tag set at creation time so admin filters don't rely on
  // note text (which can be a user-supplied description like "Lunch").
  sourceType: {
    type: String,
    enum: ['p2p', 'qr_internal', 'qr_external', 'quick', 'secure', 'group', 'subscription', 'coins', 'withdrawal'],
    default: null,
  },
  adminFlagged: { type: Boolean, default: false },
  status: { type: String, enum: ['processing', 'processed', 'failed', 'reversed'] },
  failureReason: { type: String, default: null },
  createdAt: { type: Date, default: Date.now },
});

walletTransactionSchema.index({ user: 1, createdAt: -1 });

// Sparse unique index — only indexes documents that have razorpayPaymentId set
// (i.e. Razorpay payments). Wallet-to-wallet records omit the field entirely and
// are therefore excluded, preventing the duplicate-null error.
walletTransactionSchema.index({ razorpayPaymentId: 1 }, { unique: true, sparse: true });

// Drop any legacy non-sparse version of this index so Mongoose recreates it correctly.
walletTransactionSchema.post('init', function () {});
mongoose.connection.once('open', async () => {
  try {
    const col = mongoose.connection.collection('wallettransactions');
    const indexes = await col.indexes();
    const stale = indexes.find(
      idx => idx.name === 'razorpayPaymentId_1' && !idx.sparse
    );
    if (stale) {
      await col.dropIndex('razorpayPaymentId_1');
    }
  } catch (_) {}
});

module.exports = mongoose.model('WalletTransaction', walletTransactionSchema);
