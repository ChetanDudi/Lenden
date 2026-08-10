# LenDen — Peer-to-Peer Money Management App

LenDen is a full-stack mobile application for tracking and settling money between friends, built with **Flutter** (frontend) and **Node.js + MongoDB** (backend). It combines a digital wallet, multiple transaction types, gamification, a full admin panel, and real-time chat into a single platform.

---

## Tech Stack

| Layer | Technologies |
|---|---|
| Mobile | Flutter (Dart), Provider, Socket.IO Client |
| Backend | Node.js, Express.js, MongoDB (Mongoose) |
| Real-time | Socket.IO |
| Payments | Razorpay (orders, webhooks, manual review) |
| Auth | JWT (access + refresh tokens), Google OAuth 2.0 |
| Email | Nodemailer (OTP, receipts, notifications) |
| Scheduling | node-cron (7 background jobs) |
| PDF | PDFKit (receipts, statements) |
| Logging | Winston |

---

## Repository Structure

```
Lenden/
├── backend/          # Node.js + Express API
│   └── src/
│       ├── controllers/
│       ├── middleware/
│       ├── models/
│       ├── routes/
│       └── utils/
└── frontend/         # Flutter app
    └── lib/
        ├── admin/
        ├── login/
        ├── profile/
        ├── settings/
        ├── user/
        │   ├── activity/
        │   ├── budget/
        │   ├── calendar/
        │   ├── chats/
        │   ├── connections/
        │   ├── digitise/
        │   ├── support/
        │   ├── transaction/
        │   └── wallet/
        └── widgets/
```

---

## Features

### Authentication & Account

- **Email + OTP** registration with email verification
- **Email + Password** login with rate limiting
- **Google Sign-In** (OAuth 2.0)
- **OTP-only login** (passwordless)
- **Forgot password** with email OTP reset
- **Account recovery** via alternative email
- **Multi-device session management** — view active sessions, logout specific devices or all
- **Alternative email** — add/verify a backup email for account recovery
- **App version check** — force-update gate before login

---

### LenDen Wallet

- Real-money wallet balance per user
- **Top-up via Razorpay** — Payment Handle link + manual payment verification
- **Pay User** — transfer wallet balance to any registered user (OTP or PIN)
- **Transaction PIN** — set/change/remove a 4-digit wallet PIN for fast auth
- **Wallet history** — paginated ledger of all credits, debits, top-ups, and withdrawals
- **Withdrawal** — request payout to bank (admin-reviewed; no RazorpayX required)
- **QR/Scan payments** — scan a UPI QR code to request an external payment (admin-reviewed)
- All outgoing wallet operations are gated by `walletAuthMiddleware` (PIN or OTP)

---

### Quick Transactions

Track informal lending and borrowing between two people.

- Create a Quick Transaction (lender ↔ borrower, amount, category, description)
- **Request & respond to settlement** — counterparty accepts or rejects
- **Pay via wallet** — settle directly through the LenDen wallet
- **Clear / Delete** transactions
- **Scheduled transactions** — set a future date for automatic creation
- **Recurring templates** — define a template that repeats on a schedule
- **Friend balances** — see net balance with each contact at a glance
- **Favourites** — pin important transactions
- **Request money** — send a money request to another user
- Create with **LenDen Coins** as a fee alternative

---

### Secure Transactions (Lend/Borrow Agreements)

Formal agreements with file attachments and OTP confirmation from both parties.

- Create with amount, due date, files (up to 10 MB each), and counterparty OTP verification
- **Partial payments** — record multiple partial payments against one agreement
- **PIN or OTP** gate on each partial payment
- **Clear / Delete** with audit trail
- **Favourites**
- **Email receipt** — PDF receipt sent on creation and settlement
- Per-transaction **in-app encrypted chat** (end-to-end encrypted, Socket.IO)
- Create with LenDen Coins

---

### Group Transactions

Shared expense tracking for groups of any size.

