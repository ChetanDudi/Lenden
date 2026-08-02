const admin = require('firebase-admin');
const path  = require('path');
const fs    = require('fs');

let _initialized = false;

function _init() {
  if (_initialized) return;
  let credential;

  // Priority 1: JSON string in env var (good for hosting platforms)
  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    try {
      const sa = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
      credential = admin.credential.cert(sa);
    } catch (e) {
      console.error('[FCM] Failed to parse FIREBASE_SERVICE_ACCOUNT env var:', e.message);
      return;
    }
  }
  // Priority 2: path to service account JSON file
  else {
    const filePath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH
      || path.join(__dirname, '../../firebase-service-account.json');

    if (!fs.existsSync(filePath)) {
      console.warn('[FCM] No Firebase service account found. Push notifications are disabled.');
      console.warn('[FCM] Set FIREBASE_SERVICE_ACCOUNT env var or place firebase-service-account.json in backend/');
      return;
    }
    try {
      credential = admin.credential.cert(require(filePath));
    } catch (e) {
      console.error('[FCM] Failed to load service account file:', e.message);
      return;
    }
  }

  try {
    admin.initializeApp({ credential });
    _initialized = true;
    console.log('[FCM] Firebase Admin initialized successfully.');
  } catch (e) {
    console.error('[FCM] initializeApp failed:', e.message);
  }
}

/**
 * Send a push notification to a single FCM token.
 * Silently ignores invalid/expired tokens.
 */
async function sendToToken(fcmToken, { title, body, data = {} }) {
  _init();
  if (!_initialized || !fcmToken) return;
  try {
    await admin.messaging().send({
      token: fcmToken,
      notification: { title, body },
      data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
      android: {
        priority: 'high',
        notification: { channelId: 'lenden_high_importance', sound: 'default' },
      },
    });
  } catch (err) {
    // Expired / unregistered tokens — nothing to do
    if (err.code !== 'messaging/registration-token-not-registered' &&
        err.code !== 'messaging/invalid-registration-token') {
      console.error('[FCM] sendToToken error:', err.message);
    }
  }
}

/**
 * Look up a user's FCM token from the DB and send a push notification.
 * Pass `User` model to avoid circular imports.
 */
async function sendToUser(UserModel, userId, payload) {
  try {
    const user = await UserModel.findById(userId).select('fcmToken');
    if (user?.fcmToken) await sendToToken(user.fcmToken, payload);
  } catch (err) {
    console.error('[FCM] sendToUser error:', err.message);
  }
}

module.exports = { sendToToken, sendToUser };
