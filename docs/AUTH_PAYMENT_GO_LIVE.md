# WashPro — Phone OTP Auth + Razorpay Go-Live Checklist

Do **not** switch Razorpay to Live Mode or enable paid SMS billing until this checklist is complete.

## 1. Firebase Authentication

1. Firebase Console → **Authentication** → **Sign-in method**
2. Enable **Phone** (required — the Firebase CLI `deploy --only auth` does **not** enable Phone; it only supports email/password, Google, and anonymous)
3. Keep Email/Password and Google enabled (secondary login paths remain in the app)
4. **Phone** → **Phone numbers for testing** → Add:
   - Number: `+91 9059899298`
   - Code: `123456`
5. Confirm this test number is configured **only** in Firebase Console (never hardcode OTP in the app)
6. **Authentication → Settings → SMS region policy** → allow **India (`IN`)**  
   New projects default to an empty allow-list (no regions). That blocks `+91` SMS and often surfaces in the app as Firebase `operation-not-allowed` (misleadingly worded as “Phone not enabled”).

### Android SHA certificates (required for real SMS / Play Integrity)

```bash
# Debug keystore
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android

# Release / Play upload keystore (use your WashPro keystore path)
keytool -list -v -keystore /path/to/washpro-upload.keystore -alias upload
```

Add **SHA-1** and **SHA-256** under Firebase Console → Project settings → Your Android app (`com.washpro.customer`).

### iOS (if shipping iOS)

1. Ensure `GoogleService-Info.plist` matches the Firebase project
2. Enable Push Notifications capability (APNs) for silent/push-assisted verification where used
3. Add the iOS app’s bundle ID in Firebase Console

### Deploy Auth provider config (optional via CLI)

```bash
firebase deploy --only auth --project wash-pro-7f3b1
```

This enables **Email/Password** and **Google** from `firebase.json` only.  
**Phone must stay enabled in the Console** (and SMS region `IN` must remain allowed). Do not put `"phoneNumber": true` in `firebase.json` — the CLI ignores it and it previously caused false confidence that Phone was live.

## 2. Firestore rules & indexes

```bash
firebase deploy --only firestore:rules,firestore:indexes --project wash-pro-7f3b1
```

Customers:

- Own `users/{uid}` only
- Cannot set roles / admin flags
- Cannot create online Razorpay payment rows or set `razorpaySignatureVerified`
- Cash pending payment placeholders remain client-creatable

## 3. Razorpay (TEST MODE)

1. Create / open Razorpay Dashboard → **Test Mode**
2. Copy **Key ID** and **Key Secret**
3. Store secrets in Firebase Secret Manager (never in Flutter / git):

```bash
firebase functions:secrets:set RAZORPAY_KEY_ID --project wash-pro-7f3b1
firebase functions:secrets:set RAZORPAY_KEY_SECRET --project wash-pro-7f3b1
firebase functions:secrets:set RAZORPAY_WEBHOOK_SECRET --project wash-pro-7f3b1
```

4. Blaze plan is required for outbound HTTPS from Cloud Functions to Razorpay

## 4. Deploy Cloud Functions

```bash
cd functions && npm ci && npm test && npm run build && cd ..
firebase deploy --only functions --project wash-pro-7f3b1
```

Functions:

| Function | Purpose |
|---|---|
| `createPaymentOrder` | Auth + ownership + trusted amount → Razorpay order |
| `verifyPayment` | HMAC verify + Razorpay status + confirm booking |
| `handlePaymentFailure` | Record failed/cancelled checkout |
| `getPaymentStatus` | Customer payment status poll |
| `handlePaymentWebhook` | Signed webhook + idempotency |
| `recordCashCollection` | Worker/admin cash collection |
| `requestRefund` | Finance refund |
| `reconcilePayments` | Finance unresolved list |

## 5. Razorpay webhook

1. Razorpay Dashboard → **Settings** → **Webhooks** (Test Mode)
2. URL (after deploy):

```text
https://<region>-wash-pro-7f3b1.cloudfunctions.net/handlePaymentWebhook
```

3. Secret: same value as `RAZORPAY_WEBHOOK_SECRET`
4. Events:
   - `payment.authorized`
   - `payment.captured`
   - `payment.failed`
   - `refund.processed`

## 6. Physical Android OTP test

1. Install a debug/release APK with SHA keys registered
2. Open app → enter `9059899298` → **Send OTP**
3. Enter Firebase test OTP `123456` (no real SMS for test numbers)
4. Confirm new users land on onboarding; returning users with a saved name go Home
5. Log out → relaunch → session restores
6. Wrong OTP / resend countdown / offline messaging behave correctly

## 7. Razorpay test payment

Use Razorpay test cards / UPI as documented by Razorpay.

Verify:

1. Booking stays `awaiting_payment` until `verifyPayment` / webhook succeeds
2. Failed / cancelled checkout does **not** confirm booking
3. Retry payment reuses or recreates order safely
4. Cash booking path never opens Razorpay
5. Admin/finance refunds use `requestRefund` (not direct Firestore status edits)

## 8. Production migration (later)

1. Create Live Razorpay keys + webhook secret
2. Set secrets on the `prod` Firebase project (`washpro-prod`)
3. Deploy functions/rules to prod
4. Remove or rotate test phone numbers before public launch if desired
5. Enable real SMS (Firebase billing) only after SHA keys + Phone provider are verified
6. Do **not** commit secrets; rotate any key that was ever pasted into chat/logs

## What was intentionally not claimed as tested here

- Real SMS delivery to non-test numbers
- Live Razorpay capture on a production merchant
- Webhook delivery from Razorpay’s cloud to a deployed function URL
- Blaze upgrade / Secret Manager values already present in the project
