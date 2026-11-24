# Zylo — Razorpay UPI Checkout

## Device finding (2026-11-24) — QR opens but real UPI apps reject it

**Observed on Android physical device:** Razorpay Checkout shows a QR; scanning in GPay/PhonePe shows Payee ZYLOO, amount (e.g. ₹602), description “Doorstep car wash”, then:

- `Cannot pay with this QR code`
- `UPI ID is invalid`
- `Could not load banking name`

| Question | Answer |
|----------|--------|
| **QR source** | **Razorpay Standard Checkout** (`razorpay_flutter` → Checkout.js / native Checkout). **Not** Razorpay QR Codes API (`/v1/payments/qr_codes`). **Not** app-generated / hardcoded UPI QR. |
| **Who sets the VPA** | Razorpay Checkout embeds the merchant UPI payee for the **key mode**. App never invents a personal VPA. |
| **Environment** | Root / `functions/.env` uses `rzp_test_…` → **Test Mode**. |
| **Root cause** | **Test Mode Checkout QR is not a production UPI QR.** Real UPI apps resolve the payee VPA on NPCI rails; Test Mode VPAs are sandbox and fail with “UPI ID is invalid” / “Could not load banking name”. Showing a QR ≠ payable QR. |
| **What works in Test** | Cards + UPI Collect test VPAs (`success@razorpay` / `failure@razorpay`) when Collect is still enabled — **not** scanning with a real bank UPI app. |
| **What works for real QR / Intent** | **Live Mode** (`rzp_live_…`) + UPI activated on the Razorpay account + KYC. Prefer UPI Intent on phones; Checkout QR is mainly wide screens. |
| **Paid marking** | Unchanged: only server `verifyPayment` / webhook after HMAC — client success alone never marks paid. |

**Do not claim QR payments fixed until a Live Mode scan completes and `verifyPayment` confirms the booking.**

## Root cause (Cards-only on Android)

Checkout opened, but **only Cards** appeared. Dashboard “UPI = ACTIVATED” alone does not guarantee every UPI sub-flow.

| Factor | Role |
|--------|------|
| **Primary (app)** | Custom `config.display.blocks` with `show_default_blocks: false` made Checkout show **only** instruments in that block. When no UPI sub-flow was available for the key/account, Razorpay **dropped UPI** and left Cards. Forcing `upi.flows: [intent,collect,qr]` made this worse in Test Mode. |
| Secondary | Android 11+ needs Manifest `<queries>` for UPI Intent apps (present). Missing queries hide Intent apps. |
| Account / mode | **Test Mode**: UPI Collect (VPA) when still enabled. **Live Mode**: UPI Intent (+ QR on wide screens). Installing UPI apps does **not** enable QR on typical phone widths (&lt; ~485dp per Razorpay). |
| NPCI Collect sunset | Collect is being deprecated (deadline 28 Feb 2026). If Collect is already off for the merchant on Android Test, Intent/QR need **Live** — Test may remain Cards-only until then. |
| Keys | Server `createPaymentOrder` returns `keyId` from `functions/.env` (synced from root `.env`). Must be `rzp_test_…` for Test Checkout. |

Backend order creation (`amount` paise, `currency: INR`, order id) and `verifyPayment` (HMAC) were **not** the cause of missing UPI.

## Fix applied

| Area | Change |
|------|--------|
| `lib/services/app_services.dart` | **Default Checkout blocks** + `hide` (emi/netbanking/wallet/paylater/cardless_emi). `sequence: [upi, card]`. `show_default_blocks: true`. No custom blocks, no forced `flows`. `jsonSafeOptions` before `open`. Safe diagnostics. |
| `AndroidManifest.xml` | Kept Razorpay UPI `<queries>`. |
| `ios/Runner/Info.plist` | Kept UPI `LSApplicationQueriesSchemes`. |
| Unit tests | Assert UPI/card not hidden; no custom `blocks`. |

Payments still confirmed **only** after server `verifyPayment`. Cash-after-service unchanged. Three-step booking unchanged.

## What each UPI method needs

| Flow | Test Mode (`rzp_test_`) | Live Mode (`rzp_live_`) |
|------|-------------------------|-------------------------|
| **UPI Collect / UPI ID** | Documented Test path (`success@razorpay` / `failure@razorpay`) **if Collect still enabled** | Being sunset; prefer Intent/QR |
| **UPI Intent** (GPay / PhonePe / …) | Not a reliable Test money flow; validate in **Live** | Needs UPI activated + apps + `<queries>` |
| **UPI QR** | Not for phone-sized Checkout | Live; mainly wide screens — **not expected on typical phones** |

Do **not** claim Intent/QR verified until tested on a physical device with the appropriate mode.

## Razorpay Dashboard checklist

1. Toggle **Test Mode** while developing; put `rzp_test_…` in root `.env` (`RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET`), then `node scripts/sync-razorpay-env.mjs`.
2. **Payment Methods → UPI → Activated**.
3. If Checkout is still Cards-only in Test: check whether **UPI Collect** was disabled for the account. Either re-enable Collect for Test QA, or switch to **Live** keys to validate Intent.
4. After key rotation: sync + redeploy payment functions so Checkout gets the new `keyId`.
5. Production Intent: Live keys in `.env` + KYC/activation + device test **with and without** UPI apps.

## Device QA (manual)

```bash
cd apps/customer-mobile
flutter clean && flutter pub get
flutter run   # physical Android preferred
```

1. Book online → open Checkout → confirm **UPI** appears with **Cards**.
2. **No UPI apps**: UPI ID / Collect (if offered) still visible — not Cards-only.
3. **With UPI apps** (Live): Intent app list appears.
4. Test VPA `success@razorpay` → client success → `verifyPayment` → booking paid.
5. Cancel / fail → booking stays unpaid; retry allowed. No client-only “paid”.

## Logcat filters

```text
[Razorpay] orderReady
[Razorpay] openCheckout
[Razorpay] clientSuccess|clientError|verifyOk|verifyFail
```

Expect `showDefaultBlocks=true`, `hasCustomBlocks=false`, `upiHidden=false`, `sequence=upi>card`.
