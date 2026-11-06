# WashPro — Complete Development & Delivery Checklist

**Prepared:** Oct 22, 2026 · **App version:** 1.2.0+3 · **Status legend:** ✅ Done · 🟡 Partial/In-progress · ❌ Missing · 👤 Owner action required
**Scope:** WashPro doorstep car wash & detailing, Hyderabad — customer Android app (primary), worker PWA, admin dashboard, Firebase backend.

This document is the single source of truth for delivery sign-off. Anything not ✅ here is listed again in §10 (Incomplete) or §11 (Dependencies) — nothing is hidden.

---

## 1. Screen list

### 1.1 Customer Android app (Flutter) — 17 screens
| # | Screen | Status | Notes |
|---|--------|--------|-------|
| 1 | Splash / session restore | ✅ | Auto sign-in for returning users |
| 2 | Login / Register (email + Google) | ✅ | Forgot password via reset email |
| 3 | Basic-details onboarding (first login only) | ✅ | Name, phone, email; skipped for returning users |
| 4 | Home | ✅ | Live banner, next-slot, upcoming booking, catalog, savings, garage |
| 5 | Booking flow (4 steps: car → service → schedule → review & pay) | ✅ | Service search + price sort, slot availability, double-tap guard |
| 6 | Booking success | ✅ | Shows PAID vs PAYMENT PENDING honestly |
| 7 | My Bookings (Upcoming / In progress / Completed) | ✅ | Load-more pagination, error+retry banner |
| 8 | Booking detail / live tracking / verify & rate | ✅ | Pay-now (Razorpay) for pending, cancel with confirm |
| 9 | Plans (explore + my subscription) | ✅ | Sort by saving/price/visits |
| 10 | Subscription management | ✅ | Pause/resume/skip/change time/cancel |
| 11 | Profile | ✅ | Edit name, member-since, logout |
| 12 | Settings | ✅ | Change password, push toggle, appearance (dark mode), privacy/terms, version, delete account |
| 13 | My Vehicles (CRUD) | ✅ | Default vehicle, validation |
| 14 | Saved Addresses (CRUD) | ✅ | Default address, service areas |
| 15 | Payments & refunds | ✅ | Real records from Firestore |
| 16 | Notifications | ✅ | Mark read/all, tap → booking, load-more |
| 17 | Help & Support | ✅ | Ticket creation, tracked in admin |

### 1.2 Worker PWA (React) — 6 views
Login/Register (email only, auto-approved) · Today · My Jobs · Job detail (trip → arrive → checklist → verification) · Earnings · Profile/availability. Before/after photo feature **removed by owner request** (checklist-only completion).

### 1.3 Admin dashboard (React) — 8 views
Overview · Bookings (+assign worker with recommendations) · Workers (approve/suspend, auto-approve) · Services & Pricing · Finance · Subscriptions · Support · Audit Logs. Live at wash-pro-admin.web.app.

---

## 2. Feature list (approved scope vs delivered)

| Area | Feature | Status |
|------|---------|--------|
| Auth | Email/password, Google sign-in, forgot password, logout, session restore | ✅ |
| Auth | Phone OTP | ❌ Removed at owner request (not a gap) |
| Profiles | First-login onboarding, edit profile, change password | ✅ |
| Catalog | Services/plans/banner from Firestore (admin-editable), search + sorting | ✅ |
| Booking | Scheduled + instant, real slot availability, idempotent create, cancel/reschedule with confirmations | ✅ |
| Payments | Cash (pay to expert) | ✅ Live |
| Payments | Online via Razorpay (order → checkout → server-side signature verify + webhook) | 🟡 Code complete; activates when keys are added (§11) |
| Subscriptions | Subscribe, pause/resume/skip/cancel, visit balance | ✅ (prepaid activation follows verified payment, §11) |
| Workers | Self-register (auto-approved), job lifecycle, live location sharing, earnings 70% | ✅ |
| Admin | Assignment recommendations, worker approve/suspend, pricing, finance view, tickets, audit log | ✅ |
| Notifications | In-app inbox (all apps) + FCM push (customer app) | 🟡 Push code complete; sends after Functions deploy (§11) |
| Engagement | Deep links (`washpro://booking/<id>`, notifications), dark mode, offline banner | ✅ (https link verification via assetlinks pending) |
| Account | Self-service account deletion + web deletion page | 🟡 Function ready; instant path activates with Functions deploy; interim = recorded request |