- Create a group (name, image, color, up to N members)
- **Join by code** — generate a shareable join code
- Add / remove members
- Add, edit, delete expenses with equal or custom splits
- **Settle member expenses** (OTP-verified)
- **Self-settle** your share
- **Record wallet payment** for a member
- **Group leave requests** — members request leave; creator approves
- **Group statistics** — per-member totals, outstanding balances
- **Group receipt** — PDF summary of all expenses
- **Group image & custom color**
- **Favourites**
- **Group chat** (Socket.IO, encrypted)
- Create with LenDen Coins

---

### QR / Scan Payments

- Scan a UPI QR code from inside the app
- Initiates an admin-reviewed payment request
- Admin approves or rejects; user wallet is debited/refunded accordingly

---

### LenDen Coins (Gamification)

An in-app coin economy that rewards engagement.

| Source | How earned |
|---|---|
| Daily login | Automatic on first app open each day |
| Referral | Referee completes registration |
| Monthly leaderboard | Top-ranked users receive coins |
| Gift card scratch | Scratch a gift card to reveal coin reward |
| Offer claims | Complete an admin-created offer task |

- **Buy coins with wallet balance** (configurable pricing, admin-set)
- **Coin history** — full ledger of earned and spent coins
- **Use coins** — spend coins to create transactions instead of paying fees
- Coin usage is validated by `coinUsageGuard` (prevents double-spend)

---

### Gift Cards

- Admin creates gift cards (coin value, quantity, expiry)
- Users receive unscratched gift cards (via referral, offers, or admin grants)
- **Scratch mechanic** — reveal and credit coins in one tap
- Scratched / unscratched history with counts

---

### Offers

- Admin creates time-limited offers with coin rewards
- Users browse available offers and **claim** them
- Per-offer analytics visible to admin (claim counts, user list)
- Offer cleanup scheduler auto-expires old offers

---

### Referral Program

- Each user gets a unique referral code/link
- **Log referral share** events (track how users share)
- Admin controls reward amounts and eligibility via Referral Config
- Referee must complete registration for referrer to earn coins

---

### Leaderboard

- Daily leaderboard ranked by transaction volume or activity
- **Monthly rewards** — top users automatically receive coins at month-end
- View personal monthly reward summary

---

### Friends & Social

- **Search users** by name or email
- **Friend requests** — send, accept, decline, cancel
- **Mutual friends** display
- **Block / Unblock** users
- **Remove friend**
- **Birthdays** — see upcoming friend birthdays
- **Birthday wish** — send an in-app wish
- **Birthday gift** — send coins as a gift
- Friend suggestions

---

### Budget & Finance Tools

- **Monthly budget** — set overall and per-category spending limits
- **Budget alerts** — configurable threshold notifications
- **Category budgets** — granular limits per expense category
- **Budget rollover** — carry unused budget to next month
- **Budget streak** — track consecutive months under budget
- **Recurring expenses** — log fixed monthly costs
- **Budget messages** — system messages when limits are approached or exceeded
- **Savings goals** — create, fund, and track financial goals
- **Smart Insights** — AI-style spending tips and pattern analysis
- **Financial Reports** — spending summary across all transaction types
- **Statement export** — download a CSV statement for any date range
- **Due Date Calendar** — calendar view of all upcoming payment due dates
- **Lending Budget Page** — overview of all active lending/borrowing

---

### Subscriptions (Premium Plans)

- Admin-managed subscription plans (name, price, duration, benefits)
- Purchase via Razorpay or wallet balance
- **Auto-renew** toggle
- Subscription history
- **Premium Benefits** page (feature list for each plan)
- **FAQs** page (managed by admin)
- Subscription expiry scheduler auto-deactivates lapsed subscriptions

---

### Notifications

- Admin creates notifications targeting all users, specific roles, or premium subscribers
- Users see in-app notification feed with unread count badge
- **Mark as read / clear read** notifications
- **Audience preview** — admin sees estimated reach before sending

---

### Support

- **Support queries** — users submit tickets; admins reply in real-time via Socket.IO
- **Contact form** — pre-categorised messages to admin team
- **Disputes** — raise a formal dispute on a transaction; admin resolves with status update
- **Feedback** — star rating + comment
- **App rating** — public rating visible on app
- **Notes** — private personal notes (user-side and admin-side)
- **Help & Support** page with FAQ-style content

