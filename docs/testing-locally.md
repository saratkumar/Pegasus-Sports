# Testing locally without touching production

The app can run against the **Firebase Local Emulator Suite**: a private copy of
sign-in, Firestore and Cloud Functions on your PC. Nothing you do in test mode
reaches live data, sends real emails or charges cards. (One exception: coach
photo uploads go to the real "Pegasus Coach Photos" Drive folder, named
"TEST - …", so you can delete them afterwards.)

## One-time setup

- Firebase CLI: `npm install -g firebase-tools`, then `firebase login`
- Java 21 or newer (already installed)
- `functions/.secret.local` (never committed, so create it on each PC):
  dummy values for the function secrets, so the functions emulator never
  fetches the real ones from production:

  ```
  STRIPE_SECRET_KEY=sk_test_dummy_local_emulator_only
  STRIPE_PUBLISHABLE_KEY=pk_test_dummy_local_emulator_only
  APPS_SCRIPT_URL=http://127.0.0.1:9/apps-script-disabled-in-local-test
  ```

  With the dummy APPS_SCRIPT_URL, coach photo upload fails in test mode.
  Put the real URL there only if you need to test that upload.
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
| glofox@test.com | client (imported from Glofox, no invitation) | 3 |

Each email works once per session (the invitation is used up on first sign-in).

Sign-up is **invite-only**, so any other email is refused with
"… isn't registered with PSAS". To let someone new in, sign in as
admin@test.com and add them under Users → Add User first.

## Things worth checking

- **Uninvited email:** sign in with e.g. stranger@gmail.com and you should
  see the "isn't registered" message on the login screen, not the app.
- **Imported Glofox member:** sign in as glofox@test.com. There's no
  invitation, but it's allowed, and within a few seconds the 3 credits and
  phone number from the imported record appear on the new account.
- **Deactivate / reactivate:** as admin@test.com, open Users, pick a test
  user and tap Deactivate. That user is signed out (or refused at their next
  sign-in) with an "inactive" message. Tap Reactivate and they can sign in
  again with their credits and bookings intact. Use a second browser profile
  or an incognito window to be signed in as both at once.
- **Junior package for one child:** as client@test.com, add two children in
  My Family. As admin@test.com, approve both (Requests). Back as the parent,
  buy a Kids plan with coupon **TESTFREE**: you're asked which child it's
  for, and it shows under that child only. Booking that child uses their
  package; booking yourself or the other child never touches it. Cancelling
  puts the credit back on the same child.
- **Child's own login:** in My Family, give a child a login email (e.g.
  kid@test.com). Once the child is approved, an invitation appears in the
  emulator's `mail` collection. Sign in with that email in an incognito
  window: the child sees Classes, Bookings and My Plan only, books
  themselves with their own junior credits, and can't buy anything. The
  parent sees those bookings too. Removing the child in My Family signs
  their login out.

Credits are general credits: they work for any class that isn't restricted to
specific plans.

## What doesn't work in test mode

Cloud Functions run locally, but the parts that would touch live systems are
switched off (see `IS_EMULATOR` in `functions/index.js`). These show an
error in test mode:

- card payments (Stripe)
- the admin Activity Log and Transactions (Google Sheet)

Free-plan redemption and "Send reminder now" work.

Emails are saved to the emulator's `mail` collection (visible in the dashboard)
but never sent.

## Resetting

Stop the emulators (Ctrl+C in terminal 1). All test data is discarded. Start
again and re-run the seed script for a clean copy.

To reset without restarting, wipe the emulator and re-seed:

```
curl -X DELETE "http://127.0.0.1:8080/emulator/v1/projects/fitness-booking-app-23bdc/databases/(default)/documents"
curl -X DELETE "http://127.0.0.1:9099/emulator/v1/projects/fitness-booking-app-23bdc/accounts"
node tool/emulator_seed.js
```

If the emulators won't start with "port taken", an earlier emulator is still
running in the background: `netstat -ano | findstr :8080` shows its process
id, then `taskkill /PID <id> /F`.

## How it's wired

`--dart-define=USE_EMULATOR=true` switches the app to the emulators (see
`lib/utils/emulator.dart`). Without the flag, builds behave exactly as before
and talk to production. Never pass the flag for store or hosting builds.
