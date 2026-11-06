# Release features — setup & go-live guide (Oct 22, 2026)

What was implemented in code, what only you can switch on, and in what order.

## 1. Forgot password ✅ live in code
Login screen → **Forgot password?** → Firebase sends a reset-link email.
No console setup needed (uses the Email/Password provider already enabled).
Tip: customize the email template in Firebase Console → Authentication → Templates.

## 2. Push notifications (FCM) ✅ code ready, needs Functions deploy
- App requests permission (Android 13+), saves the device token to `users/{uid}.fcmToken`.
- Foreground pushes show an in-app banner; tapping any push opens the booking.
- Server side: the new `onNotificationCreated` Cloud Function sends an FCM push for
  **every** `notifications/{id}` doc — including worker-assignment notifications the
  Admin dashboard writes directly.
- **To activate:** Blaze upgrade → `firebase deploy --only functions --project wash-pro-7f3b1`.
- Worker PWA (web) push is NOT included: web push needs a VAPID key + service-worker
  wiring. Workers still get live job updates in-app. Add later if needed.

## 3. Razorpay online payments ✅ code ready, keys pending (your step)
Flow: Book → `createPaymentOrder` (server creates the Razorpay order) → Razorpay
checkout opens → `verifyPayment` verifies the signature **on the server** → booking
confirmed + marked paid. The app can never mark a booking paid by itself.
Fallback stays honest: if checkout can't run, the user gets Retry / Pay cash / Pay later,
and "Pay now (Razorpay)" also appears on awaiting-payment booking details.

**Your steps when ready:**
1. Create a Razorpay account, finish KYC, get **Key Id + Key Secret** (test mode first).
2. Firebase → upgrade project `wash-pro-7f3b1` to **Blaze**.
3. Set secrets (never put the secret in the app):
   ```bash
   npx -y firebase-tools@latest functions:secrets:set RAZORPAY_KEY_ID --project wash-pro-7f3b1
   npx -y firebase-tools@latest functions:secrets:set RAZORPAY_KEY_SECRET --project wash-pro-7f3b1
   npx -y firebase-tools@latest functions:secrets:set RAZORPAY_WEBHOOK_SECRET --project wash-pro-7f3b1
   ```
4. Deploy: `npx -y firebase-tools@latest deploy --only functions --project wash-pro-7f3b1`
5. In Razorpay Dashboard → Webhooks, add:
   `https://us-central1-wash-pro-7f3b1.cloudfunctions.net/handlePaymentWebhook`
   with the same webhook secret, events: payment.captured, payment.failed, refund.created.
6. Test with Razorpay test UPI/card, then switch secrets to live keys.

## 4. Search, filters, sorting ✅ live in code (where needed)
- Booking flow: service search box + sort (Recommended / Price low→high / high→low).
- Bookings: existing Upcoming / In progress / Completed filters (kept).
- Plans: sort by Best saving / Price / Most visits.
Not added where not needed (vehicles/addresses are short personal lists).

## 5. Offline / poor-network ✅ live in code
- Global red **"You are offline"** banner on every screen.
- Firestore offline cache explicitly enabled; reads show saved data, writes queue
  and sync on reconnect. Real write errors now toast instead of failing silently.

## 6. Crashlytics ✅ live in code
Flutter + async errors report to Firebase Crashlytics automatically.
Verify: Firebase Console → Crashlytics after installing the new APK and using the app
(first report can take a few minutes). For release stack-trace deobfuscation, keep the
build's symbols/mapping files from `build/app/outputs/`.

## 7. Dark mode, deep links, pagination ✅ live in code
- **Dark mode:** Profile → Appearance → System / Light / Dark (saved on device).
- **Deep links:** `washpro://booking/<bookingId>`, `washpro://notifications`,
  `https://wash-pro-customer.web.app/booking/<bookingId>`.
  Test: `adb shell am start -a android.intent.action.VIEW -d "washpro://notifications" com.washpro.customer`
  For verified https links later, publish `/.well-known/assetlinks.json` with the
  Play App Signing SHA-256.