---

### Privacy & Account Settings

- **Change password** (OTP-verified)
- **Set password** for Google-only accounts (OTP-verified)
- **Notification settings** — toggle per-event notification preferences
- **Privacy settings** — control profile visibility
- **Account information** — update display name, username
- **Export data** — download a JSON archive of personal data
- **Delete account** (OTP-verified, permanent)
- **App lock** — biometric or PIN lock on app open
- **Theme** — light / dark mode toggle
- **Language / Localisation** — i18n support via Flutter `flutter_localizations`

---

### Activity Feed

- Chronological log of all user actions (transactions created, settled, payments, etc.)
- **Bookmark** activity entries
- **Delete** individual entries or auto-cleanup old ones
- Activity statistics

---

### In-App Chat

- Per-transaction encrypted chat (Secure Transactions)
- Group chat (Group Transactions)
- End-to-end encryption using X25519 key exchange + AES-GCM
- Public keys stored per user; encrypted on device before upload
- Real-time delivery via Socket.IO

---

### Currency Conversion

- Admin-managed exchange rates for supported currencies
- **Live rate sync** from European Central Bank (ECB) every 4 hours via cron
- Public currency matrix for users (read-only)

---

## Admin Panel

### Dashboard

- Platform overview: total users, total transactions, wallet volume, subscription revenue
- Active sessions count, new signups trend

### User Management

- List all users with search, filter, and pagination
- View full user profile + transaction history + activity log
- **Suspend / Reactivate** accounts with reason
- **Force logout** any user from all devices
- **Bulk status update**
- Add admin notes to user profiles
- **Edit** user profile fields directly
- **Delete** user (irreversible, cascades related data)
- **Export** user list to CSV
- Track pending registrations; approve or reject

### Admin Role Management

- Add / remove admin accounts
- Toggle **Super Admin** status
- Set granular **permissions** per admin
- Full **Audit Log** of all admin actions

### Transaction Management

- **Secure Transactions** — list, edit, delete across all users
- **Quick Transactions** — list, edit, delete
- **Group Transactions** — list, edit members, add/edit/delete expenses, settle

### Real-Money Payments (Admin Review)

- **Wallet Top-ups** — view all Razorpay top-up attempts with status
- **Withdrawals** — list pending/processed/rejected withdrawal requests; mark processed or reject
- **Scan Payments** — list pending QR-scan payment requests; approve or reject

### In-App Payments

Full transaction monitor for all internal wallet movements, with tabs for each category:

| Tab | Data source |
|---|---|
| All | All wallet debits/credits |
| P2P | User-to-user wallet transfers |
| Quick Tx | QuickTransaction model (all, not just wallet-paid) |
| Secure Tx | Secure transaction wallet payments |
| Group | Group wallet payments |
| QR/Scan | QR scan payment wallet records |
| Plans | Subscription wallet payments |
| Coins | Coin purchase wallet payments |
| Rewards | CoinLedger — all coin earnings |
| Gift Cards | CoinLedger — gift card scratches |
| Offer Coins | CoinLedger — offer claim rewards |
| Refunds | Credit entries matching refund/reversed pattern |

**Per-tab features:**
- Per-category count badges on tabs
- Stats chips (total volume, count, cleared/pending for Quick Tx, earned/spent for Coins)
- 7-day volume chart (custom bar chart, no external chart library required)
- **Search** by name, email, or note
- **Date presets** (Today / This Week / This Month) + custom date range
- **Amount range filter** (Min ₹ / Max ₹)
- **Flagged only** chip — surface admin-flagged suspicious transactions
- **Failed / Reversed** status filter (wallet tabs)
- **Cleared / Pending** filter (Quick Tx tab)
- **User drill-down** — tap any user row to see all their transactions in that category
- **Flag / Unflag** individual transactions
- **Copy ID** on long-press
- **CSV export** with active filters respected
- Pagination with Load More

### Subscriptions (Admin)

- Create / edit / delete subscription plans (price, duration, features)
- Manage premium benefits list
- **Grant subscription** to any user manually
- Activate / deactivate / reactivate individual subscriptions
- Subscription analytics: total count, active, expiring soon, revenue, plan breakdown

