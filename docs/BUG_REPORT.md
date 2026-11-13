# ZYLO Bug Report (Production Audit)

## Open / accepted

| ID | Sev | Title | Repro | Expected | Actual / mitigation |
|----|-----|-------|-------|----------|---------------------|
| B-01 | P1 | App Check missing | N/A | Integrity tokens on callables | Not implemented — accept until Phase enforce |
| B-02 | P1 | Booking create still client Firestore | Book online | `createBooking` CF only | Client create + server re-quote at pay (**mitigated**) |
| B-03 | P1 | UPI Intent/QR in Test Mode | Checkout Test keys, no UPI apps | Cards + Collect | Intent/QR need Live — documented |
| B-04 | P2 | Admin bootstrap email in rules | Create admins doc | Claims-only | Temporary `admin@washproo.in` path remains |
| B-05 | P2 | Analyze `withOpacity` / BuildContext async | `flutter analyze` | Clean | Infos only — non-blocking |
| B-06 | P3 | Privacy login copy not tappable | Auth screen | Links open policy | Text only |

## Fixed this audit

| ID | Sev | Title | Fix |
|----|-----|-------|-----|
| F-01 | P0 | Underpay via client totalPaise | `trusted_amount` in `createPaymentOrder` |
| F-02 | P0 | Customer self-complete | Rules + `verifyCompletion` |
| F-03 | P0 | Subscription visitBalance client edit | Rules lock |
| F-04 | P0 | Storage evidence public to any auth user | Claim-scoped rules |
| F-05 | P1 | Debug signing fallback on release | Gradle check fails closed |
| F-06 | P1 | Incomplete account anonymisation | Redact address/GPS; delete profile Storage |
| F-07 | P3 | README claimed OTP `123456` demo | Removed |
