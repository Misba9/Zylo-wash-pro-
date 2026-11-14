# Zylo — Razorpay UPI Checkout

## Root cause (Cards-only on Android)

Checkout opened, but **only Cards** appeared. This was **not** fixed by Dashboard “UPI = ACTIVATED” alone.

| Factor | Role |
|--------|------|
| **Primary (app bug)** | `checkoutOptions` forced `upi.flows: ['intent','collect','qr']` with `show_default_blocks: false`. In **Test Mode**, Intent/QR are unavailable; Checkout then **dropped the entire UPI instrument**, leaving only Cards in the custom block. |
| Secondary | Android 11+ needs Manifest `<queries>` for UPI Intent apps (already present). Missing queries hide Intent apps; they should not remove Collect/VPA when Collect is offered. |
| Account / mode | **Test Mode** → UPI Collect (enter VPA). **Live Mode** → UPI Intent + QR. Installing UPI apps does **not** enable QR in Test Mode. |
| Keys | Server returns `keyId` from Firebase secrets (`RAZORPAY_KEY_ID`). Must be `rzp_test_…` for Test Checkout. Redeploy functions after rotating secrets. |

Backend `createPaymentOrder` (amount in paise, `currency: INR`, order id) and `verifyPayment` (HMAC signature) were **not** the cause of missing UPI.

## Fix applied

| Area | Change |
|------|--------|
| `lib/services/app_services.dart` | UPI instrument is plain `{ method: 'upi' }` — **no** `flows` array. Safe diagnostic logs (mode, order prefix, amount, methods; never secrets/signatures). |
| `AndroidManifest.xml` | Kept Razorpay UPI `<queries>` (GPay, PhonePe, Paytm, BHIM, `upi://`, …). |
| `ios/Runner/Info.plist` | Kept `LSApplicationQueriesSchemes` for UPI. |
| Unit tests | Assert `flows` is **absent** on the UPI instrument. |

Payments still confirmed **only** after server `verifyPayment`. Cash-after-service unchanged. Three-step booking unchanged.

## What each UPI method needs

| Flow | Test Mode (`rzp_test_`) | Live Mode (`rzp_live_`) |
|------|-------------------------|-------------------------|
| **UPI Collect / UPI ID** | Yes — enter `success@razorpay` / `failure@razorpay` | Subject to NPCI Collect sunset (28 Feb 2026); migrate to Intent/QR |
| **UPI Intent** (GPay / PhonePe / …) | Not a real money flow; Razorpay: validate in **Live** | Needs activated UPI + installed apps + `<queries>` |
| **UPI QR** | Not available for real QR testing in Test | Live Checkout where supported; works without apps |

Do **not** claim Intent/QR verified until tested on a physical device with Live keys (or Razorpay’s documented Live UPI checks).

## Razorpay Dashboard checklist

1. **Test Mode** toggle ON while developing; API keys must match (`rzp_test_…` in `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET`).
2. **Payment Methods → UPI → Activated**.
3. Do not disable UPI Collect in Test until you have verified Live Intent/QR (Collect still needed for Test VPA).
4. After secret rotation: redeploy payment functions so Checkout receives the new `keyId`.
   **Done (2026-11-14):** `createPaymentOrder`, `verifyPayment`, `handlePaymentWebhook`, `requestRefund`, `handlePaymentFailure`, `getPaymentStatus` redeployed on `wash-pro-7f3b1` with Test key secret **v4**.
5. For production UPI Intent/QR: switch to Live keys, complete Razorpay activation/KYC, then retest on device **with and without** UPI apps (QR/Collect should still appear when offered).

## Device QA (manual)

```bash
cd apps/customer-mobile
flutter clean && flutter pub get
flutter run   # physical Android preferred
```

1. Book online → open Checkout → confirm **UPI** and **Cards** both visible.
2. **No UPI apps**: UPI ID / Collect (and QR in Live if shown) still available — not Cards-only.
3. **With UPI apps** (Live): Intent app list appears.
4. Test VPA `success@razorpay` → client success → `verifyPayment` → booking paid.
5. Cancel / fail → booking stays unpaid; retry allowed. No client-only “paid”.

## Logcat filters

```text
[Razorpay] orderReady
[Razorpay] openCheckout
[Razorpay] clientSuccess|clientError|verifyOk|verifyFail
```
