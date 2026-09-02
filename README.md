# LenDen

A full-stack peer-to-peer money management app for tracking lending, borrowing, and shared expenses between friends and groups.

## Structure

```
Lenden/
├── backend/    Node.js + Express + MongoDB + Socket.IO + Firebase Admin
└── frontend/   Flutter (Android)
```

---

## Features

### Transactions
| Feature | Description |
|---------|-------------|
| **Quick Transactions** | Record lend/borrow instantly; OTP-verified settlement; recurring templates; scheduled transactions |
| **Secure Transactions** | Escrow-style flow with partial payments, repayment schedules, admin review, and a full payment timeline |
| **Group Transactions** | Shared expense groups with budget caps, per-member split tracking, expense sheets, and built-in encrypted group chat |

### Social & Community
| Feature | Description |
|---------|-------------|
| **Community** | Shared spaces for larger groups; public/private/invite-only privacy; post feed with media; star favourites; community settings |
| **Connections** | Friend requests, mutual friends display, counterparty tracking across transactions |
| **Real-time Chat** | End-to-end encrypted 1-to-1 and group chat; message counts; member search |

### Finance & Wallet
| Feature | Description |
|---------|-------------|
| **Wallet** | Balance top-up via Razorpay; OTP-verified peer-to-peer payments; 4-digit PIN protection; transaction history |
| **Budget Planning** | Monthly, category, and group budgets; savings goals; recurring budgets; budget alerts |
| **Smart Insights** | Spending analysis, weekly summaries, financial health score, goal forecasts, AI-style saving tips |
| **Reports** | Income/expense reports, category breakdowns, trend charts, group reports, exportable statements |
| **Due Date Calendar** | Visual calendar of upcoming transaction due dates |

### Gamification & Rewards
| Feature | Description |
|---------|-------------|
| **LenDen Coins** | In-app currency earned through daily logins, referrals, and engagement; spent on premium features |
| **Activity & Leaderboard** | Engagement scoring; monthly leaderboard with coin rewards for top finishers |
| **Subscriptions** | Feature gating with free-attempt counters and coin-based pay-per-use; admin-managed plans |
| **Referrals** | Referral link/code system with configurable coin rewards |

### Utility
| Feature | Description |
|---------|-------------|
| **QR Scanner** | Scan-to-pay via QR code |
| **Notifications** | In-app notification centre with read/unread state and category filtering |
| **Disputes** | User-initiated dispute flow with admin resolution |
| **Support** | Help & FAQ, contact form, feedback, personal notes |
| **Ads & Updates** | Admin-published app updates and promotional banners |

---

## Themes & Languages

### Themes
The app supports three display modes, persisted per user account:

| Mode | Behaviour |
|------|-----------|
| **Light** | Always light |
| **Dark** | Always dark |
| **System** | Follows device setting (default for new accounts) |

Theme preference is loaded from the backend on login and stored locally via `ThemeProvider` (`lib/utils/theme_provider.dart`).

### Languages
Two locales are supported:

| Code | Language |
|------|----------|
| `en` | English (default) |
| `hi` | Hindi |

All strings live in `frontend/lib/l10n/app_localizations.dart` — a plain Dart map, no code generation required. Usage: `AppLocalizations.of(context).t('key')`. Language preference is persisted per user via `LocaleProvider` (`lib/utils/locale_provider.dart`).

---

## Security

### Authentication
- **JWT** access tokens (short-lived) + refresh token rotation. Both tokens are cached in-memory on the frontend to avoid Android Keystore read-after-write failures on fresh installs.
- **OTP verification** gates login, transaction settlement, and wallet peer-to-peer payments. OTPs are single-use and expire after a short window.
- **Session timeout** — configurable per user (in minutes; `0` = never, which is the default). The backend reads `privacySettings.sessionTimeout` from the user document and returns HTTP `440` when the session has been idle beyond the threshold. JWT `iat` is used as a floor so a freshly issued token can never trigger a timeout, regardless of any stale `lastActivityAt` value in the database. The Flutter interceptor catches `440`, clears tokens, and redirects to the login screen.

