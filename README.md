# LenDen

A full-stack personal finance app for tracking money lent and borrowed between friends, groups, and communities.

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (Dart) — iOS, Android |
| Backend | Node.js + Express |
| Database | MongoDB (Mongoose) |
| Auth | JWT |
| Push Notifications | Firebase Cloud Messaging |
| Payments | RazorPay (coin purchases) |

## Features

### Transactions
- **Quick Transactions** — record money lent/borrowed with a counterparty, with optional notes and OTP-secured partial payments
- **Secure Transactions** — multi-step escrow-style flow with OTP verification at each stage
- **Group Transactions** — split expenses across a group (like Splitwise), with per-member balances
- **Recurring Templates** — schedule repeating quick transactions (weekly/monthly)

### Social
- **Friends** — add friends by email; block/unblock users
- **Communities** — umbrella spaces that hold multiple groups; invite-code or direct-add join flow
- **Counterparties** — automatically tracked from transactions; mark close counterparties
- **Activity Feed** — per-user log of all actions

### Discovery & Member Management
- **Source Pickers** — when adding members to groups or communities, pick from Friends, Counterparties, existing Groups, or All Sources combined
- **Favorites** — star transactions, groups, or communities for quick access

### Wallet & Coins
- **LenDen Coins** — virtual coins earned via daily bonus; spent on premium features
- **Wallet** — top-up, pay users, request withdrawals (admin-reviewed)

### Admin
- **Support** — users submit queries; admins reply and update status
- **Ratings** — peer ratings on transactions
- **Coin Ledger** — admin view of all coin movements

### UX
- **Dark Mode** — system/light/dark toggle
- **Hindi / English** — full bilingual support via in-app `AppLocalizations`
- **Description limits** — 300-character limit enforced on all description/note fields (frontend counter + backend validation)

## Project Structure

```
Lenden/
├── backend/
│   ├── src/
│   │   ├── controllers/   # Express route handlers
│   │   ├── models/        # Mongoose schemas
│   │   ├── routes/        # Route definitions grouped by domain
│   │   ├── middleware/    # Auth, rate limiting
│   │   └── utils/         # Shared helpers
│   └── server.js
└── frontend/
    └── lib/
        ├── admin/         # Admin-only pages
        ├── l10n/          # AppLocalizations (en + hi)
        ├── login/         # Auth flow
        ├── user/          # All user-facing pages
        │   ├── community/
        │   ├── connections/
        │   ├── digitise/
        │   ├── favorites/
        │   ├── notifications/
        │   └── transaction/
        │       ├── group_transactions/
        │       ├── quick_transactions/
        │       └── secure_transactions/
        ├── utils/         # Theme helpers, API client
        └── widgets/       # Shared UI components
```

## Setup

### Backend
```bash
cd backend
npm install
cp .env.example .env   # fill in MONGO_URI, JWT_SECRET, etc.
npm run dev
```

### Frontend
```bash
cd frontend
flutter pub get
flutter run
```

## Environment Variables (backend)

| Variable | Purpose |
|---|---|
| `MONGO_URI` | MongoDB connection string |
| `JWT_SECRET` | Token signing key |
| `FCM_SERVER_KEY` | Firebase push notifications |
| `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` | Coin purchase payments |

## Contributing

This is a private project. No public contributions.
