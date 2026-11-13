# ZYLO E2E Test Results

**Run date:** 2026-11-11 (IST 2026-11-12)  
**Config:** `tests/e2e/playwright.config.ts`  
**Command:** `E2E_FORCE_DEMO=1` · projects `chromium`, `webkit`, `mobile-chrome`, `mobile-safari`, `tablet`, `worker-demo`, `admin-demo`, `api`  
**Duration:** ~30.5s  
**HTML report:** `tests/e2e/reports/html/`  
**JSON:** `tests/e2e/reports/results.json`

## Headline

| Metric | Count |
|--------|------:|
| Total executed outcomes (all projects) | 143 |
| Passed (expected) | 108 |
| Skipped | 35 |
| Unexpected failures | **0** |
| Flaky | 0 |
| Expected infra failures (`test.fail`) | 2 unique cases × browsers (www TLS, field DNS) — counted as expected |

Exit code **0**. Suite is green with known infra marked via `test.fail`.

## Coverage by module (unique specs; multi-browser multiplies outcomes)

| Module | Specs exercised | Result notes |
|--------|-----------------|--------------|
| Customer (marketing / privacy) | Homepage, privacy, delete-account, `/app` | Pass on Chromium/WebKit/mobile emulation; www TLS expected-fail |
| Authentication | Demo admin boot, hosted invalid login, worker picker/hosted invalid, optional live admin, OTP | Pass where runnable; live admin / OTP skipped without secrets |
| Worker | Demo dashboard, profile, job scope, manifest | Pass (`worker-demo`) |
| Admin | Dashboard nav, pricing calculator, seat price save, finance/audit | Pass (`admin-demo`); `data-testid` nav added |
| Booking | Flutter booking journey | **Skipped** — not browser-automatable |
| Payments | Boundaries + manual Test Mode checklist | Documented / soft pass; no Live charges; Flutter path skipped |
| Firebase/API | Public hosts, redirects, unified shells, unauth callable reject | Pass except field DNS expected-fail |
| Security | Isolation, secrets grep, XSS probe | Pass |
| Performance | Local DCL budget, production TTFB smoke | Pass (budgets documented in spec) |
| Integration | Marketing CTA, admin↔worker isolation | Pass; Flow A–C Flutter+CF **skipped/blocked** |

## Browser / device matrix

| Target | Status |
|--------|--------|
| Chromium desktop | Executed — pass |
| WebKit desktop | Executed — pass |
| Mobile Chrome (Pixel 7 emu) | Executed — pass |
| Mobile Safari (iPhone 14 emu) | Executed — pass |
| Tablet (iPad Pro emu) | Executed — pass |
| Firefox desktop | **Blocked in this agent environment** (Nightly profile launch / sandbox) — project configured; re-run locally |

**Reminder:** emulation is not a substitute for physical devices or Play Console pre-launch reports.

## Skipped / blocked (intentional)

- Live admin login without `E2E_ADMIN_EMAIL` / `E2E_ADMIN_PASSWORD`
- Firebase phone OTP without Console test number + OTP env
- Full customer booking / Razorpay native checkout (Flutter)
- Cross-app Flow A–C end-to-end (requires Flutter + test Firebase accounts)
- Firefox in Cursor agent sandbox

## Artifacts

Failure/expected-fail artifacts (screenshots, video, traces) retained under `tests/e2e/reports/test-output/` for www TLS and field DNS checks.
