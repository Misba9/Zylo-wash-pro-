# WashPro — Primary Firebase Project: `wash-pro-7f3b1`

Set up following the official **Firebase agent skills** (`firebase-basics`,
`firebase-auth-basics`, `firebase-firestore`, `firestore-rules-creation`) —
installed in `.agents/skills/`. Firebase MCP server configured in `.cursor/mcp.json`.

> The earlier `washpro-hyd` project remains as the `staging` alias (see
> `docs/FIREBASE_LIVE.md`). **`wash-pro-7f3b1` is now the default/primary.**

## Registered apps (project number `832079032419`)

| App | App ID |
|---|---|
| WashPro Customer (Android, `com.washpro.customer`) | `1:832079032419:android:db186e57ff6db912f5c856` |
| WashPro Customer iOS (`com.washpro.customer`) | `1:832079032419:ios:9a3edf7344b37d42f5c856` |
| WashPro Customer Web | `1:832079032419:web:ba8ba43729059d22f5c856` |
| WashPro Admin (Web) | `1:832079032419:web:b4d918791a64453cf5c856` |
| WashPro Worker (Web) | `1:832079032419:web:ad5825b9390f88adf5c856` |

Config files in codebase:

- `apps/customer-mobile/android/app/google-services.json` (via `apps:sdkconfig`)
- `apps/customer-mobile/ios/Runner/GoogleService-Info.plist`
- `apps/customer-mobile/lib/firebase_options.dart` (web/android/ios)
- `apps/admin-dashboard/.env.local`, `apps/worker-pwa/.env.local` (web app IDs)

Android SHA fingerprints (debug keystore) registered via `apps:android:sha:create`:

- SHA-1: `F0:48:BE:C1:13:E1:98:E4:62:6D:FF:E1:61:B1:DB:FF:92:B8:D7:AB`
- SHA-256: `58:3E:31:0A:A0:9F:3D:0F:BE:78:8F:F5:87:E0:57:F4:59:A4:C7:C5:C5:08:15:71:70:2B:22:C1:C6:72:11:78`

(Add your release keystore fingerprints the same way before Play Store upload.)

## Authentication

Enabled via `firebase.json` → `auth.providers` + `npx -y firebase-tools@latest deploy --only auth`:

- ✅ **Email/Password** — enabled
- ✅ **Google Sign-In** — enabled (OAuth brand "WashPro"; web client auto-created)
- ⏳ **Phone** — per the `firebase-auth-basics` skill, Phone can only be enabled in the
  Console: https://console.firebase.google.com/project/wash-pro-7f3b1/authentication/providers
  → **Phone → Enable**, then add test numbers `+91 98765 43210` and
  `+91 98500 00001`–`005` with OTP `123456`.

Client implementation (`apps/customer-mobile/lib/main.dart` → `AuthService`,
following the skill's Flutter guide for `google_sign_in` 7.x):

- Email sign-in / sign-up (Phone OTP auth was removed from the customer app on request)
- "Continue with Google" (`authenticate()` on mobile, `signInWithPopup` on web)
- Sign-out clears Google + Firebase sessions

**Worker PWA (`apps/worker-pwa`): Email/Password ONLY** — Login + Register
(full name, email, password; no mobile number, no OTP). Registering creates a
`workers/{uid}` profile with `status: "pending"`; an admin approves it in the
Admin app (Workers page) before jobs can be assigned. Firestore rules permit
this one self-registration write (own uid + own email + pending only).

Admin ops login: create the admin user in Console (Authentication → Users →
`admin@washpro.in`), then add `admins/{uid}` in Firestore with `role: "super_admin"`,
then use **Seed Hyderabad pilot data** in the Admin app.

## Firestore

- Database auto-provisioned on first rules deploy; `firestore.rules` +
  `firestore.indexes.json` **deployed** to `wash-pro-7f3b1`.
- Re-deploy anytime: `npx -y firebase-tools@latest deploy --only firestore --project wash-pro-7f3b1`

## Commands (per firebase-basics skill, always via npx)

```bash
npx -y firebase-tools@latest use                # active: wash-pro-7f3b1
npx -y firebase-tools@latest apps:list --project wash-pro-7f3b1
npx -y firebase-tools@latest deploy --only auth # after editing firebase.json providers
cd apps/customer-mobile && flutter run          # Android: com.washpro.customer
```

## Hosting (live)

| App | URL |
|---|---|
| Admin Dashboard | https://wash-pro-admin.web.app |
| Worker PWA | https://wash-pro-worker.web.app |
| Customer App (web) | https://wash-pro-customer.web.app |

Multi-site targets (`admin` / `worker` / `app`) are mapped in `.firebaserc` for
both `wash-pro-7f3b1` (primary) and `washpro-hyd` (staging). Redeploy with:

```bash
npx -y firebase-tools@latest deploy --only hosting --project wash-pro-7f3b1
```

## Still pending (yours)

1. **Enable Phone provider** in Console (link above) + test numbers.
2. **Blaze plan** for Cloud Functions: https://console.firebase.google.com/project/wash-pro-7f3b1/usage/details
   → then `npx -y firebase-tools@latest deploy --only functions`.
3. Change the Google `supportEmail` in `firebase.json` if it shouldn't be
   `misbahuddinahmed157@gmail.com`.
