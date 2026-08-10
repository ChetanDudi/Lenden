module.exports = (router, { auth, isAdmin, io }) => {
  const friendController = require('../../controllers/friendController');
  const ratingController = require('../../controllers/ratingController');
  const AppratingController = require('../../controllers/AppratingController');
  const leaderboardController = require('../../controllers/leaderboardController');
  const referralController = require('../../controllers/referralController');
  const coinLedgerController = require('../../controllers/coinLedgerController');
  const activityController = require('../../controllers/activityController');
  const chatController = require('../../controllers/chatController')(io);

  // App rating (star rating for the LenDen app itself)
  router.post('/rating', auth, AppratingController.submitRating);
  router.get('/rating/my', auth, AppratingController.getMyRating);
  router.get('/rating/all', auth, isAdmin, AppratingController.getAllRatings);
  router.get('/feedback/app-ratings', AppratingController.getAppRatings);

  // Peer user ratings
  router.get('/ratings/me', auth, ratingController.getMyRatings);
  router.get('/ratings/top', auth, ratingController.getTopRatedUsers);
  router.post('/ratings', auth, ratingController.rateUser);
  router.patch('/ratings/:ratingId', auth, ratingController.updateRating);
  router.get('/ratings/user-avg', auth, ratingController.getUserAvgRating);

  // Friends
  router.get('/friends', auth, friendController.getFriends);
  router.get('/friends/search', auth, friendController.searchUsers);
  router.get('/friends/suggestions', auth, friendController.getFriendSuggestions);
  router.get('/friends/mutual', auth, friendController.getMutualFriends);
  router.post('/friends/mutual-counts', auth, friendController.getMutualFriendCounts);
  router.get('/friends/requests', auth, friendController.getFriendRequests);
  router.post('/friends/request', auth, friendController.sendFriendRequest);
  router.post('/friends/add', auth, friendController.sendFriendRequest);
  router.post('/friends/requests/:requestId/accept', auth, friendController.acceptFriendRequest);
  router.post('/friends/requests/:requestId/decline', auth, friendController.declineFriendRequest);
  router.post('/friends/requests/:requestId/cancel', auth, friendController.cancelFriendRequest);
  router.post('/friends/block', auth, friendController.blockUser);
  router.post('/friends/unblock', auth, friendController.unblockUser);
  router.delete('/friends/:friendId', auth, friendController.removeFriend);
  router.get('/friends/birthdays', auth, friendController.getBirthdayFriends);
  router.post('/friends/:userId/wish', auth, friendController.sendBirthdayWish);
  router.post('/friends/:userId/gift', auth, friendController.sendBirthdayGift);

  // Leaderboard
  router.get('/leaderboard', auth, leaderboardController.getDailyLeaderboard);
  router.get('/leaderboard/rewards/me', auth, leaderboardController.getMyMonthlyRewardSummary);

  // Referral & coins
  router.get('/referral/me', auth, referralController.getReferralInfo);
  router.post('/referral/share', auth, referralController.logReferralShare);
  router.get('/coins/history', auth, coinLedgerController.getMyCoinHistory);
  router.post('/coins/buy-with-wallet', auth, coinLedgerController.buyCoinsWithWallet);

  // Activity feed
  router.get('/activities', auth, activityController.getUserActivities);
  router.get('/activities/stats', auth, activityController.getActivityStats);
  router.delete('/activities/:activityId', auth, activityController.deleteActivity);
  router.patch('/activities/:activityId/bookmark', auth, activityController.bookmarkActivity);
  router.delete('/activities/cleanup', auth, activityController.cleanupOldActivities);

  // 1-to-1 chat
  router.get('/chat/messages/:transactionId', auth, chatController.getMessages);
};
