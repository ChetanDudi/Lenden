const mongoose = require('mongoose');

const activitySchema = new mongoose.Schema({
  user: { 
    type: mongoose.Schema.Types.ObjectId, 
    ref: 'User', 
    required: true 
  },
  type: {
    type: String,
    enum: [
      // Transaction activities
      'transaction_created',
      'transaction_cleared',
      'partial_payment_made',
      'partial_payment_received',
      'transaction_created_with_coins',
      
      // Group activities
      'group_created',
      'group_created_with_coins',
      'group_joined',
      'group_left',
      'member_added',
      'member_removed',
      'expense_added',
      'expense_edited',
      'expense_deleted',
      'expense_settled',
      
      // Note activities
      'note_created',
      'note_edited',
      'note_deleted',
      
      // Profile activities
      'profile_updated',
      'password_changed',
      
      // Other activities
      'login',
      'logout',
      'support_query_created',
      'support_query_updated',
      'support_query_deleted',
      'support_query_replied'
    ,
    // App rating activities
    'app_rated',
    // Feedback activities
    'feedback_submitted',
    // User rating activities
          'user_rated',
        'user_rating_received',
        'receipt_generated',
      // Quick transaction activities
      'quick_transaction_created',
      'quick_transaction_created_with_coins',
      'quick_transaction_updated',
      'quick_transaction_deleted',
      'quick_transaction_cleared',
      'quick_transaction_cleared_all',
      'quick_transaction_settlement_requested',
      'quick_transaction_settlement_accepted',
      'quick_transaction_settlement_rejected',
      // Friend activities
      'friend_request_sent',
      'friend_request_received',
      'friend_request_accepted',
      'friend_request_declined',
      'friend_request_canceled',
      'friend_removed',
      'user_blocked',
      'user_unblocked',
      'offer_accepted',
      'transaction_updated_by_admin'
        ],    required: true
  },
  title: {
    type: String,
    required: true
  },
  description: {
    type: String,
    required: true
  },
  metadata: {
    type: mongoose.Schema.Types.Mixed,
    default: {}
  },
  // Reference to related documents
  relatedTransaction: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Transaction'
  },
  relatedGroup: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'GroupTransaction'
  },
  relatedNote: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Note'
  },
  // Amount involved (for financial activities)
  amount: {
    type: Number,
    default: null
  },
  currency: {
    type: String,
    default: null
  },
  // IP address for security tracking
  ipAddress: {
    type: String,
    default: null
  },
  // User agent for device tracking
  userAgent: {
    type: String,
    default: null
  },
  bookmarked: {
    type: Boolean,
    default: false
  }
}, { 
  timestamps: true 
});

// Indexes for efficient querying
activitySchema.index({ user: 1, createdAt: -1 });
activitySchema.index({ type: 1 });
activitySchema.index({ relatedTransaction: 1 });
activitySchema.index({ relatedGroup: 1 });
activitySchema.index({ relatedNote: 1 });

module.exports = mongoose.model('Activity', activitySchema); 