### Gift Cards (Admin)

- Create gift cards (coin value, batch quantity, expiry)
- Edit / delete
- View issued vs. scratched counts

### Offers (Admin)

- Create time-limited offers with coin rewards and eligibility rules
- Edit / delete / expire offers
- Per-offer analytics: claim count, user claim audit list

### Referral Config (Admin)

- Set referrer coin reward amount
- Set referee coin reward amount
- Enable / disable the referral programme

### Currency Conversions (Admin)

- View and edit exchange rates for all supported currencies
- Add new supported currencies
- Trigger a manual live-rate sync from ECB

### Coin Pricing (Admin)

- Set the wallet price per LenDen coin
- Effective immediately for all new purchases

### FAQs (Admin)

- Create / edit / delete FAQ entries shown on the user-side Help page

### Notifications (Admin)

- Create targeted notifications (all users / admins / premium subscribers)
- Audience preview before sending
- View sent notification history

### Fraud & Disputes (Admin)

- **Fraud Alerts** — automatically generated by the fraud detection scheduler; admin reviews and updates status (dismiss, escalate, resolve)
- Manual **trigger fraud scan** on demand
- **Disputes** — list all user-raised disputes; resolve with a status update and admin note

### Support (Admin)

- **Support Queries** — list all tickets; reply in real-time (Socket.IO); update workflow status (open → in-progress → resolved)
- Export support queries to CSV
- **Contact Messages** — view messages submitted via the contact form; reply by email; update status
- **Contact Info Config** — manage the support email address and categories shown to users

### Feedback & Ratings (Admin)

- View all user-submitted feedback with star ratings
- View all App Store–style app ratings

### Ads & Updates (Admin)

- **App Updates** — create/edit/delete update announcements shown to users in-app
- **Ads** — create/edit/delete/toggle in-app ads with image or video (up to 150 MB); served randomly to users; click/impression events tracked
- Content analytics: impressions, clicks, CTR per ad/update

### Reports (Admin)

- **Platform overview** — totals for users, transactions, wallet volume, subscription revenue over configurable periods
- **Top users** by transaction volume or count
- **Category trends** — which transaction types are growing/declining
- **Per-user report** — deep-dive into a single user's full financial activity

### Budget Overview (Admin)

- Platform-wide budget adoption metrics
- Per-user budget detail and limit overrides
- Subscription breakdown (which plan users are on)

### Smart Insights (Admin)

- Platform-level health scores
- Anomaly detection alerts
- Manage smart tips (create, toggle active, delete)

### System Settings (Admin)

- Security settings (session timeout, max login attempts, rate limits)
- Analytics settings (data retention, report periods)
- Notification settings (admin digest frequency and recipients)
- Data export / maintenance tools (cleanup old data, export platform data)

### User Activity Tracking (Admin)

- Search any user by email or name
- View their full chronological activity log

### Audit Logs (Admin)

- Complete log of every admin action with timestamp, admin name, and affected resource

---

## Background Schedulers

| Scheduler | Trigger | Purpose |
|---|---|---|
| Reminder Scheduler | Daily | Send due-date reminders for upcoming transactions |
| Subscription Scheduler | Daily | Expire lapsed subscriptions, process auto-renewals |
| Scheduled Transaction Scheduler | Minutely/Hourly | Execute pending scheduled Quick Transactions |
| Recurring Template Scheduler | Daily | Create transactions from recurring templates |
| Monthly Leaderboard Reward Scheduler | 1st of month | Distribute coin rewards to top-ranked users |
| Offer Cleanup Scheduler | Daily | Expire and archive past-due offers |
| Fraud Alerting Scheduler | Daily | Scan for suspicious transaction patterns |
| Admin Digest Scheduler | Configurable | Email admin team a daily/weekly activity digest |
| Currency Rate Sync | Every 4 hours | Sync live rates from ECB into the database |

---

## Prerequisites

