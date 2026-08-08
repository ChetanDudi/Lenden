# Lenden Backend

Node.js + Express + MongoDB backend for the Lenden app — a personal finance platform for tracking lending, borrowing, group expenses, and quick transactions.

---

## Setup

### 1. Install dependencies
```bash
npm install
```

### 2. Create `.env` file
Copy the template below into `backend/.env` and fill in your values:

```env
# ── Database ────────────────────────────────────────────────────────────────
MONGODB_URI=mongodb+srv://<user>:<pass>@cluster.mongodb.net/lenden

# ── Auth ────────────────────────────────────────────────────────────────────
JWT_SECRET=<strong-random-64-char-string>   # REQUIRED — never leave this unset in production

# ── Razorpay ────────────────────────────────────────────────────────────────
RAZORPAY_KEY_ID=rzp_live_...
RAZORPAY_KEY_SECRET=...
RAZORPAY_WEBHOOK_SECRET=...
RAZORPAY_PAYMENT_LINK=https://rzp.io/...
RAZORPAY_ACCOUNT_NUMBER=...                 # for payouts (withdrawal feature)

# ── Firebase (FCM push notifications) ───────────────────────────────────────
# Either set the JSON directly or point to a file:
FIREBASE_SERVICE_ACCOUNT={"type":"service_account",...}
# or:
FIREBASE_SERVICE_ACCOUNT_PATH=./firebase-service-account.json

# ── Email ────────────────────────────────────────────────────────────────────
EMAIL_HOST=smtp.example.com
EMAIL_PORT=587
EMAIL_USER=no-reply@lenden.app
EMAIL_PASS=...

# ── Google OAuth ─────────────────────────────────────────────────────────────
GOOGLE_WEB_CLIENT_ID=...

# ── App ──────────────────────────────────────────────────────────────────────
PORT=5000
NODE_ENV=production
APP_BASE_URL=https://your-backend.onrender.com
```

### 3. Start the server
```bash
npm run dev    # development (nodemon)
npm start      # production
```

---

## Folder Structure

```
src/
├── app.js                        # Express entry point, middleware, DB connection, crons
├── routes/
│   └── api.js                    # All API routes with auth middleware wired in
├── controllers/                  # Route handlers (one file per domain)
│   ├── userController.js         # Register, login (email/OTP/Google), profile
│   ├── transactionController.js  # Secure P2P lending/borrowing
│   ├── quickTransactionController.js
│   ├── groupTransactionController.js
│   ├── personalBudgetController.js
│   ├── personalBudgetExpenseController.js
│   ├── analyticController.js     # Analytics + quick insights (server-computed)
│   ├── referralController.js     # Referral info, share logging
│   ├── paymentController.js      # Razorpay add-money, webhook
│   ├── withdrawalController.js   # Wallet withdrawal requests
│   ├── friendController.js
│   ├── chatController.js         # Socket.io real-time chat
│   ├── notificationController.js
│   └── adminController.js
├── models/                       # Mongoose schemas
│   ├── user.js
│   ├── transaction.js
│   ├── quickTransaction.js
│   ├── groupTransaction.js
│   ├── personalBudget.js         # includes allocations[] sub-array
│   ├── personalBudgetExpense.js  # includes allocationName field
│   ├── notification.js
│   ├── coinLedger.js
│   ├── referralConfig.js
│   ├── refreshToken.js
│   └── ...
├── repositories/                 # DB-abstraction layer (repository pattern)
│   ├── BaseRepository.js         # Generic CRUD wrapper around Mongoose
│   ├── UserRepository.js
│   ├── TransactionRepository.js
│   └── QuickTransactionRepository.js
├── middleware/
│   ├── auth.js                   # JWT verification, account status checks
│   ├── rateLimit.js              # Per-endpoint + global API rate limiters
│   ├── walletAuth.js
│   ├── sessionTimeout.js
│   └── budgetCheck.js
├── services/
│   └── notificationService.js    # FCM push via Firebase Admin SDK
├── utils/
│   ├── referralService.js        # Referral code generation + reward distribution
│   ├── coinLedgerService.js
│   ├── tokenService.js           # Access + refresh token management
│   ├── reminderScheduler.js      # Cron: payment reminders + birthday notifications
│   ├── fraudAlertingScheduler.js
│   ├── subscriptionScheduler.js
│   ├── recurringTemplateScheduler.js
│   ├── scheduledTransactionScheduler.js
│   ├── monthlyLeaderboardRewardScheduler.js
│   └── offerCleanupScheduler.js
└── migrations/                   # One-time data migrations
```

