# Lenden Frontend

Flutter app for Lenden — a personal finance platform for tracking lending, borrowing, group expenses, and quick transactions.

---

## Setup

### 1. Install Flutter
Follow the [official installation guide](https://docs.flutter.dev/get-started/install). Requires Flutter 3.x and Dart 3.x.

### 2. Get dependencies
```bash
flutter pub get
```

### 3. Configure API endpoint
Edit [lib/utils/api_config.dart](lib/utils/api_config.dart) and set `baseUrl` to your backend URL:
```dart
static const String baseUrl = 'https://your-backend.onrender.com';
```

### 4. Firebase setup
- Add `google-services.json` to `android/app/`
- Add `GoogleService-Info.plist` to `ios/Runner/`
- These files are not committed — get them from the Firebase Console for your project

### 5. Run the app
```bash
flutter run                    # debug on connected device
flutter run --release          # release mode
```

---

## Build for Release (Play Store)

### Generate a keystore (one-time)
```bash
keytool -genkey -v \
  -keystore android/lenden.jks \
  -alias lenden \
  -keyalg RSA -keysize 2048 \
  -validity 10000
```

### Sign the build
In `android/app/build.gradle` under `android { signingConfigs { release { ... } } }`, set the keystore path, alias, and passwords (use environment variables or `key.properties`, never commit credentials).

### Build
```bash
flutter build appbundle         # produces .aab for Play Store
flutter build apk --release    # produces .apk for direct install
```

---

## Folder Structure

```
lib/
├── main.dart                         # App entry point, theme, routing
├── session.dart                      # SessionProvider (auth state, feature flags)
├── l10n/                             # Localisation strings
│   └── app_localizations.dart
├── utils/
│   ├── api_client.dart               # HTTP client (attaches JWT, handles 401)
│   ├── api_config.dart               # Base URL configuration
│   ├── theme_helper.dart             # AppThemeColors, dark/light helpers
│   ├── responsive.dart               # context.sp() font scaling
│   ├── currency_helpers.dart         # currencySymbol(), convertCurrency()
│   └── pickers.dart                  # Date/time picker helpers
├── widgets/
│   ├── app_colors.dart               # AppColors (cyan, etc.), AppThemeColors
│   ├── app_widgets.dart              # showSnack(), errorStateWidget(), tricolorBorder()
│   ├── tricolor_border_text_field.dart  # Tricolor gradient border widget (used for Google button)
│   ├── premium_gate.dart             # Paywall gate widget
│   └── currency_display.dart
├── login/
│   └── login_page.dart               # Email+password, OTP, Google Sign-In login
├── register/
│   └── register_page.dart            # Registration with optional referral code field
└── user/
    ├── home_page.dart
    ├── transaction/
    │   ├── analytics_page.dart       # Transaction analytics (server-computed quick insights)
    │   └── ...
    ├── budget/
    │   ├── budget_planning_page.dart # Main budget hub with tab navigation
    │   ├── personal_budget_expenses_page.dart  # Expense list + add/edit sheet
    │   └── tabs/
    │       ├── personal_budget_tab.dart  # Active budgets + create/edit modal with allocations
    │       └── ...
    └── digitise/
        └── referral_page.dart        # Invite page with share options
```

---

## Features

### Authentication
- Email + password login
- Passwordless OTP login (email)
- Google Sign-In
- Auto token refresh (transparent to user)
- Force-logout on password change / account suspension

### Home & Navigation
- Bottom navigation with badges for unread notifications
- Feature-flag gating via `SessionProvider.hasFeature()`

### Login & Register — Input Styling
All input fields on the login and register pages use the **profile-page card style** (`_profileStyleField`):
- Card container with `AppThemeColors.cardBg` background
- 34×34 icon box with `AppColors.cyan` tint
- Plain border — no tricolor gradient on inputs
- The tricolor gradient border is reserved for the Google Sign-In button only

### Register Page — Referral Code
An optional **"Referral Code"** field appears at the bottom of the registration form.
- Auto-uppercased as the user types
- Sent in the registration POST body only if non-empty
- Backend validates the code and links the new user to the referrer

### Referral Page
- **Copy button** copies the full invite message (code + app link + text) — not just the URL
- Sharing via WhatsApp, Telegram, SMS, email, etc. uses the same full message
- Each share action is logged to the backend (`POST /referral/share`)

### Personal Budget

#### Budget Creation / Editing — Allocations
When creating or editing a budget, users can optionally add **planned allocation items**:
- Each allocation has a name (e.g. "Food", "Transport") and a limit
- Total of all allocations must be ≤ the main budget limit
- A live running total is shown as allocations are added/changed
- Allocations are displayed in the budget card's expanded section

#### Expense Add/Edit Sheet
- **Cancel button** added alongside the Save button at the bottom of the sheet
- When the budget has allocations, an **allocation picker** appears above the date field:
  - Chip-style selector (None + each allocation name)
  - Selected allocation is saved as `allocationName` on the expense
- Cancel dismisses the sheet without saving; both buttons disable during the save request

#### Budget Card
- Expanded view shows the planned allocations list with individual limits

### Analytics Page — Quick Insights
The quick analytics section no longer iterates raw transactions on the device. The backend now computes and returns:
- Biggest pending amount (INR)
- Net flow this month (INR)
- Average transaction amount (INR)
- Most frequent counterparty (name)
- Lent count / Borrowed count

### Birthday Notifications (In-App + FCM)
When a friend or counterparty has a birthday, the backend sends:
- An in-app notification (visible in the notifications tab)
- A device push notification via FCM
- Notification includes the birthday person's name and a deep-link payload (`type: 'birthday'`)

---

## UI Conventions

| Element | Convention |
|---|---|
| Colors | `AppColors.cyan` for primary actions; `AppThemeColors.*` for theme-aware colors |
| Text sizing | `context.sp(n)` for responsive font sizes |
| Cards | `AppThemeColors.cardBg`, `AppThemeColors.border`, `BorderRadius.circular(14-18)` |
| Loading | `CircularProgressIndicator(color: AppColors.cyan)` |
| Errors | `showSnack(context, message, isError: true)` |
| Success | `showSnack(context, message)` |
| Tricolor border | `tricolorBorder(radius, child)` — used on premium/featured widgets only |
| Input fields | Profile-page card style via `_profileStyleField` helper in auth pages |

---

## State Management

- **Provider** — `SessionProvider` holds auth token, user info, subscription features
- **StatefulWidget + setState** — local UI state (forms, pagination, filters)
- **StatefulBuilder** — local state inside modal bottom sheets without a full widget

---

## Localization

Strings are accessed via:
```dart
final t = AppLocalizations.of(context).t;
Text(t('some_key'))
```

Add new strings in [lib/l10n/app_localizations.dart](lib/l10n/app_localizations.dart).

---

## API Client

[lib/utils/api_client.dart](lib/utils/api_client.dart) wraps all HTTP calls:
- Automatically attaches `Authorization: Bearer <token>`
- Handles 401 → clears session, redirects to login
- Methods: `ApiClient.get(path)`, `.post(path, body: {})`, `.put(...)`, `.delete(...)`
