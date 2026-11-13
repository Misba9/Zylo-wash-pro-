# WashPro — Doorstep Car Wash & Detailing (Hyderabad)

Implements `PRD.md` v1.0: Flutter customer app, React worker PWA, React admin dashboard, Firebase backend (Firestore, Auth, Functions Gen 2, Storage, FCM).

## Run locally (Demo Mode — no Firebase needed)
Demo mode uses seeded Hyderabad data persisted to `localStorage`. It exercises the *same* pricing, state-machine and assignment-scoring logic as the Cloud Functions (shared in `packages/shared-types`).

```bash
npm install
npm run dev:worker   # http://localhost:5174  (ZYLO Field — worker PWA)
npm run dev:admin    # http://localhost:5173  (Admin Dashboard)
npm test             # unit tests: pricing, transitions, assignment scoring
npm run build        # production builds for both web apps
```

**Demo logins (any OTP/password):**
- Admin: any email → dashboard (role switcher in sidebar: Operations / Finance / Super Admin)
- Worker: select a worker profile on the login screen (e.g. Ramesh K.)

**Customer app (Flutter) — Firebase Phone Auth only (no OTP bypass in the app):**
```bash
cd apps/customer-mobile && flutter pub get && flutter run
# Use Firebase Console → Authentication → Phone → Test phone numbers for QA.
# Never ship hardcoded OTPs or demo logins in a Play release build.
```

## Go live with Firebase (`wash-pro-7f3b1`)
1. Enable Phone Auth, Firestore, Storage, Functions (Blaze), FCM.
2. Copy `.env.example` → `apps/*/.env.local` with web config; apps auto-switch from demo to Firebase mode.
3. Set secrets: `firebase functions:secrets:set RAZORPAY_KEY_ID` (etc.)
4. `firebase deploy --only firestore:rules,firestore:indexes,storage,functions,hosting:main`
5. See `docs/PRODUCTION_READINESS_AUDIT.md` and `docs/RELEASE_CHECKLIST.md` before Play upload.