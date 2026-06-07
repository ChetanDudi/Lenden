const UserGiftCard = require('../models/userGiftCard');
const GiftCard = require('../models/giftCard');
const User = require('../models/user');
const { recordCoinLedgerEntry } = require('../utils/coinLedgerService');

// Helper: Check if user should get gift card (guaranteed once per window)
// Uses deterministic hash based on userId + windowNumber to pick random position
// windowSize: 3 for groups, 5 for user txns, 10 for quick txns
// currentCount: total count of this feature for the user
exports.shouldAwardGiftCard = (userId, currentCount, windowSize) => {
  if (currentCount < 1) return false;
  
  // Determine which window we're in (0-indexed)
  const windowNumber = Math.floor((currentCount - 1) / windowSize);
  
  // Create a deterministic hash using userId and windowNumber
  // This ensures the same random position for each window
  const hash = (userId.toString() + windowNumber.toString())
    .split('')
    .reduce((acc, char) => acc + char.charCodeAt(0), 0);
  
  // Pick random position within window (1 to windowSize)
  const randomOffset = (hash % windowSize) + 1;
  const windowStart = windowNumber * windowSize + 1;
  const targetPosition = windowStart + randomOffset - 1;
  
  // Award if current count matches the target
  return currentCount === targetPosition;
};

// Award a gift card to user (called after each transaction/group creation)
exports.awardGiftCard = async (userId, awardedFrom) => {
  try {
    // Get all admin-created gift cards
    const allGiftCards = await GiftCard.find({});
    
    if (allGiftCards.length === 0) {
      return null;
    }

    // Pick a random gift card from the pool
    const randomCard = allGiftCards[Math.floor(Math.random() * allGiftCards.length)];

    // Create user gift card entry
    const userGiftCard = await UserGiftCard.create({
      user: userId,
      giftCard: randomCard._id,
      coins: randomCard.value,
      scratched: false,
      awardedFrom,
    });

    return userGiftCard;
  } catch (error) {
    console.error('[Gift Card Award] Error awarding gift card:', error);
    return null;
  }
};

// Get user's unscratched gift cards
exports.getUnscractchedGiftCards = async (req, res) => {
  try {
    const userId = req.user._id;
    const cards = await UserGiftCard.find({ user: userId, scratched: false })
      .populate('giftCard', 'name value')
      .sort({ createdAt: -1 });

    res.status(200).json({ cards });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// Get user's scratched gift cards
exports.getScratcedGiftCards = async (req, res) => {
  try {
    const userId = req.user._id;
    const cards = await UserGiftCard.find({ user: userId, scratched: true })
      .populate('giftCard', 'name value')
      .sort({ scratchedAt: -1 });

    res.status(200).json({ cards });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// Scratch a gift card and claim coins
exports.scratchGiftCard = async (req, res) => {
  try {
    const { userGiftCardId } = req.params;
    const userId = req.user._id;

    // Find the user gift card
    const userGiftCard = await UserGiftCard.findById(userGiftCardId);
    if (!userGiftCard) {
      return res.status(404).json({ error: 'Gift card not found' });
    }

    // Verify ownership
    if (userGiftCard.user.toString() !== userId.toString()) {
      return res.status(403).json({ error: 'Unauthorized' });
    }

    // Check if already scratched
    if (userGiftCard.scratched) {
      return res.status(400).json({ error: 'Gift card already scratched' });
    }

    // Mark as scratched and add coins to user
    userGiftCard.scratched = true;
    userGiftCard.scratchedAt = new Date();
    await userGiftCard.save();

    // Add coins to user's lenDenCoins
    const user = await User.findById(userId);
    user.lenDenCoins += userGiftCard.coins;
    await user.save();
    await recordCoinLedgerEntry({
      userId,
      direction: 'earned',
      coins: userGiftCard.coins,
      source: 'gift_card_scratch',
      title: 'Gift Card Coins Claimed',
      description: `Claimed ${userGiftCard.coins} LenDen coins from a scratched gift card.`,
      metadata: {
        userGiftCardId: userGiftCard._id,
        awardedFrom: userGiftCard.awardedFrom,
      },
      occurredAt: userGiftCard.scratchedAt || new Date(),
    });

    // Populate gift card details for response
    const populatedCard = await UserGiftCard.findById(userGiftCardId)
      .populate('giftCard', 'name value');

    res.status(200).json({
      message: 'Gift card scratched successfully',
      coinsAdded: userGiftCard.coins,
      totalCoins: user.lenDenCoins,
      card: populatedCard,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// Get gift card counts for dashboard
exports.getGiftCardCounts = async (req, res) => {
  try {
    const userId = req.user._id;
    const unscratched = await UserGiftCard.countDocuments({ user: userId, scratched: false });
    const scratched = await UserGiftCard.countDocuments({ user: userId, scratched: true });

    res.status(200).json({
      unscratched,
      scratched,
      total: unscratched + scratched,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};