---

## 3. Technology stack

| Layer | Technology |
|-------|-----------|
| Customer app | Flutter (Dart), Material 3, `firebase_auth`, `cloud_firestore`, `cloud_functions`, `firebase_messaging`, `firebase_crashlytics`, `razorpay_flutter`, `connectivity_plus`, `app_links`, `google_sign_in` 7.x |
| Worker/Admin | React + TypeScript + Vite, Firebase JS SDK |
| Shared logic | TypeScript packages: domain/pricing/assignment scoring (`packages/shared-types`), validation schemas, design tokens |
| Backend | Firebase: Authentication (Email, Google), Cloud Firestore (rules+indexes deployed), Cloud Functions Gen 2 / Node TS (written, compile-verified, **not yet deployed**), FCM, Crashlytics, Hosting (3 sites live) |
| Payments | Razorpay (orders + signature verification + webhooks, server-side secrets only) |
| Projects | Pilot `wash-pro-7f3b1` (live), Production `washpro-prod` (created; auth+rules deployed; cut-over pending) |
| Android | Package `com.washpro.customer`, signed upload key (R8/ProGuard), adaptive icon, version 1.2.0+3 |
| Docs | `docs/` — PRD, architecture, data-model, security, booking-workflow, deployment, PLAY_STORE, FIREBASE_WASH_PRO, RELEASE_FEATURES, KEYSTORE_BACKUP, this checklist |

---

## 4. Backend / API / database integration (§2 of your list)

- ✅ Firestore is the database; **every** customer screen reads/writes live data — no hardcoded demo data (demo fallback exists only if Firebase is unreachable).
- ✅ Firestore Security Rules: deny-by-default, owner-scoped collections, role checks via `admins/{uid}` doc + custom claims; deployed to both projects.
- ✅ Cloud Functions implement the API layer (createBooking, payments, subscriptions, assignments, support, notifications trigger, deleteMyAccount) — TypeScript compiles clean; **deployment pending Blaze** (§11).
- ✅ Auth token/session handled by Firebase SDK; server validation via callable Functions + zod schemas.
- 🟡 Timeouts/retries: Firestore internal retries + UI retry banners; no custom backoff layer (accepted for pilot).

## 5. Security, privacy, permissions

- ✅ HTTPS-only (Firebase), no private keys/secrets in the app (Razorpay secret = server secret only).
- ✅ Android permissions minimized: INTERNET, ACCESS_NETWORK_STATE, POST_NOTIFICATIONS only. No camera/location/storage permissions (photo feature removed).
- ✅ Privacy Policy + Terms + account-deletion pages live (`wash-pro-customer.web.app/privacy.html`, `/terms.html`, `/delete-account.html` — hosting deployed Oct 22, 2026, all HTTP 200).
- 🟡 App Check / Play Integrity not enabled (recommended post-launch).
- ✅ Keystore backed up outside repo with checksums (`docs/KEYSTORE_BACKUP.md`); off-laptop copy is an owner action (§11).

## 6. Loading, validation, error & network handling

- ✅ Form validation (auth, onboarding, vehicles, addresses, booking guards).
- ✅ Loading indicators, empty states (all lists), error states with Retry (bookings, notifications, vehicles, addresses, plans), friendly auth/payment error mapping.
- ✅ Offline: global offline banner, Firestore offline cache enabled, writes queue and sync; write failures toast instead of failing silently.
- ✅ Confirmation dialogs for cancel booking, delete vehicle/address, delete account, plan cancellation.

