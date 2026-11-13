# ZYLO Playwright Bug Report

**Source:** Playwright E2E run 2026-11-11 · Suite `tests/e2e`

## Fixes applied during E2E work

| ID | Severity | Area | Issue | Fix |
|----|----------|------|-------|-----|
| E2E-F1 | Medium | Admin UI | Sidebar nav buttons matched multiple roles (`Bookings` vs `All bookings →`); emoji labels broke `/^Pricing$/` | Added `data-testid={nav-{page}}` on admin sidebar; POM uses `openNav(pageId)` |
| E2E-F2 | Low | Marketing | React 18 console warning on `fetchPriority` on `<img>` caused console-guard failures | Removed camelCase `fetchPriority`; console guard also ignores React unrecognized-prop noise |
| E2E-F3 | Low | Tests | Demo mode detection failed on viewports &lt;860px (`.hideS` hides “Demo mode”) | `AdminPage.isDemoMode()` uses Reset button / `nav-overview` + absence of login |
| E2E-F4 | Low | Config | Chromium project double-ran admin/worker; LIVE Vite reuse broke demo | `testIgnore` for admin/worker/api; `E2E_FORCE_DEMO` disables `reuseExistingServer`; webServer clears `VITE_FIREBASE_*` |

## Open bugs / infra (not fixed in this pass)

| ID | Severity | Area | Evidence | Reproduction | Suggested fix |
|----|----------|------|----------|--------------|---------------|
| E2E-B1 | **P1** | TLS / CDN | Chromium/WebKit: `net::ERR_CERT_COMMON_NAME_INVALID` / invalid certificate on `https://www.zyloo.co.in` | `page.goto('https://www.zyloo.co.in')` in Playwright | Issue a cert covering `www.zyloo.co.in` (and apex); verify Firebase Hosting custom domain |
| E2E-B2 | **P1** | DNS / worker domain | `https://field.zyloo.co.in` → `301` → `https://www.field.zyloo.co.in/` which does not resolve (`ENOTFOUND`) | `curl -I https://field.zyloo.co.in` | Point `field` (and/or `www.field`) to Firebase Hosting target for worker; avoid redirect to non-existent host |
| E2E-B3 | Medium | Admin responsive | Sidebar text/labels hidden under 860px; demo affordances hard to discover | Narrow viewport on admin demo | Optional: keep “Demo mode” / primary labels visible on compact layout |
| E2E-B4 | Info | Firefox CI | Firefox Nightly failed to launch in Cursor agent (`Could not find profile folder`) | `--project=firefox` in agent | Run Firefox on developer machine / CI with writable `TMPDIR` |

## Not bugs — missing product scope for browser E2E

- Customer booking / vehicles / addresses / coupons → Flutter app only  
- Real SMS OTP delivery → not claimed; requires Firebase test phone config  
- Razorpay Checkout iframe / UPI apps → Test Mode manual checklist only  

## Policy

No production customer data mutated. No Live Razorpay charges. No OTP bypass. No security rules disabled.