### App-Level Locks
- **App lock** — optional PIN or biometric lock that activates when the app is backgrounded (`lib/settings/app_lock_setup_page.dart`).
- **Wallet PIN** — separate 4-digit PIN required to authorise wallet operations (`lib/settings/set_wallet_pin_page.dart`).

### Encryption
- **Chat (E2E)** — X25519 Diffie-Hellman key agreement, HKDF key derivation, AES-GCM-256 encryption. Public keys are stored per-device on the server. Each message is encrypted individually for every registered device of every recipient. Key material never leaves the device in plaintext (`lib/user/chats/chat_encryption_service.dart`).

### Rate Limiting (backend)

| Limiter | Window | Max requests |
|---------|--------|-------------|
| Global API | 15 min | 300 |
| Login | 15 min | 10 |
| OTP send | 10 min | 5 |
| OTP verify | 10 min | 10 |
| Password reset | 15 min | 10 |
| User search | 1 min | 30 |
| Manual payment verify | 15 min | 10 |

Razorpay webhooks are exempt from the global limiter.

### Content Safety
- Profanity filtering (`bad-words`, `leo-profanity`, `french-badwords-list`) applied to user-generated content.
- Admin review step for withdrawal requests before funds are released.

---

## Quick Start

```bash
# Backend
cd backend && npm install && npm run dev

# Frontend
cd frontend && flutter pub get && flutter run
```

---

## Backend

Node.js + Express REST API with Socket.IO real-time chat and Firebase Admin push notifications.

### Required `.env` keys

| Key | Description |
|-----|-------------|
| `MONGO_URI` | MongoDB connection string |
| `JWT_SECRET` | Secret for signing access JWTs |
| `REFRESH_TOKEN_SECRET` | Secret for refresh tokens |
| `FIREBASE_SERVICE_ACCOUNT` | Firebase Admin service account JSON (stringified) |
| `EMAIL_USER` | SMTP sender address |
| `EMAIL_PASS` | SMTP password |
| `RAZORPAY_KEY_ID` | Razorpay key ID |
| `RAZORPAY_KEY_SECRET` | Razorpay key secret |

`FIREBASE_SERVICE_ACCOUNT` can be omitted if a `firebase-service-account.json` file is placed at the backend root.

### Source layout

```
backend/src/
├── controllers/    Route handlers (REST + Socket.IO events)
├── models/         Mongoose schemas (50+ models)
├── routes/         Express routers, split by domain
│   └── domains/    auth, user, social, group, community, content, wallet, admin …
├── middleware/     auth.js, sessionTimeout.js, rateLimit.js, validation
├── services/       notificationService.js, coinLedger.js
└── utils/          subscriptionFeatureCheck.js, coinPricing.js, email templates
```

### Key middleware

- **`auth.js`** — verifies JWT, attaches `req.user`
- **`sessionTimeout.js`** — checks `privacySettings.sessionTimeout`; returns 440 on idle expiry; uses `req.user.iat` as floor to protect fresh logins
- **`rateLimit.js`** — per-route express-rate-limit instances (see Security section)

---

## Frontend

Flutter app targeting Android. Requires `google-services.json` in `android/app/`.

### State management
`Provider` via `SessionProvider` (`lib/session.dart`), `ThemeProvider`, `LocaleProvider`, `CurrencyProvider`.

### HTTP
`lib/utils/http_interceptor.dart` wraps every request with auth headers. On 401 it silently refreshes the token pair. On 440 it clears session and redirects to login via `AuthNavigation.redirectToLogin()`.

### Encryption
`lib/user/chats/chat_encryption_service.dart` — X25519 + HKDF + AES-GCM-256. Public keys uploaded per-device on first chat init; re-uploaded automatically if missing.

### Source layout