## 7. Performance & device compatibility

- ✅ Tree-shaken release build (~56 MB APK), lazy list rendering + load-more pagination, stream-based (no polling) data.
- 🟡 Not yet profiled on low-end devices; no startup/scroll/memory measurements recorded — covered by the device test plan (§9) before production rollout.
- 🟡 Dark mode v1: theme-aware scaffolds; some cards intentionally remain light (readability) — cosmetic, not functional.

## 8. Push notifications & Android-specific

- ✅ FCM: permission (Android 13+), token stored on `users/{uid}`, foreground banner, tap → booking; server trigger sends push for every notification (activates on Functions deploy).
- ✅ Deep links (custom scheme live; https App Links need `assetlinks.json` with Play signing SHA — post-Play step).
- ✅ Back-button/keyboard defaults correct (`adjustResize`); lifecycle via Firestore streams.
- ❌ Worker web push (VAPID) not implemented — workers rely on in-app live updates (accepted).

---

## 9. Testing plan (every feature end-to-end before delivery)

### 9.1 Automated (running now)
| Suite | Coverage | Result |
|-------|----------|--------|
| Flutter tests (9) | Auth screen, pricing incl. Firestore-shaped data, slots, profile gate, plan savings, empty state | ✅ 9/9 |
| Shared-types tests (6) | Pricing/assignment/state machine | ✅ 6/6 |
| Static analysis | `flutter analyze` 0 errors; TS builds clean (apps + functions) | ✅ |

### 9.2 Manual E2E — must pass on a real phone before delivery sign-off
1. Fresh install → register → onboarding → home loads live catalog.
2. Forgot password → email reset → login with new password.
3. Google sign-in → returning user skips onboarding.
4. Add/edit/delete vehicle & address (incl. validation failures).
5. Book scheduled wash (cash) → admin assigns worker → customer notified (in-app + push after deploy) → worker trip/arrive/checklist → customer verifies + rates → completed; worker earnings update.
6. Book online → Razorpay test payment → success, failure, and cancel paths; booking never shows PAID without server verification. *(After keys.)*
7. Subscribe to a plan → pause → resume → skip visit → cancel.
8. Airplane mode mid-booking → offline banner → reconnect → data syncs; kill/reopen → session restored.
9. Settings: change password (incl. wrong-current-password), push off/on, dark mode persists, delete account (instant after deploy).
10. Deep link `washpro://booking/<id>` opens the booking; invalid inputs everywhere show friendly errors.

### 9.3 API/backend tests
- Firestore rules: owner can/can't matrix per collection (test with two accounts + one worker + admin) — **to run on emulator before prod cut-over** 🟡.
- Functions: callable auth checks, payment signature verify (valid/invalid), webhook replay/idempotency — after deploy, Razorpay test mode 🟡.

### 9.4 Device matrix (before production rollout)
Low-end Android (≤3 GB RAM, Android 10–12), mid (Android 13–14), current flagship (Android 15+); small (5") and large (6.7") screens; Wi-Fi, 4G, offline, slow-3G throttle. Crashlytics verified with a forced test crash after deploy.

### 9.5 Regression rule
`flutter analyze` + all automated suites green on every release build; §9.2 smoke (steps 1,4,5,8) re-run for any change touching auth, booking, or payments.

---

## 10. Incomplete features & known issues (honest list)