---

## Key Systems

### Authentication
- Email + password registration with email OTP verification
- Email OTP login (passwordless)
- Google Sign-In (ID token verified server-side)
- JWT access tokens (short-lived) + refresh tokens (long-lived, device-scoped, revocable)
- Account suspension, deactivation, and `forceLogoutAfter` for password changes
- Session timeout middleware

### Referral System
Users get a unique referral code (`LD` + 8 chars). Flow:

```
User A shares code → User B registers with it
→ B.referredByUser = A._id stored on registration
→ B creates their first transaction (any type)
→ processReferralRewardOnFirstCreation() fires once:
    A gets +20 LenDen coins (inviter reward)
    B gets +10 LenDen coins (referee reward)
→ Both entries written to CoinLedger
→ B.referralRewardGranted = true (prevents double payout)
```

Reward amounts are admin-configurable via `PUT /admin/referral-config`.

### Personal Budget — Allocations
Budgets now support optional sub-category allocations:
- `PersonalBudget.allocations: [{ name, limit }]` — planned spending items
- `PersonalBudgetExpense.allocationName` — optional tag linking an expense to an allocation
- `GET /personal-budget/:id/expenses` returns each allocation with its `spent` amount computed server-side
- Validation: total of all allocation limits must not exceed the main budget limit

### Analytics (server-computed)
`GET /api/analytics/quick` now returns server-computed fields, eliminating client-side iteration:
- `lentCount`, `borrowedCount`
- `biggestPendingAmountInr`
- `thisMonthNetFlowInr`
- `averageAmountInr`
- `mostFrequentCounterparty` (name looked up from User collection)

### Birthday Notifications (Cron)
Runs daily at **8am**. For every user whose `birthday` month+day matches today:
1. Finds their friends (via `User.friends`) and counterparties (via `QuickTransaction.users`)
2. Sends each recipient an in-app `Notification` document + FCM push
3. Respects per-user quiet hours setting
4. Notification metadata includes `type: 'birthday'` and `birthdayUserId` for deep-linking

### Repository Pattern (DB Abstraction)
All controllers should eventually import from `repositories/` instead of `models/` directly. To switch databases in future:
1. Only change files under `src/repositories/`
2. `BaseRepository` wraps every Mongoose call — replace its internals with your new DB driver
3. Controllers are already DB-agnostic when using repositories

Current repositories: `UserRepository`, `TransactionRepository`, `QuickTransactionRepository`.

---

## MongoDB Indexes

Compound indexes added for production query performance:

| Collection | Index |
|---|---|
| `transactions` | `{ userEmail: 1, date: -1 }` |
| `transactions` | `{ userEmail: 1, userCleared: 1 }` |
| `transactions` | `{ counterpartyEmail: 1, date: -1 }` |
| `quicktransactions` | `{ users: 1, date: -1 }` |
| `quicktransactions` | `{ users: 1, category: 1 }` |
| `withdrawalrequests` | `{ user: 1, createdAt: -1 }` |
| `withdrawalrequests` | `{ status: 1, createdAt: -1 }` |
| `scanpaymentrequests` | `{ user: 1, createdAt: -1 }` |
| `scanpaymentrequests` | `{ status: 1, createdAt: -1 }` |
| `razorpaycapturedpayments` | `{ claimed: 1, capturedAt: -1 }` |
| `razorpaycapturedpayments` | `{ claimedBy: 1 }` |
| `personalbudgets` | `{ user: 1, startDate: -1 }` |
| `personalbudgets` | `{ user: 1, status: 1 }` |
| `personalbudgetexpenses` | `{ budget: 1, date: -1 }` |
| `personalbudgetexpenses` | `{ user: 1, budget: 1 }` |
| `refreshtokens` | `{ userId: 1, deviceId: 1 }` |
| `refreshtokens` | `{ token: 1, isRevoked: 1 }` |