```
frontend/lib/
├── admin/              Admin-only pages (dashboard, user mgmt, transactions, …)
├── login/              Login, registration, OTP verification
├── profile/            Profile page
├── settings/           Settings (theme, language, notifications, privacy, locks, …)
├── user/
│   ├── activity/       Activity feed, leaderboard
│   ├── budget/         Budget planning, goals, recurring
│   ├── calendar/       Due date calendar
│   ├── chats/          1-to-1 and group chat pages, encryption service
│   ├── community/      Community list, detail, creation
│   ├── connections/    Friends, counterparties
│   ├── dashboard/      Main dashboard
│   ├── digitise/       Coins, subscriptions, offers, gift cards, referrals
│   ├── favorites/      Starred communities
│   ├── insights/       Smart insights tabs
│   ├── notifications/  Notification centre
│   ├── rating/         App ratings
│   ├── reports/        Financial reports and export
│   ├── scanner/        QR scanner and user QR code
│   ├── statements/     Statement export
│   ├── support/        Help, contact, feedback, notes, disputes
│   ├── transaction/
│   │   ├── quick_transactions/
│   │   ├── secure_transactions/
│   │   └── group_transactions/
│   └── wallet/         Wallet page, payment sheet, PIN auth
├── services/
│   ├── firebase_service.dart       FCM init + foreground notification banner
│   ├── chat_page_tracker.dart      Tracks active chat to suppress redundant banners
│   └── sound_service.dart
├── utils/
│   ├── http_interceptor.dart
│   ├── api_client.dart
│   ├── community_helpers.dart      Keyword-based image URL helpers
│   ├── theme_provider.dart
│   ├── locale_provider.dart
│   └── currency_provider.dart
└── widgets/                        Shared UI components
```

### Image fallbacks
- **Communities** — `/api/communities/:id/image` endpoint serves the uploaded photo or redirects to a keyword-matched Unsplash URL. Error builder shows a colour gradient.
- **Groups** — `defaultGroupImageUrl()` returns a keyword-matched URL, or `''` for unrecognised names. When empty, cards show a colour gradient with the group's initial letter directly (no failing network request).

---

## Admin Panel

Accessible to users with the `admin` role. Separate route namespace, separate settings pages.

| Section | Capabilities |
|---------|-------------|
| **Dashboard** | Overview metrics and quick actions |
| **User Management** | View, edit, assign roles, track activity |
| **Transactions** | Oversee quick, secure, group transactions; approve withdrawals; manage scan payments; view real and in-app payments |
| **Community & Content** | Moderate community posts; manage ads and app updates |
| **Coins & Subscriptions** | Configure coin pricing, subscription plans, offers, gift cards, referral settings |
| **Budget** | Admin budget overview |
| **Insights & Reports** | Platform-wide analytics and reports |
| **Disputes & Fraud** | Manage user disputes; view fraud alerts |
| **Support** | Review support queries, contact messages, feedbacks, admin notes |
| **Audit** | Full audit log of admin actions |
| **System** | Maintenance mode, backup/restore, data export, notification settings, security settings (session timeout, login alerts), analytics settings |

---

## Push Notifications

Firebase Cloud Messaging (FCM) handles all push notifications.

`backend/src/services/notificationService.js` — `sendToUser(User, userId, payload, options)` looks up the user's FCM token, checks their `pushNotifications` and feature-specific flags, then calls `sendToToken`.

| Chat type | Controller | Guard |
|-----------|------------|-------|
| Secure (1-to-1) | `chatController.js` | receiver offline + `chatNotifications` flag |
| Group | `groupChatController.js` | member offline + `groupNotifications` flag |

**Foreground suppression** — `lib/services/chat_page_tracker.dart` tracks which conversation the user is viewing. `firebase_service.dart` consults it on every `onMessage` event:

| User is on | Notification for | Show banner? |
|------------|-----------------|--------------|
| Same group chat | that group | No |
| Different group chat | another group | Yes |
| Secure chat A | chat A | No |
| Secure chat A | chat B | Yes |
| Any other page | any chat | Yes |
| Background / closed | any | FCM system tray |

---

## Known Limitations

- Android only (no iOS build target configured).
- Wallet top-up uses Razorpay; withdrawal approval is manual (admin-reviewed, no automated payout integration).
- Unsplash keyword images for communities depend on Unsplash availability; communities without a matching keyword fall back to a pool of generic Unsplash URLs served via backend redirect.
