# Zylo — Razorpay UPI in Test Mode

## Why UPI was missing (root cause)

UPI was **ACTIVATED** on the Razorpay Dashboard, but Checkout still hid UPI because:

1. **Android 11+ package visibility** — the app `targetSdk` is 30+. Without `<queries>` for UPI packages / `upi://` intents in `AndroidManifest.xml`, the Razorpay native SDK cannot detect UPI apps and often **omits the entire UPI block**.
2. **Ineffective method flags** — the Flutter `method: { upi: true, emi: false, … }` map is **not reliably applied** by `razorpay_flutter` Standard Checkout. EMI / Netbanking / Wallet / Pay Later kept appearing for that reason (not because UPI was disabled in code).

This was an **Android/SDK checkout configuration** issue, not a Dashboard “UPI off” issue and not a Live-key mix-up (keys remain Test Mode / `rzp_test_…` via Cloud Functions secrets).

## Fixes applied

| Area | Change |
|---|---|
| `android/.../AndroidManifest.xml` | Added official Razorpay UPI `<queries>` (GPay, PhonePe, Paytm, BHIM, `upi` scheme, …) |
| `ios/Runner/Info.plist` | Added `LSApplicationQueriesSchemes` for UPI schemes |
| `lib/services/app_services.dart` | Use `config.display.hide` for emi/netbanking/wallet/paylater; normalise `prefill.contact` to 10 digits |

Backend `createPaymentOrder` / `verifyPayment` / webhooks were **not** changed. Payments are still only confirmed after server signature verification.

## Test Mode — official UPI VPAs

In Checkout → **UPI** → enter VPA (Collect flow):

| VPA | Expected |
|---|---|
| `success@razorpay` | Simulated success |
| `failure@razorpay` | Simulated failure |

Then confirm:

1. Flutter success callback → `verifyPayment` Cloud Function succeeds → booking `paid` / `confirmed`
2. Failure → booking stays `awaiting_payment`; retry allowed
3. Duplicate pay blocked by existing pending-order reuse + server checks

### What Test Mode actually covers

| Flow | In Test Mode |
|---|---|
| **UPI Collect (enter VPA)** | Supported with `success@razorpay` / `failure@razorpay` |
| **UPI Intent** (open GPay / PhonePe / …) | Requires a **real device** with those apps + the new `<queries>`. Intent against **real apps** is not a true money movement in Test Mode; Razorpay docs note UPI Intent is best validated in Live Mode. |
| **UPI QR** | Not claimed verified in this integration pass |

Do **not** claim Google Pay / PhonePe app switching or QR works until physically verified on a device.

## Dashboard checks (still required)

1. Stay in **Test Mode** credentials (`rzp_test_…` in Firebase secrets `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET`).
2. Confirm **UPI = ACTIVATED** (already done).
3. After rebuilding the Android app, open Checkout and confirm **UPI** appears beside **Cards**.
4. Optional: Payment Methods → ensure no account-level block on UPI Collect.

## Rebuild

```bash
cd apps/customer-mobile
flutter clean && flutter pub get
flutter run   # prefer a physical Android device for UPI Intent visibility
```
