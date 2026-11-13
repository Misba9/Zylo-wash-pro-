# ZYLO Playwright Security Results

**Scope:** Non-destructive browser + HTTP probes only. No production data deletion, no rule disablement, no Live payment secrets.

## Automated probes (passed)

| Check | Method | Result |
|-------|--------|--------|
| Marketing does not expose admin Control sidebar | UI assert on local marketing | Pass |
| Worker hosted shell does not embed admin chrome | UI assert on `wash-pro-worker.web.app` | Pass |
| Admin hosted requires login for ops | Sign-in form present; no open dashboard without auth | Pass |
| Frontend bundles lack Razorpay **secret** patterns | Page/content scan for secret-like Razorpay key material | Pass (publishable keys may appear — secrets must not) |
| XSS probe on marketing contact fields | Inject script-like strings; assert no execution | Pass |
| Unauthenticated `createPaymentOrder` callable | POST without auth → not HTTP 200 | Pass |
| Customer A/B booking isolation (browser) | Full Flow D | **Not executed** — needs Firebase test users (documented blocked) |
| Worker A/B job isolation (live) | Beyond demo seed | **Partial** — demo job list scoped to selected worker only |
| Firestore rules / App Check | Rules unit / deploy | Outside Playwright; see production readiness audit |

## Explicitly not performed

- Destructive security testing against production Firebase  
- Credential stuffing / brute force beyond single invalid login  
- Bypassing OTP or forging payment signatures  
- Exposing secrets in HTML reports  

## Residual risks

1. Custom domains TLS/DNS issues (`www`, `field`) weaken trust for customers/workers even if Firebase hosts are healthy.  
2. App Check not enforced (see production readiness).  
3. Client-visible Firebase config is expected; confirm Functions/rules remain source of truth for pricing and payment status.
