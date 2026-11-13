# ZYLO Playwright E2E Testing Guide

**Suite path:** `tests/e2e/` · **Workspace:** `@washpro/e2e`  
**Brand:** ZYLO · **Firebase:** `wash-pro-7f3b1`

## Apps under test

| Surface | Path / URL | Playwright coverage |
|---------|------------|---------------------|
| Marketing / customer web | `apps/website` → `wash-pro-7f3b1.web.app`, local `:5175` | Automated |
| Worker PWA | `apps/worker-pwa` → local demo `:5174`, `wash-pro-worker.web.app` | Demo + hosted login smoke |
| Admin Control | `apps/admin-dashboard` → local demo `:5173`, `wash-pro-admin.web.app` | Demo + hosted login smoke |
| Customer mobile | `apps/customer-mobile` (Flutter) | **Not browser-automatable** — skipped with reason |
| Cloud Functions / hosting | Gen2 callables, Firebase Hosting | API smoke only |

## Important limitations

1. **Browser device emulation ≠ real Android/iOS devices.** Pixel/iPhone/iPad projects use Playwright device descriptors only.
2. **Flutter customer booking, OTP SMS, and Razorpay native checkout are out of scope** for this suite. Use device / Test Mode checklists.
3. **Do not use Live Razorpay keys or production OTPs.** Optional `.env.test` credentials must be dedicated test accounts.
4. **Local admin/worker demos** require empty `VITE_FIREBASE_*` (Playwright `webServer` clears them; set `E2E_FORCE_DEMO=1` to avoid reusing a LIVE Vite process).

## Layout

```
tests/e2e/
  playwright.config.ts
  global-setup.ts / global-teardown.ts
  .env.test.example
  config/urls.ts
  fixtures/          # reserved for shared fixtures
  pages/             # Page Object Model
  helpers/           # auth, console guard
  factories/         # test data builders
  tests/
    customer/ authentication/ booking/ payments/
    worker/ admin/ api/ security/ performance/ integration/
  reports/           # html, results.json, test-output artifacts
```

## Projects

| Project | Role |
|---------|------|
| `chromium` / `firefox` / `webkit` | Desktop browsers (marketing + shared specs; admin/worker/api excluded) |
| `mobile-chrome` / `mobile-safari` / `tablet` | Emulated viewports |
| `worker-demo` / `admin-demo` | Local demo Vite apps |
| `api` | `APIRequestContext` HTTP smoke |

## Scripts

From repo root:

```bash
npm run test:e2e
npm run test:e2e:ui
npm run test:e2e:headed
npm run test:e2e:debug
npm run test:e2e:customer
npm run test:e2e:worker
npm run test:e2e:admin
npm run test:e2e:api
npm run test:e2e:payments
npm run test:e2e:integration
npm run test:e2e:mobile
npm run test:e2e:report
```

Recommended env for CI / agent runs:

```bash
export PLAYWRIGHT_BROWSERS_PATH="$HOME/Library/Caches/ms-playwright"
export TMPDIR=/tmp
export E2E_FORCE_DEMO=1
npx playwright install chromium firefox webkit   # once
npm run test:e2e -w @washpro/e2e
```

## Selectors

Prefer `data-testid` (admin sidebar: `nav-overview`, `nav-bookings`, …) and role-based locators. Avoid brittle CSS.

## Artifacts

- HTML: `tests/e2e/reports/html/` (`npm run test:e2e:report`)
- JSON: `tests/e2e/reports/results.json`
- Failures: screenshots, video, trace under `tests/e2e/reports/test-output/`

## Related docs

- `docs/E2E_TEST_RESULTS.md` — latest run numbers  
- `docs/PLAYWRIGHT_BUG_REPORT.md` — bugs found  
- `docs/PLAYWRIGHT_SECURITY_RESULTS.md` — security probes  
- `docs/PLAYWRIGHT_RELEASE_READINESS.md` — scorecard / blockers  