| # | Item | Impact | Unblocks when |
|---|------|--------|---------------|
| 1 | Online payments not live — online bookings wait at "Awaiting payment" (cash fully works) | No prepaid revenue yet | Razorpay keys + Blaze + Functions deploy |
| 2 | Push notifications not sending yet (in-app inbox works) | Customers must open app for updates | Functions deploy (same step as #1) |
| 3 | Instant account deletion falls back to recorded request | ≤30-day manual deletion | Functions deploy |
| 4 | Cloud Functions written but undeployed (Spark plan). Deploy attempted Oct 22, 2026 — Firebase refused: "must be on the Blaze plan" | Items 1–3 + server-side booking APIs run in "direct Firestore" staging mode | Blaze upgrade (owner billing): https://console.firebase.google.com/project/wash-pro-7f3b1/usage/details |
| 5 | Prod project `washpro-prod` empty catalog; no prod admin/SHA yet | Prod build shows no services until seeded | Cut-over steps, RELEASE_FEATURES §13 |
| 6 | Worker web push absent | Workers check app for jobs | VAPID setup (optional, later) |
| 7 | No device-matrix/performance test evidence yet | Unknown low-end behaviour | §9.4 before production rollout |
| 8 | https App Links unverified (no assetlinks) | Web links may open browser first | After Play App Signing SHA exists |
| 9 | Source not pushed to a git remote | Single-machine risk | Owner picks GitHub/private repo |
| 10 | Admin/Worker web apps still point at pilot project | Prod cut-over incomplete | At cut-over with #5 |

**Intentionally out of scope (owner decisions, not defects):** phone OTP (removed), before/after photos (removed), QR scanning, customer live-map tracking.

---

## 11. Pending dependencies (owner / external)

| # | Dependency | Owner | Needed for |
|---|-----------|-------|-----------|
| 1 | Firebase Blaze upgrade (billing) on `wash-pro-7f3b1` (and later `washpro-prod`) | 👤 You | Functions deploy → payments, push, instant deletion |
| 2 | Razorpay account + KYC + Key Id/Secret + webhook secret (test first) | 👤 You | Online payments go-live |
| 3 | Copy `~/WashPro-Backups/` to Drive + USB | 👤 You | Signing-key safety |
| 4 | Play Console developer account ($25), screenshots, data-safety, content rating, internal-testing upload | 👤 You | Play Store release |
| 5 | ~~Say "deploy" for hosting~~ ✅ Done Oct 22, 2026 (all 3 sites + delete-account page live) | — | — |
| 6 | Prod cut-over: seed catalog, SHA fingerprints, prod admin | Us, on your go-ahead | Production launch |
| 7 | Git remote (GitHub account/repo name) | 👤 You choose | Source backup/handover |

---

## 12. Development milestones

| Milestone | Scope | Status |
|-----------|-------|--------|
| M1 Foundation | Firebase projects, auth, rules, data model, docs | ✅ Complete |
| M2 Customer app | All 17 screens, live data, honest payments, tests | ✅ Complete (v1.2.0) |
| M3 Worker + Admin | Job lifecycle, assignment, auto-approve, finance/support | ✅ Complete |
| M4 Monetisation & messaging activation | Blaze → Functions deploy → Razorpay live → push live | 🟡 Blocked on §11.1–11.2 |
| M5 Hardening & QA | Device matrix, rules tests, Crashlytics verification, performance pass | 🟡 Plan ready (§9), execution pending devices |
| M6 Play Store release | Listing, data safety, internal → production rollout | ❌ Pending §11.4 |
| M7 Production cut-over | `washpro-prod` seed/config, ENV=prod builds, monitoring | 🟡 Project ready; cut-over pending |

## 13. Handover package

✅ Complete source (this workspace) · ✅ docs: PRD, architecture, data-model, security, booking-workflow, deployment, PLAY_STORE runbook, FIREBASE_WASH_PRO runbook, RELEASE_FEATURES go-live guide, KEYSTORE_BACKUP · ✅ signed APK (`WashPro-Customer.apk`) + AAB · ✅ this checklist + gap-audit canvas · 🟡 formal test report = §9 results recorded at M5 · 👤 final sign-off below.

**Delivery sign-off:** ☐ Approved to proceed to M4–M6 · Name/Date: ____________________
