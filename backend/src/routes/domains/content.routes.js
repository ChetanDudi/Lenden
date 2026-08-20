module.exports = (router, { auth, isAdmin, handleAdUpload }) => {
  const appContentController = require('../../controllers/appContentController');
  const offerController = require('../../controllers/offerController');
  const giftCardController = require('../../controllers/giftCardController');
  const userGiftCardController = require('../../controllers/userGiftCardController');
  const notificationController = require('../../controllers/notificationController');
  const feedbackController = require('../../controllers/feedbackController');
  const noteController = require('../../controllers/noteController');

  // App updates (user)
  router.get('/app-updates', auth, appContentController.listUpdates);
  router.post('/app-updates/:updateId/read', auth, appContentController.markUpdateRead);
  router.post('/app-updates/read-all', auth, appContentController.markAllUpdatesRead);

  // Ads (user)
  router.get('/ads/random', auth, appContentController.getRandomActiveAd);
  router.post('/ads/:adId/events', auth, appContentController.trackAdEvent);
  router.get('/ads/media/:fileId', appContentController.streamAdMedia);

  // Offers (user)
  router.get('/offers/available', auth, offerController.getAvailableOffers);
  router.post('/offers/:offerId/accept', auth, offerController.acceptOffer);
  router.get('/offers/my-claims', auth, offerController.getMyOfferClaims);

  // Gift cards (user)
  router.get('/gift-cards/unscratched', auth, userGiftCardController.getUnscractchedGiftCards);
  router.get('/gift-cards/scratched', auth, userGiftCardController.getScratcedGiftCards);
  router.post('/gift-cards/:userGiftCardId/scratch', auth, userGiftCardController.scratchGiftCard);
  router.get('/gift-cards/counts', auth, userGiftCardController.getGiftCardCounts);

  // Notifications (user)
  router.get('/notifications', auth, notificationController.getNotifications);
  router.get('/notifications/unread-count', auth, notificationController.getUnreadNotificationCount);
  router.post('/notifications/mark-as-read', auth, notificationController.markNotificationsAsRead);
  router.delete('/notifications/clear-read', auth, notificationController.clearReadNotifications);
  router.delete('/notifications/:id', auth, notificationController.deleteNotification);

  // Feedback (user)
  router.post('/feedback', auth, feedbackController.submitFeedback);
  router.get('/feedback/my', auth, feedbackController.getUserFeedbacks);

  // Notes — specific paths before :id to avoid param capture
  router.get('/notes/shared', auth, noteController.getSharedNotes);
  router.get('/notes/recipients', auth, noteController.searchNoteRecipients);
  router.post('/notes/share-content', auth, noteController.shareContentAsNote);
  router.post('/notes', auth, noteController.createNote);
  router.get('/notes', auth, noteController.getNotes);
  router.post('/notes/:id/share', auth, noteController.shareNote);
  router.put('/notes/:id', auth, noteController.updateNote);
  router.delete('/notes/:id', auth, noteController.deleteNote);

  // Admin: content analytics overview
  router.get('/admin/content-analytics', auth, isAdmin, appContentController.getAdminContentAnalytics);

  // Admin: app updates
  router.post('/admin/app-updates', auth, isAdmin, appContentController.createUpdate);
  router.put('/admin/app-updates/:updateId', auth, isAdmin, appContentController.updateUpdate);
  router.delete('/admin/app-updates/:updateId', auth, isAdmin, appContentController.deleteUpdate);

  // Admin: ads
  router.get('/admin/ads', auth, isAdmin, appContentController.listAdminAds);
  router.post('/admin/ads', auth, isAdmin, handleAdUpload, appContentController.createAd);
  router.put('/admin/ads/:adId', auth, isAdmin, handleAdUpload, appContentController.updateAd);
  router.patch('/admin/ads/:adId', auth, isAdmin, appContentController.toggleAd);
  router.delete('/admin/ads/:adId', auth, isAdmin, appContentController.deleteAd);

  // Admin: offers
  router.post('/admin/offers', auth, isAdmin, offerController.createOffer);
  router.get('/admin/offers', auth, isAdmin, offerController.getAdminOffers);
  router.get('/admin/offers/users', auth, isAdmin, offerController.searchUsersForOffers);
  router.get('/admin/offers/:offerId/analytics', auth, isAdmin, offerController.getOfferAnalytics);
  router.get('/admin/offers/:offerId/claims', auth, isAdmin, offerController.getOfferClaimsAudit);
  router.put('/admin/offers/:offerId', auth, isAdmin, offerController.updateOffer);
  router.delete('/admin/offers/:offerId', auth, isAdmin, offerController.deleteOffer);

  // Admin: gift cards
  router.post('/admin/giftcards', auth, isAdmin, giftCardController.createGiftCard);
  router.get('/admin/giftcards', auth, isAdmin, giftCardController.getGiftCards);
  router.put('/admin/giftcards/:id', auth, isAdmin, giftCardController.updateGiftCard);
  router.delete('/admin/giftcards/:id', auth, isAdmin, giftCardController.deleteGiftCard);

  // Admin: notifications
  router.post('/notifications', auth, isAdmin, notificationController.createNotification);
  router.get('/notifications/sent', auth, isAdmin, notificationController.getSentNotifications);
  router.get('/notifications/audience-preview', auth, isAdmin, notificationController.getAudiencePreview);
  router.put('/notifications/:id', auth, isAdmin, notificationController.updateNotification);

  // Admin: feedback
  router.get('/feedbacks/all', auth, isAdmin, feedbackController.getAllFeedbacks);
};