---

## Security

| Layer | Implementation |
|---|---|
| Security headers | `helmet` (X-Frame-Options, HSTS, X-Content-Type-Options, etc.) |
| NoSQL injection | `express-mongo-sanitize` strips `$` and `.` from all request bodies |
| Global rate limit | 300 requests / 15 min / IP on all `/api` routes |
| Auth rate limits | Login: 10/15min · OTP send: 5/10min · OTP verify: 10/10min |
| Password reset | 10 attempts / 15 min |
| JWT | Verified on every request; checks account status, suspension, forceLogoutAfter |
| Razorpay webhook | HMAC-SHA256 signature verified before processing |
| Passwords | bcrypt hashed |
| File uploads | 10MB limit, filenames sanitized |
| CORS | Whitelist of known origins; mobile app requests (no Origin header) allowed |
| Request body size | Limited to 2MB via `express.json({ limit: '2mb' })` |

**Required in production:**
- `JWT_SECRET` must be set — server refuses to start admin login without it
- MongoDB Atlas IP allowlist — restrict to your backend host's outbound IPs only

---

## API Overview

All routes are under `/api`. Protected routes require `Authorization: Bearer <token>`.

| Group | Prefix | Notes |
|---|---|---|
| Auth | `/users/` | register, login, OTP, Google, refresh-token, logout |
| Profile | `/profile/` | view, edit, avatar, privacy |
| Transactions | `/transactions/` | secure P2P lending/borrowing |
| Quick Transactions | `/quick-transactions/` | fast informal tracking |
| Group Transactions | `/group-transactions/` | split expenses in groups |
| Personal Budget | `/personal-budget/` | budgets, expenses, predictions, history |
| Analytics | `/analytics/` | user, group, quick analytics |
| Friends | `/friends/` | add, remove, search |
| Wallet | `/wallet/` | balance, add money, withdraw |
| Referral | `/referral/` | my code, share log |
| Notifications | `/notifications/` | list, mark read, FCM token |
| Chat | `/chat/` + Socket.io | real-time messaging |
| Admin | `/admin/` | user management, config, analytics |

---

## Scheduled Jobs

| Job | Schedule | Description |
|---|---|---|
| Payment reminders | `0 0 * * *` (midnight) | Notifies users of upcoming/overdue transaction due dates |
| Birthday notifications | `0 8 * * *` (8am) | Notifies friends/counterparties of user birthdays |
| Currency sync | `0 */4 * * *` (every 4h) | Syncs ECB exchange rates |
| Subscription check | Configurable | Marks expired subscriptions |
| Monthly leaderboard rewards | Monthly | Awards coins to top users |
| Recurring transactions | Daily | Creates transactions from recurring templates |
| Scheduled transactions | Daily | Executes future-dated transactions |
| Offer cleanup | Daily | Removes expired coin offers |
| Fraud alerts | Daily | Flags suspicious transaction patterns |
| Admin digest | Daily | Sends summary email to super-admin |

---

## Deployment (Render)

1. Set all environment variables in Render dashboard → Environment
2. Build command: *(none needed — Node.js)*
3. Start command: `npm start`
4. Ensure MongoDB Atlas network access allows Render's outbound IPs (or `0.0.0.0/0` during setup)
5. After first deploy run `npm install` locally and commit any new `package-lock.json` changes

> **Upgrade from free tier before going live.** Render free tier spins down after 15 minutes of inactivity, causing 30-60s cold starts for real users. Render Starter (~$7/mo) keeps the server always-on.
