# ZYLO Production Readiness Audit

**Project:** `wash-pro-7f3b1` · **Package:** `com.washpro.customer` · **Version:** `1.2.0+3`  
**Date:** 2026-11-11  
**Scope:** Customer Flutter, Worker PWA, Admin, Cloud Functions, Rules, Play prep  

**Verdict: NOT production-ready for open Play release.** Critical security fixes landed in-repo; deploy rules/functions, closed testing, App Check, and physical-device UPI/OTP still required.

---

## Architecture (preserved)

| Component | Path | Notes |
|-----------|------|-------|
| Customer | `apps/customer-mobile` | Flutter, Phone Auth, Razorpay Standard |
| Worker | `apps/worker-pwa` | ZYLO Field React PWA |
| Admin | `apps/admin-dashboard` | ZYLO Control |
| Functions | `functions/` | Gen 2 callables + webhooks |
| Rules | `firestore.rules`, `storage.rules` | Hardened in this audit |
| Hosting | `zyloo.co.in` / `wash-pro-7f3b1.web.app` | Unified |

---

## Severity findings

### P0 — Critical (fixed or mitigated in repo)

| ID | Issue | Status |
|----|-------|--------|
| P0-1 | Client-written `priceSnapshot` trusted for Razorpay amount | **Mitigated:** `createPaymentOrder` now recomputes via `trusted_amount` / catalog quote; underpayment blocked |
| P0-2 | Customer could set booking `status: completed` / rewrite payment fields | **Fixed:** Rules allow customer cancel only; completion via `verifyCompletion` CF; Flutter updated |
| P0-3 | Customer could mutate subscription `visitBalance` | **Fixed:** Rules lock visitBalance/status to Functions |
| P0-4 | Storage job evidence readable by any signed-in user | **Fixed:** Admin/worker claim only |

### P1 — Release blockers (partial / pending deploy)

| ID | Issue | Status |
|----|-------|--------|
| P1-1 | Firestore/Storage/Functions changes not yet **deployed** | Manual: deploy with approval |
| P1-2 | App Check not enforced | Pending |
| P1-3 | Admin email bootstrap `admin@washproo.in` still in rules | Accept risk for pilot; remove for public launch |
| P1-4 | Flutter still writes booking create client-side (amount then corrected at pay) | Accept interim; prefer full `createBooking` CF next |
| P1-5 | Account deletion: bookings retain `customerUid` for tax; coords redacted | Improved; document retention |
| P1-6 | UPI Intent/QR require Live Mode — not verified on device this run | See `RAZORPAY_UPI_TEST.md` |
| P1-7 | Release signing now fails closed without `key.properties` | Fixed in Gradle |

### P2 / P3

- Stale README OTP demo text → **fixed**
- Dual pricing sources (Flutter fees vs catalog) → converging via trusted_amount
- No App Check · analytics placeholders · RBAC demo switcher
- Analyze infos (`withOpacity`, BuildContext async) — non-blocking

---

## Automated evidence (this session)

| Suite | Command | Result |
|-------|---------|--------|
| Flutter analyze | `flutter analyze` | **0 errors** (infos/warnings only) |
| Flutter test | `flutter test` | **59 passed** |
| shared-types | `npm test` | **16 passed** |
| functions | `npm test` | **7 passed** (crypto + location + trusted quote) |
| admin | `npm run typecheck` | **pass** |
| worker | `npm run typecheck && npm test && npm run build` | **pass** (2 tests + production build) |

Physical device / OTP SMS / Live Razorpay / Play Console upload: **not tested this session**.

---

## Fixes applied in this audit

1. `functions/src/trusted_amount.ts` + wired into `createPaymentOrder`
2. `firestore.rules` booking/subscription hardening
3. `storage.rules` evidence/profile tightening
4. `deleteMyAccount` deeper anonymisation + Storage profile delete
5. Flutter `verifyCompletion` callable (no direct complete write)
6. Release Gradle refuses missing keystore
7. README OTP demo wording removed

---

## Deploy when approved (do not run without explicit approval)

```bash
firebase deploy --only firestore:rules,storage,firestore:indexes --project wash-pro-7f3b1
firebase deploy --only functions --project wash-pro-7f3b1
cd apps/customer-mobile && flutter build appbundle --release
```

Do **not** switch Razorpay to Live or upload AAB without approval.
