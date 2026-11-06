# WashPro — Play Store & Go-Live Checklist

App: **WashPro** · package `com.washpro.customer` · version `1.0.0+1`
Backend: Firebase project `wash-pro-7f3b1` (Auth + Firestore, rules deployed)

## ✅ Done in codebase

- [x] Release signing: `android/upload-keystore.jks` (alias `upload`) + `android/key.properties` — **both gitignored, never commit**
  - ⚠️ **Back up `upload-keystore.jks` + passwords (`key.properties`) somewhere safe NOW.** Losing them means you can never update the app on Play.
  - Upload-key SHA-1 (register in Firebase after Play enrollment): get it with
    `keytool -list -v -keystore android/upload-keystore.jks -alias upload`
  - Also add the **Play App Signing** SHA-1 from Play Console → Release → Setup → App signing.
- [x] App icon (all densities + adaptive) from `assets/icon/app_icon.png`; Play listing icon: `assets/icon/play_store_512.png`
- [x] App label "WashPro", INTERNET permissions, R8 minify + proguard rules
- [x] Privacy Policy + Terms pages shipped in web build:
  - Privacy: https://wash-pro-customer.web.app/privacy.html
  - Terms: https://wash-pro-customer.web.app/terms.html
- [x] Auth: Email/Password ✅ live, Google ✅ live, Phone (code ready)
- [x] Fully dynamic: bookings, vehicles, addresses, subscriptions, tickets, cancel/reschedule/verify all sync to Firestore in real time

## 🙋 Your remaining steps (in order)

### 1. Firebase Console (5 min) — https://console.firebase.google.com/project/wash-pro-7f3b1
- [ ] Authentication → Providers → **Phone → Enable**; add test numbers `+91 98765 43210`, `+91 98500 00001`–`005` (OTP `123456`)
- [ ] Authentication → Users → add `admin@washpro.in` (choose a strong password)
- [ ] Firestore → `admins/{that-uid}` doc: `email`, `role: "super_admin"` → then Admin app → **Seed Hyderabad pilot data**

### 2. Build the release bundle ✅ DONE (21 Oct 2026)
- `build/app/outputs/bundle/release/app-release.aab` (55.4 MB, signature verified with jarsigner)
- Rebuild anytime: `cd apps/customer-mobile && flutter build appbundle --release`

### 3. Play Console — https://play.google.com/console ($25 one-time developer account)
- [ ] Create app → name **WashPro**, default language en-IN, App, Free
- [ ] Upload `app-release.aab` to **Internal testing** first → test on a real phone (Phone OTP + Google sign-in)
- [ ] Store listing: icon `assets/icon/play_store_512.png`, short description
      "Doorstep car wash & detailing in Hyderabad — book, track and pay in minutes."
      Feature graphic 1024×500 + 4–8 phone screenshots (use the app)
- [ ] Privacy policy URL: https://wash-pro-customer.web.app/privacy.html
- [ ] Data safety form: collects Phone, Email, Name, Address, Vehicle info, Payment info (processed by Razorpay) — no data shared for ads, encrypted in transit, deletion via support@washpro.in
- [ ] Content rating questionnaire (target: Everyone), target age 18+
- [ ] Add Play App Signing SHA-1/SHA-256 to Firebase (Project settings → Android app → Add fingerprint), re-download `google-services.json`
- [ ] Promote Internal → Production (rollout 20% → 100%)

### 4. Money & scale (when ready)
- [ ] Upgrade to **Blaze** → `npx -y firebase-tools@latest deploy --only functions --project wash-pro-7f3b1`
- [ ] Razorpay live keys → `firebase functions:secrets:set RAZORPAY_KEY_ID` (+ SECRET, WEBHOOK_SECRET)
- [ ] Budget alerts (₹500) + App Check enablement

## Live URLs
- Admin: https://wash-pro-admin.web.app · Worker: https://wash-pro-worker.web.app · Customer: https://wash-pro-customer.web.app
- Redeploy: `npx -y firebase-tools@latest deploy --only hosting --project wash-pro-7f3b1`

## Rules note
I've set up prototype Security Rules to keep the data in Firestore safe. They are designed to be secure because every collection is owner/role-scoped and customer writes are limited to whitelisted fields and statuses. However, you should review and verify them before broadly sharing your app. If you'd like, I can help you harden these rules.
