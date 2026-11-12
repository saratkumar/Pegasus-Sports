# Testing locally without touching production

The app can run against the **Firebase Local Emulator Suite**: a private copy of
sign-in, Firestore and Cloud Functions on your PC. Nothing you do in test mode
reaches live data, sends real emails or charges cards. (One exception: coach
photo uploads go to the real "Pegasus Coach Photos" Drive folder, named
"TEST - …", so you can delete them afterwards.)

## One-time setup

- Firebase CLI: `npm install -g firebase-tools`, then `firebase login`
- Java 21 or newer (already installed)
- `functions/.secret.local` (already created, never committed): local copies
  of the function secrets. The Stripe values in it are dummies on purpose.
- `npm install` inside `functions/` (already done)

## Each test session

Open two terminals in the project folder.

**Terminal 1: start the emulators** (leave it running)

```
firebase emulators:start --only auth,firestore,functions --project fitness-booking-app-23bdc
```

Wait for "All emulators ready". The emulator dashboard is at http://localhost:4000.

**Terminal 2: copy test data in, then run the app in test mode**

```
node tool/emulator_seed.js
flutter run -d web-server --web-port=5000 -t lib/main_shop_web.dart --dart-define=USE_EMULATOR=true
```

Open http://localhost:5000. Use `-t lib/main.dart` for the mobile app's screens or
`-t lib/main_admin_web.dart` for the admin panel.

The seed script only **reads** production (classes, class types, facilities,
plans, and coach names/photos/descriptions). It writes to the emulator only.

## Signing in

Sign in with Google as usual. The emulator shows its own test pop-up instead
of Google's. Choose **Add new account** and enter one of these emails:

| Email | Role | Credits |
|---|---|---|
| client@test.com | client | 4 |
| client2@test.com | client | 1 |
| trainer@test.com | trainer | 0 |
| admin@test.com | admin | 0 |

Each email works once per session (the invitation is used up on first sign-in).
Any other email signs in as a plain client with 0 credits.

Credits are general credits: they work for any class that isn't restricted to
specific plans.

## What doesn't work in test mode

Cloud Functions run locally, but the parts that would touch live systems are
switched off (see `IS_EMULATOR` in `functions/index.js`). These show an
error in test mode:

- card payments (Stripe)
- the admin Activity Log and Transactions (Google Sheet)

Free-plan redemption, "Send reminder now" and coach photo upload work.

Emails are saved to the emulator's `mail` collection (visible in the dashboard)
but never sent.

## Resetting

Stop the emulators (Ctrl+C in terminal 1). All test data is discarded. Start
again and re-run the seed script for a clean copy.

## How it's wired

`--dart-define=USE_EMULATOR=true` switches the app to the emulators (see
`lib/utils/emulator.dart`). Without the flag, builds behave exactly as before
and talk to production. Never pass the flag for store or hosting builds.