| Tool | Minimum Version |
|---|---|
| Node.js | 18.x |
| npm | 9.x |
| MongoDB | 6.x (local) or MongoDB Atlas |
| Flutter SDK | 3.x (Dart ≥ 3.0) |
| Android Studio / Xcode | For emulator or physical device |

---

## Backend Setup

```bash
cd backend
npm install
```

Create a `.env` file inside `backend/`:

```env
# Server
PORT=5000
NODE_ENV=development

# MongoDB
MONGODB_URI=mongodb://localhost:27017/lenden

# JWT
JWT_SECRET=your_jwt_secret_here
JWT_REFRESH_SECRET=your_refresh_secret_here
JWT_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=7d

# Email (Nodemailer)
EMAIL_USER=your_email@gmail.com
EMAIL_PASS=your_app_password

# Razorpay
RAZORPAY_KEY_ID=rzp_test_xxxxxxxxxxxx
RAZORPAY_KEY_SECRET=your_razorpay_secret
RAZORPAY_WEBHOOK_SECRET=your_webhook_secret

# Google OAuth
GOOGLE_CLIENT_ID=your_google_client_id.apps.googleusercontent.com

# Default Admin (created on first start)
DEFAULT_ADMIN_EMAIL
DEFAULT_ADMIN_PASSWORD

# App version gate
APP_MIN_VERSION=1.0.0
APP_LATEST_VERSION=1.0.0
APP_UPDATE_URL=
```

Start the server:

```bash
# Development (auto-restart on changes)
npm run dev

# Production
npm start
```

The API is available at `http://localhost:5000/api`.

---

## Frontend Setup

```bash
cd frontend
flutter pub get
```

Set the backend URL in [frontend/lib/api_config.dart](frontend/lib/api_config.dart):

```dart
const String baseUrl = 'http://10.0.2.2:5000'; // Android emulator
// const String baseUrl = 'http://localhost:5000'; // iOS simulator / web
// const String baseUrl = 'https://your-production-backend.com'; // Production
```

Run the app:

```bash
flutter run
```

Build a release APK:

```bash
flutter build apk --release
```

Build for iOS:

```bash
flutter build ipa
```

---

## Key Dependencies

### Backend

| Package | Purpose |
|---|---|
| `express` | HTTP server and routing |
| `mongoose` | MongoDB ODM |
| `socket.io` | Real-time bidirectional events |
| `jsonwebtoken` | JWT access and refresh tokens |
| `bcrypt` | Password hashing |
| `nodemailer` | Transactional email (OTP, receipts) |
| `razorpay` | Payment orders and webhook verification |
| `node-cron` | Scheduled background jobs |
| `pdfkit` | PDF receipt and statement generation |
| `multer` | File upload handling |
| `express-rate-limit` | Rate limiting on auth endpoints |
| `google-auth-library` | Google OAuth token verification |
| `winston` | Structured logging |

### Frontend

| Package | Purpose |
|---|---|
| `provider` | State management |
| `http` | REST API calls |
| `socket_io_client` | Real-time chat and notifications |
| `razorpay_flutter` | In-app payment sheet |
| `flutter_secure_storage` | Secure JWT token storage |
| `google_sign_in` | Google OAuth flow |
| `mobile_scanner` | QR code scanning |
| `qr_flutter` | QR code generation |
| `cryptography` | E2E chat encryption (X25519 + AES-GCM) |
| `fl_chart` | Analytics charts |
| `image_picker` | Profile and group image selection |
| `file_picker` | Document attachment for transactions |
| `pdf` | Client-side PDF generation |
| `path_provider` | File system access |
| `share_plus` | Share/export CSV and PDF files |
| `google_mlkit_text_recognition` | Receipt OCR scanning |
| `intl` | Date/number formatting and localisation |
| `elegant_notification` | In-app toast notifications |
| `emoji_picker_flutter` | Emoji keyboard for chat |
| `video_player` | In-app ad video playback |

---

## API Overview

All endpoints are prefixed with `/api`. Authentication uses a Bearer JWT in the `Authorization` header.

