const mongoose = require('mongoose');

const walletTransactionSchema = new mongoose.Schema({
  user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  type: { type: String, enum: ['credit', 'debit', 'topup'], required: true },
  amount: { type: Number, required: true },
  fromEmail: { type: String, default: null },
  toEmail: { type: String, default: null },
  note: { type: String, default: '' },
  razorpayOrderId: { type: String },
  // No default — field must be absent (not null) on wallet-payment records so the
  // sparse unique index below ignores them. null != absent for sparse indexes.
  razorpayPaymentId: { type: String },
  createdAt: { type: Date, default: Date.now },
});

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