- **Pagination:** Bookings and Notifications lazy-load with "Load more".

## 8. Before/after photos — REMOVED ✅
Worker app no longer asks for before/after photos; job completion requires only the
service checklist, then customer verification. Removed from worker UI, customer
booking detail, admin detail, shared types, seed data, and Firestore rule whitelists.
(Old booking docs may still carry the fields — they're ignored everywhere.)

## 9. Device testing — your 20-minute checklist (real phone)
1. Install `WashPro-Customer.apk`, open with mobile data ON.
2. Register a new account → basic-details onboarding appears → complete it.
3. Sign out → **Forgot password?** → reset via email → sign in with new password.
4. Add vehicle + address → book a wash → pay CASH → confirm booking appears.
5. In Admin, assign a worker → customer phone: in-app notification + (after
   Functions deploy) push arrives; tap it → booking opens.
6. Worker completes checklist → customer verifies + rates → completed.
7. Book online payment → (after Razorpay keys) checkout opens; test-mode pay.
8. Turn on airplane mode → red offline banner; create a booking; turn data back
   on → booking syncs.
9. Profile → Appearance → Dark → reopen app → theme persists.
10. Kill and reopen the app → session restored, no login prompt.

## 10. Settings screen ✅ (v1.2.0)
Profile → **Settings**: name/email, change password (re-authenticated; Google
accounts are told to manage it via Google), push-notification toggle (actually
unregisters the FCM token), Appearance, Privacy/Terms links, version, log out,
delete account.

## 11. Error states ✅ (v1.2.0)
Bookings, Notifications, Vehicles, Addresses and Plans now show a red
"Could not load… Retry" banner when a live load fails (repository stream errors
feed `AppState.loadError`), instead of silently showing stale/empty lists.
Empty states already existed on those screens and remain.

## 12. Automatic account deletion ✅ code ready (v1.2.0)
Settings → Delete account → `deleteMyAccount` Cloud Function erases profile,
vehicles, addresses, subscriptions, notifications, tickets; anonymises
bookings/payments (tax law); deletes the Auth user. Activates with the same
Functions deploy as payments/push. Until then the app honestly falls back to
recording a deletion request. Web deletion page for Play Console:
`https://wash-pro-customer.web.app/delete-account.html` (ships with the next
customer hosting deploy; source: apps/customer-mobile/web/delete-account.html).

## 13. Separate production Firebase project ✅ created (Oct 22, 2026)
- Project: **washpro-prod** (number 848454299025). Auth (Email + Google)
  deployed, Firestore rules/indexes deployed, Android app
  `com.washpro.customer` + Customer Web app registered.
- App switch: default build = pilot `wash-pro-7f3b1`;
  `flutter build apk --dart-define=ENV=prod` = production
  (`lib/firebase_options_prod.dart`). For a prod Android build also copy
  `android/app/google-services.prod.json` over `google-services.json` first.
- **Before prod go-live you still need:** seed the catalog on prod (open the
  prod build once → it reads empty `services/plans`; copy the pilot catalog or
  run the admin seed against prod), register the release SHA-1/SHA-256 on the
  prod Android app for Google sign-in, create an admin user + `admins` doc on
  prod, Blaze + Razorpay secrets on prod, and point admin/worker web apps at
  prod when you cut over. Pilot stays untouched for testing.

## 14. Keystore backup ✅ made (Oct 22, 2026)
Backed up to `~/WashPro-Backups/` (checksums + restore steps in
docs/KEYSTORE_BACKUP.md). **Your remaining step:** copy that folder to Google
Drive + a USB stick — off this laptop.

## Still outstanding (unchanged from the gap audit)
Play Console account/screenshots/data-safety/content-rating/internal testing,
git remote backup, prod cut-over steps in §13.