| Group | Example Endpoints |
|---|---|
| Auth | `POST /api/users/register`, `POST /api/users/login`, `POST /api/users/google-login` |
| Profile | `GET /api/users/me`, `PUT /api/users/me` |
| Sessions | `GET /api/users/active-sessions`, `POST /api/users/logout-device` |
| Wallet | `GET /api/wallet/balance`, `POST /api/wallet/pay`, `POST /api/wallet/qr-pay` |
| Withdrawal | `POST /api/wallet/withdraw`, `GET /api/wallet/withdrawals` |
| Quick Tx | `POST /api/quick-transactions`, `PUT /api/quick-transactions/:id/clear` |
| Secure Tx | `POST /api/transactions/create`, `POST /api/transactions/partial-payment` |
| Group Tx | `POST /api/group-transactions`, `POST /api/group-transactions/:id/add-expense` |
| Coins | `GET /api/coins/history`, `POST /api/coins/buy-with-wallet` |
| Gift Cards | `GET /api/gift-cards/unscratched`, `POST /api/gift-cards/:id/scratch` |
| Offers | `GET /api/offers/available`, `POST /api/offers/:id/accept` |
| Leaderboard | `GET /api/leaderboard`, `GET /api/leaderboard/rewards/me` |
| Referral | `GET /api/referral/me`, `POST /api/referral/share` |
| Budget | `GET /api/budget/:year/:month`, `POST /api/budget` |
| Friends | `POST /api/friends/request`, `POST /api/friends/requests/:id/accept` |
| Notifications | `GET /api/notifications`, `POST /api/notifications/mark-as-read` |
| Support | `POST /api/support/queries`, `GET /api/support/queries/me` |
| Disputes | `POST /api/disputes`, `GET /api/disputes/mine` |
| Chat | `GET /api/chat/messages/:transactionId` |
| Subscription | `GET /api/subscription/plans`, `GET /api/subscription/status` |
| Admin — Users | `GET /api/admin/users`, `PATCH /api/admin/users/:id/suspension` |
| Admin — In-App | `GET /api/admin/in-app-transactions?category=quick&minAmount=500` |
| Admin — Payments | `GET /api/admin/withdrawals`, `GET /api/admin/real-payments/topups` |
| Admin — Reports | `GET /api/admin/reports/platform`, `GET /api/admin/reports/top-users` |

---

## Default Admin Account

On first startup, if no admin exists in the database, a default admin is created using `DEFAULT_ADMIN_EMAIL` and `DEFAULT_ADMIN_PASSWORD` from `.env`. Change these credentials immediately after first login.

---

## Environment Notes

- The backend exposes **Socket.IO** on the same port as the HTTP server — no separate WS port is needed.
- Razorpay **webhook** (`POST /api/payment/webhook`) and payout webhook (`POST /api/wallet/payout-webhook`) require no auth header — Razorpay calls them directly. Ensure the webhook secret in `.env` matches the one set in the Razorpay dashboard.
- For local development with an Android emulator, use `10.0.2.2` as the host instead of `localhost`.
- MongoDB URI can point to a local instance or MongoDB Atlas — no code changes required.

---

## Dark Mode

The app ships with full light/dark mode support controlled by a toggle in **Settings → Theme**. The preference is persisted in `flutter_secure_storage` and applied at startup through an `AppThemeNotifier` (Provider). Every screen and widget reads its palette from `AppThemeColors` helpers (`AppThemeColors.cardBg(context)`, `AppThemeColors.primaryText(context)`, etc.) — no hard-coded `Colors.white` or `Colors.black` appear in the UI layer.

---

## Language & Localisation

The app supports multiple languages via Flutter's `flutter_localizations` package and a custom `AppLocalizations` class generated from `.arb` files in `frontend/lib/l10n/`. Language preference is persisted and applied at startup alongside the theme preference. All user-visible strings pass through `AppLocalizations.of(context)` — switching language takes effect instantly without restarting.

---

## Recent Improvements

### UX — OTP / PIN backward navigation (all flows)

`frontend/lib/otp_input.dart` is the single shared widget used across every flow that shows a 6-box code input: OTP login, OTP verification, Set PIN, Change PIN, App Lock set/verify, and wallet-auth steps.

