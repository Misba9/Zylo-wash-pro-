# ZYLO Test Cases

## Automated (evidence this session)

| ID | Area | Case | Result |
|----|------|------|--------|
| A-01 | Flutter | Full unit/widget suite | **PASS** 59/59 |
| A-02 | Flutter | `flutter analyze` (errors) | **PASS** 0 errors |
| A-03 | shared-types | Pricing + catalog quote ₹602 | **PASS** 16/16 |
| A-04 | Functions | Razorpay HMAC crypto | **PASS** |
| A-05 | Functions | serviceLocation no invented GPS | **PASS** |
| A-06 | Functions | Trusted amount underpay guard | **PASS** |
| A-07 | Worker | typecheck + navigation tests + build | **PASS** |
| A-08 | Admin | typecheck | **PASS** |

## Manual / device (not executed this session)

| ID | Area | Case | Status |
|----|------|------|--------|
| M-01 | Auth | Valid +91 OTP (Console test number) | NOT TESTED |
| M-02 | Auth | Wrong OTP / resend cooldown | NOT TESTED |
| M-03 | Auth | Session restore / logout / delete account | NOT TESTED |
| M-04 | Booking | 3-step flow + express ₹602 path | NOT TESTED |
| M-05 | Pay | Razorpay Test Mode Cards | NOT TESTED |
| M-06 | Pay | UPI Collect `success@razorpay` | NOT TESTED |
| M-07 | Pay | Kill app mid-checkout + reconcile | NOT TESTED |
| M-08 | Worker | Assign → navigate → checklist → verify | NOT TESTED |
| M-09 | Admin | Create service → customer sees it | NOT TESTED |
| M-10 | Privacy | Public privacy + delete-account URLs HTTP 200 | NOT TESTED |

## Commands

```bash
cd apps/customer-mobile && flutter analyze && flutter test
cd packages/shared-types && npm test
cd functions && npm test
cd apps/worker-pwa && npm run typecheck && npm test && npm run build
cd apps/admin-dashboard && npm run typecheck
```
