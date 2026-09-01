# LenDen

A full-stack peer-to-peer money management app for tracking lending and borrowing between friends and groups.

## Structure

```
Lenden/
├── backend/    Node.js + Express + MongoDB + Socket.IO + Firebase Admin
└── frontend/   Flutter (Android)
```

## Features

- **Quick Transactions** – record lend/borrow with OTP-verified settlement
- **Secure Transactions** – escrow-style partial payments with admin review
- **Group Transactions** – shared expense groups with budget limits, split tracking, and a built-in encrypted chat
- **Community** – shared spaces for splitting costs across larger groups
- **Real-time Chat** – end-to-end encrypted (X25519 + AES-GCM) direct and group chat with Firebase push notifications
- **LenDen Coins** – in-app currency earned through engagement and used for premium features
- **Wallet** – top-up and peer-to-peer pay via OTP-verified payments
- **Subscriptions** – feature gating with free-attempt counters and coin-based pay-per-use

## Quick Start

```bash
# Backend
cd backend && npm install && npm run dev

# Frontend
cd frontend && flutter pub get && flutter run
```

## Backend

Node.js + Express REST API with Socket.IO real-time chat and Firebase Admin push notifications.

**Required `.env` keys**

| Key | Description |
|-----|-------------|
| `MONGO_URI` | MongoDB connection string |
| `JWT_SECRET` | Secret for signing JWTs |
| `REFRESH_TOKEN_SECRET` | Secret for refresh tokens |
| `FIREBASE_SERVICE_ACCOUNT` | Firebase Admin service account JSON (stringified) |
| `EMAIL_USER` | SMTP sender address |
| `EMAIL_PASS` | SMTP password |
| `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` | Razorpay credentials |

`FIREBASE_SERVICE_ACCOUNT` can be omitted if a `firebase-service-account.json` file is placed at the project root.

```
backend/src/
├── controllers/    Route handlers and Socket.IO event handlers
├── models/         Mongoose schemas
├── routes/         Express routers (split by domain)
├── middleware/     Auth, rate limiting, validation
├── services/       notificationService, coinLedger, etc.
└── utils/          Subscription feature checks, pricing, helpers
```

## Frontend

Flutter app targeting Android. Requires `google-services.json` in `android/app/`.

**State management** — `Provider` via `SessionProvider` (`lib/session.dart`).

**HTTP** — `lib/utils/http_interceptor.dart` wraps every request with auth headers. On 401 it refreshes the token pair automatically. Both tokens are cached in-memory to avoid Android Keystore read-after-write failures on fresh installs.

**Encryption** — X25519 key agreement + AES-GCM-256 + HKDF. Public keys are stored per-device on the server; each message is encrypted for every registered device of every recipient.

```
frontend/lib/
├── user/
│   ├── transaction/
│   │   ├── quick_transactions/
│   │   ├── secure_transactions/
│   │   └── group_transactions/
│   ├── chats/
│   ├── community/
│   ├── digitise/
│   └── connections/
├── services/
│   ├── firebase_service.dart      FCM init + foreground banner
│   ├── chat_page_tracker.dart     Active chat page tracker
│   └── sound_service.dart
├── utils/
│   ├── http_interceptor.dart
│   └── api_client.dart
└── widgets/
```

## Push Notifications

Firebase Cloud Messaging (FCM) handles all chat notifications.

`backend/src/services/notificationService.js` — `sendToUser(User, userId, payload, options)` looks up the user's token, checks their `pushNotifications` and feature-specific settings, then calls `sendToToken`. Chat controllers call it fire-and-forget.

| Chat type | Controller | Guard |
|-----------|-----------|-------|
| Secure (1-to-1) | `chatController.js` | receiver offline + `chatNotifications` flag |
| Group | `groupChatController.js` | member offline + `groupNotifications` flag |

**Foreground suppression** — `lib/services/chat_page_tracker.dart` tracks which conversation the user is currently viewing. `firebase_service.dart` consults it on every `onMessage` event:

| User is on | Notification for | Show banner? |
|------------|-----------------|-------------|
| Same group chat | that group | No |
| Different group chat | another group | Yes |
| Secure chat A | chat A | No |
| Secure chat A | chat B | Yes |
| Any other page | any chat | Yes |
| Background / closed | any | FCM system tray |

## Localization

English and Hindi. All strings in `frontend/lib/l10n/app_localizations.dart` — plain Dart map, no code generation. Call `AppLocalizations.of(context).t('key')`.
