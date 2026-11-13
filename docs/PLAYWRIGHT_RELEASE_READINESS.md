# ZYLO Playwright Release Readiness Scorecard

**Verdict: NOT ready for open production launch** based on E2E + known infra.  
Controlled / closed testing may proceed on Firebase Hosting URLs (`*.web.app`) while custom-domain TLS/DNS and Flutter device QA remain open.

## Scorecard

| Module | Total\* | Passed | Failed | Blocked / skipped | Status |
|--------|--------:|-------:|-------:|------------------:|--------|
| Customer (web/marketing) | 6 | 5 | 0† | 1 (www TLS expected) | Conditional |
| Worker | 4 | 4 | 0 | 0 | Pass (demo + hosted smoke) |
| Admin | 4 | 4 | 0 | 0 | Pass (demo) |
| Authentication | 6 | 3 | 0 | 3 | Partial |
| Booking | 1 | 0 | 0 | 1 | **Blocked** (Flutter) |
| Payments | 3 | 2 | 0 | 1 | Boundaries only — **no Live** |
| Firebase/API | 5 | 4 | 0† | 1 (field DNS expected) | Conditional |
| Security | 5 | 5 | 0 | Flow D deep | Pass (smoke) |
| Performance | 2 | 2 | 0 | — | Pass (smoke budgets) |
| Integration | 3 | 2 | 0 | 1 (Flow A–C) | Partial |

\*Unique primary specs (not × browsers). Multi-browser matrix: Chromium, WebKit, mobile Chrome/Safari, tablet — **108** expected passes in last full multi-project run.  
†Infra cases use Playwright `test.fail` so the suite exits 0 while still documenting blockers.

## Distinction of evidence types

| Type | What was done |
|------|----------------|
| Automated browser tests | Marketing, privacy, admin/worker demos, security/perf smoke across Chromium + WebKit + device emulation |
| API tests | Public HTTP + unauth callable rejection |
| Firebase emulator tests | **Not run** in this Playwright pass |
| Mocked payment tests | Boundary documentation only |
| Real Razorpay Test Mode | **Manual checklist required** — not automated end-to-end |
| Physical device tests | **Not run** |
| Play Console checks | **Not run** |

## Release blockers (must clear)

1. **P1 TLS:** `www.zyloo.co.in` certificate common-name / validity for modern browsers.  
2. **P1 DNS:** `field.zyloo.co.in` must not redirect to non-resolving `www.field.zyloo.co.in`. Prefer Firebase worker host or correct custom domain.  
3. **Flutter device QA:** OTP (Firebase test numbers), booking, Razorpay **Test** Mode (UPI/Intent/QR vs Cards), closed testing track.  
4. Deploy pending security/rules/functions changes only with explicit approval (not done by this suite).

## Non-blockers for Firebase Hosting soft launch

- Local/demo admin Control and worker Field flows green.  
- Unified host `wash-pro-7f3b1.web.app` serves marketing + `/field` + `/admin` shells.  
- Unauthenticated payment order creation rejected.

## How to re-verify

```bash
cd "/Volumes/storage/Start-Ups/Wash PRO"
export PLAYWRIGHT_BROWSERS_PATH="$HOME/Library/Caches/ms-playwright"
export TMPDIR=/tmp
export E2E_FORCE_DEMO=1
npm run test:e2e -w @washpro/e2e
npm run test:e2e:report -w @washpro/e2e
```

See `docs/PLAYWRIGHT_TESTING.md` and `docs/E2E_TEST_RESULTS.md`.
