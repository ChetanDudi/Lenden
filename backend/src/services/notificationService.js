const path = require('path');
const fs   = require('fs');

let _initialized = false;

function _init() {
  if (_initialized) return;

  let serviceAccount;

  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    try {
      serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    } catch (e) {
      console.error('[FCM] Failed to parse FIREBASE_SERVICE_ACCOUNT env var:', e.message);
      return;
    }
  } else {
    const filePath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH
      || path.join(__dirname, '../../firebase-service-account.json');
    if (!fs.existsSync(filePath)) {
      console.warn('[FCM] No Firebase service account found. Push notifications disabled.');
      return;
    }
    try {
      serviceAccount = require(filePath);
    } catch (e) {
      console.error('[FCM] Failed to load service account file:', e.message);
      return;
    }
  }

  try {
    const { initializeApp, cert } = require('firebase-admin/app');
    initializeApp({ credential: cert(serviceAccount) });
    _initialized = true;
    console.log('[FCM] Firebase Admin initialized successfully.');
  } catch (e) {
    console.error('[FCM] initializeApp failed:', e.message);
  }
}

async function sendToToken(fcmToken, { title, body, data = {} }) {
  _init();
  if (!_initialized || !fcmToken) return;
  try {
    const { getMessaging } = require('firebase-admin/messaging');
    await getMessaging().send({
      token: fcmToken,
      notification: { title, body },
      data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
      android: {
        priority: 'high',
        notification: { channelId: 'lenden_high_importance', sound: 'default' },
      },
    });
  } catch (err) {
    if (err.code !== 'messaging/registration-token-not-registered' &&
        err.code !== 'messaging/invalid-registration-token') {
      console.error('[FCM] sendToToken error:', err.message);
    }
  }
}

// settingKey: optional notificationSettings field to check (e.g. 'groupNotifications')
async function sendToUser(UserModel, userId, payload, { settingKey } = {}) {
  try {
    const user = await UserModel.findById(userId).select('fcmToken notificationSettings');
    if (!user?.fcmToken) return;
    const s = user.notificationSettings || {};
    if (s.pushNotifications === false) return;
    if (settingKey && s[settingKey] === false) return;
    await sendToToken(user.fcmToken, payload);
  } catch (err) {
    console.error('[FCM] sendToUser error:', err.message);
  }
}

module.exports = { sendToToken, sendToUser };
