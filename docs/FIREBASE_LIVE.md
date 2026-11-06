# WashPro — Live Firebase Setup (project: `washpro-hyd`)

> **Note (20 Oct 2026):** The primary project is now **`wash-pro-7f3b1`** — see
> `docs/FIREBASE_WASH_PRO.md`. This document remains valid for the `washpro-hyd`
> staging project (the hosted URLs below still run against it).

Everything code-side is done. Firestore + rules + indexes are deployed and all three
apps are wired. These are the **one-time console steps only you can do** (they need
your Google account / billing), then the pilot goes fully live.

## ✅ Already done (by CLI)

- Firebase project **`washpro-hyd`** created; apps registered (Admin web, Worker web, Customer Android/iOS/Web)
- Firestore database created; `firestore.rules` + `firestore.indexes.json` **deployed**
- All apps wired to live Firestore with real-time sync; demo data remains as automatic fallback

## 1️⃣ Enable Authentication (2 minutes)

Open https://console.firebase.google.com/project/washpro-hyd/authentication

1. Click **Get started**
2. **Sign-in method → Email/Password → Enable → Save**
3. **Sign-in method → Phone → Enable → Save**
4. **Users → Add user**: `admin@washpro.in` / `WashPro@123`  ← your ops admin login
5. **Settings → "Phone numbers for testing"** add these (OTP for all: `123456`):

   | Number | Who |
   |---|---|
   | `+91 98765 43210` | Riya (customer app) |
   | `+91 98500 00001` | Ramesh Kumar (worker w1) |
   | `+91 98500 00002` | Suresh Yadav (worker w2) |
   | `+91 98500 00003` | Mohd. Imran (worker w3) |
   | `+91 98500 00004` | Anil Verma (worker w4) |
   | `+91 98500 00005` | Kiran Reddy (worker w5) |

## 2️⃣ Grant the admin role (1 minute)

Firestore roles are granted via an `admins/{uid}` document (the security rules accept it).

1. Authentication → Users → copy the **UID** of `admin@washpro.in`
2. Firestore Database → **Start collection** → ID `admins` → Document ID = that UID, fields:
   - `email` = `admin@washpro.in`
   - `role` = `super_admin`

## 3️⃣ Seed the pilot data (30 seconds)

1. Open the Admin app (hosted URL below, or `npm run dev:admin`)
2. Sign in with `admin@washpro.in` / `WashPro@123`
3. In the sidebar footer click **🌱 Seed Hyderabad pilot data**

This writes services, 6 workers, bookings, payments, subscriptions & tickets into Firestore.

## 4️⃣ Verify the live loop

| Step | App | Action |
|---|---|---|
| 1 | Admin | Bookings → open an unassigned booking → Assign **Suresh Yadav** |
| 2 | Worker | Sign in `+91 98500 00002` / OTP `123456` → the job appears instantly → run it to *pending verification* |
| 3 | Customer | Sign in `98765 43210` / OTP `123456` → book a wash → watch it appear in Admin live |
| 4 | Customer | Booking details → rate → **Verify completion** → Admin & Worker update in real time |

## 5️⃣ Cloud Functions — needs Blaze (your billing)

Functions are built and compile clean, but Firebase requires the **Blaze plan** to deploy them:

1. Upgrade: https://console.firebase.google.com/project/washpro-hyd/usage/details (set a ₹500 budget alert)
2. Then run:

```bash
firebase deploy --only functions --project washpro-hyd
firebase functions:secrets:set RAZORPAY_KEY_ID
firebase functions:secrets:set RAZORPAY_KEY_SECRET
firebase functions:secrets:set RAZORPAY_WEBHOOK_SECRET
```

Until then, the apps talk to Firestore directly under the deployed security rules
(customer/worker writes are constrained to their own documents and allowed fields).
Once functions are live, prefer routing mutations through them per `docs/security.md`.

## Running the apps

```bash
npm run dev:admin     # http://localhost:5173  (admin@washpro.in)
npm run dev:worker    # http://localhost:5174  (worker phone OTP)
cd apps/customer-mobile && flutter run        # customer app
```

- Removing `apps/*/.env.local` switches the web apps back to **Demo Mode** (local seed data, no Firebase).
- The customer app auto-falls back to demo OTP `123456` if Firebase Auth isn't reachable.

## Production checklist (later)

- [ ] Upgrade to Blaze, deploy functions, set Razorpay secrets (above)
- [ ] Add Android SHA-1/SHA-256 fingerprints (Project settings → Customer Android) for phone auth on real devices
- [ ] Create `washpro-prod` project and repeat this guide for production
- [ ] Enable App Check + set budget alerts
