# WashPro — Doorstep Car Wash & Detailing (Hyderabad)

Implements `PRD.md` v1.0: Flutter customer app, React worker PWA, React admin dashboard, Firebase backend (Firestore, Auth, Functions Gen 2, Storage, FCM).

## Run locally (Demo Mode — no Firebase needed)
Demo mode uses seeded Hyderabad data persisted to `localStorage`. It exercises the *same* pricing, state-machine and assignment-scoring logic as the Cloud Functions (shared in `packages/shared-types`).

```bash
npm install
npm run dev:worker   # http://localhost:5174  (Worker PWA)
npm run dev:admin    # http://localhost:5173  (Admin Dashboard)
npm test             # unit tests: pricing, transitions, assignment scoring
npm run build        # production builds for both web apps
```

**Demo logins (any OTP/password):**
- Admin: any email → dashboard (role switcher in sidebar: Operations / Finance / Super Admin)
- Worker: select a worker profile on the login screen (e.g. Ramesh K.)

**Customer app (Flutter):**
```bash
cd apps/customer-mobile && flutter pub get && flutter run
# OTP demo: any 10-digit number, OTP = 123456
```

## Go live with Firebase
1. Create `washpro-staging` + `washpro-prod` Firebase projects, enable Phone Auth, Firestore, Storage, Functions (Blaze).
2. Copy `.env.example` → `apps/*/.env.local` with your web config; apps auto-switch from demo to Firebase mode.
3. Set secrets: `firebase functions:secrets:set RAZORPAY_KEY_ID` (etc.)
4. `firebase deploy --only firestore:rules,firestore:indexes,storage,functions,hosting`

## Structure
```
apps/customer-mobile/   Flutter customer app
apps/worker-pwa/        React+Vite installable PWA
apps/admin-dashboard/   React+Vite+TS admin
packages/shared-types/  Domain types, pricing, state machine, assignment scoring, seed data
packages/validation-schemas/  Zod schemas shared by clients + functions
packages/design-tokens/ Brand tokens
functions/              Cloud Functions Gen 2 (TypeScript)
firestore.rules / storage.rules / firestore.indexes.json
docs/                   Architecture, data model, security, workflows, deployment
```
See `docs/` for details. Currency INR (paise), timezone `Asia/Kolkata`.
