# ZYLO Security Audit

**Project:** wash-pro-7f3b1 · **Date:** 2026-11-11

## Authentication
- Phone Auth via Firebase SDK — **no OTP bypass in app source** (verified by search).
- Console test numbers are ops-only; remove before public SMS billing.
- Customers cannot obtain worker/admin claims via client updates (`users` role keys blocked).

## Payments
- Razorpay secrets: Firebase Secret Manager only — **not in Flutter**.
- Checkout signature verification: `verifyPayment` + webhook HMAC (`payments_crypto`).
- **Order amount:** recomputed from Firestore catalog in `trusted_amount` before Razorpay `/orders`.
- Flutter success callback alone does **not** mark paid — requires `verifyPayment`.
- Webhooks: idempotency keys used.

## Firestore rules (post-fix)
- Bookings: online create → `awaiting_payment`; no client `paymentStatus` paid; no customer self-complete.
- Subscriptions: no client `visitBalance` / status mutation.
- Payments: cash pending create only; finance/server for status.
- Catalog `plans`/`addons`/`coupons` rules present.

## Storage
- Job evidence: admin/worker role claims only.
- Profiles: owner write; owner/admin read.

## Account deletion
- In-app Settings → Delete account → `deleteMyAccount`.
- Public page: `https://wash-pro-customer.web.app/delete-account.html` (confirm live).
- Deletes vehicles/addresses/subs/notifications/tickets/user; anonymises bookings/payments; deletes `profiles/{uid}/`; deletes Auth user.
- Retains financial rows with redacted PII (tax/settlement).

## Remaining risks
- App Check not enforced.
- Admin bootstrap email rule.
- Booking create still client-path (amount corrected at order time).
- Do not log OTPs, tokens, or full card/UPI identifiers.

## Secrets hygiene
Never commit `key.properties`, `google-services.json` overrides with secrets, or Live Razorpay keys into git.
