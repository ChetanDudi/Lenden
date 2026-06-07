const { cleanupExpiredOffers } = require('../controllers/offerController');

let offerCleanupInterval = null;

const runCleanup = async () => {
  try {
    const result = await cleanupExpiredOffers();
    if (result.deletedOffers > 0 || result.deletedClaims > 0) {
    }
  } catch (error) {
    console.error('[OfferCleanup] Failed:', error.message);
  }
};

const initializeOfferCleanupScheduler = () => {
  if (offerCleanupInterval) return;

  runCleanup();
  offerCleanupInterval = setInterval(runCleanup, 60 * 60 * 1000);
};

module.exports = {
  initializeOfferCleanupScheduler,
};