Before this fix the widget had no backward navigation. The previous implementation used `addListener` on controllers and only moved focus *forward* when a box became non-empty. Pressing backspace on an empty box did nothing.

**Fix:**
- Replaced the `addListener` approach with per-box `TextField.onChanged` callbacks (fires with the actual new value, including empty string).
- Added `FocusNode.onKeyEvent` on every focus node to intercept `KeyDownEvent`/`KeyRepeatEvent` with `LogicalKeyboardKey.backspace` when the box is already empty → clears the previous box and moves focus back. Holding backspace sweeps back through all boxes.
- `onTap` selects all text so typing a new digit always replaces the old one cleanly.
- `onChanged` also handles SMS autofill / paste: if the delivered value is more than one digit, the digits are distributed across boxes 0–5 automatically.
- Added `FilteringTextInputFormatter.digitsOnly` to prevent non-numeric input.

Single-file fix — all 14+ OTP/PIN/app-lock flows in the codebase inherit the fix automatically.

---

### Frontend — widget extraction

Large page files were split to separate layout from logic:

| Extracted file | Source | Contents |
|---|---|---|
| `frontend/lib/user/wallet/widgets/payment_sheet.dart` | `lenden_wallet_page.dart` (≈300 lines) | `LendenPaymentHelper` static helper + `PaymentSheet` widget + state |
| `frontend/lib/admin/digitise/widgets/subscription_dialogs.dart` | `manage_subscriptions_tab.dart` (≈620 lines) | `EditSubscriptionDialog` + `GrantSubscriptionDialog` |

Callers were updated to import the new files directly. `lenden_wallet_page.dart` does **not** import `payment_sheet.dart` (one-way dependency prevents a circular import: `payment_sheet.dart` → `lenden_wallet_page.dart`).

---

### Frontend — colour system consolidation

All inline tricolor hex literals were replaced with named constants in `AppColors`:

| Constant | Value | Usage |
|---|---|---|
| `AppColors.tricolorOrange` | `Color(0xFFFF9933)` | Standalone saffron colour |
| `AppColors.tricolorGreen` | `Color(0xFF138808)` | Standalone India-green colour |
| `AppColors.tricolorGradientColors` | `[tricolorOrange, white, tricolorGreen]` | List for gradients with a custom direction |
| `AppColors.tricolorGradient` | `LinearGradient(…, topLeft → bottomRight)` | Canonical gradient; drop-in replacement |

Files updated: `group_transactions`, `group_transaction_page`, `group_members_page`, `login_page`, `profile_page`, `updates_page`, `qr_scanner_page`, `analytics_page`, `secure_transaction_detail_page`, `partial_payment_history_page`, `payment_success_page`, `contact_page`, `app_widgets`.

---

### Backend — route architecture

`backend/src/routes/api.js` is now a pure route-registration file. All middleware factories, controller imports, and Socket.IO logic were moved into their respective domain route files (`auth.routes.js`, `wallet.routes.js`, etc.). `api.js` only mounts domain routers.

---

### Backend — security hardening

**Webhook signature always verified**

`paymentController.js` and `withdrawalController.js` previously had a conditional check:

```js
if (webhookSecret) { /* verify */ }
```

If `RAZORPAY_WEBHOOK_SECRET` was missing from `.env`, verification was silently skipped and any request was accepted. This has been fixed: a missing secret now returns HTTP 500 immediately, and a missing or invalid signature returns HTTP 400. Verification cannot be bypassed.

**Rate limiting on unauthenticated write endpoints**

- `POST /api/admins/register` — now protected by the existing `loginLimiter`.
- `POST /api/contact-message` — now protected by `otpSendLimiter` to prevent spam submissions.

---

### Backend — performance

`AppratingController.getAverageRating` previously loaded every `AppRating` document into JS memory and computed the average with `Array.reduce`. It now uses a single MongoDB `$avg` aggregation:

```js
const [result] = await AppRating.aggregate([
  { $group: { _id: null, average: { $avg: '$rating' }, count: { $sum: 1 } } },
]);
```

This makes the query O(1) in application memory regardless of how many ratings exist.

---

## License

This project is private. All rights reserved.
