# WashPro Customer App — Dynamic Functionality Audit (21 Oct 2026)

**Scope:** `apps/customer-mobile` (Flutter, single-file UI in `lib/main.dart`),
Firebase project `wash-pro-7f3b1` (Auth + Firestore, rules deployed, Spark plan —
Cloud Functions code exists in `functions/` but **not deployed**, Blaze required).

## Architecture found

| Layer | Before | After this pass |
|---|---|---|
| UI | `lib/main.dart` (~445 lines, all screens) | Same screens/design (preserved) |
| Models | Ad-hoc classes in `main.dart` | `lib/data/app_data.dart` (typed models + `AppState`) |
| Data source | `LiveData` statics inside `main.dart` | `lib/data/repository.dart` (`WashProRepository`, Firestore-only) |
| State | Global `DemoStore` with fabricated seed user data | `AppState`: session profile + user-owned lists, **empty until loaded** |
| Catalog | Hardcoded `services`/`plans` consts | Firestore `services` + `plans` collections, local constants only as offline fallback |
| Backend ops | Direct Firestore writes (rules-constrained) | Same, documented; Functions remain the Blaze upgrade path (`docs/FIREBASE_WASH_PRO.md`) |

## Findings (static ❌ / partial ⚠️ / dynamic ✅ before this pass)

| # | Area | Finding | Status before |
|---|---|---|---|
| 1 | Greeting | "Hi, Riya" hardcoded (`DemoStore.userName` const) | ❌ |
| 2 | Profile | `users/{uid}` never read/written; edit button = toast only; "MEMBER SINCE 2024" fake | ❌ |
| 3 | Service address | Fixed Prestige Lakeside address; home card always `addresses.first` | ❌ |
| 4 | Banner | Static asset + copy, not configurable | ⚠️ (CTA worked) |
| 5 | Wash now tile | "Slots from 10:30 AM" fixed claim | ❌ |
| 6 | Subscribe tile | "Save up to 34%" fixed | ❌ (34 happened to match a plan) |
| 7 | Upcoming wash | Fabricated seed booking `WP-2405-1847` shown before/without login data | ❌ |
| 8 | Garage | Fabricated Tata Nexon + Honda City pre-seeded; **auto-inserted into new users' Firestore** on first login | ❌ |
| 9 | Services/prices | Local constants; Firestore `services` (admin-managed) ignored | ⚠️ |
| 10 | Slots | "Full" slots faked via hash of date; all times "available" claim | ❌ |
| 11 | Booking create | Worked + Firestore write ✅, but no double-tap guard, ID from shared counter | ⚠️ |
| 12 | Online payment | Demo Razorpay sheet marked booking **paid** on tap — fake verification | ❌ |
| 13 | Plans | Local constants; Subscribe instantly "activated" + fake recurring mandate toast; pause/skip/cancel local-only | ❌ |
| 14 | Notifications | 3 fabricated records; no read state, no backend | ❌ |
| 15 | Payments page | Derived from bookings ✅ but bookings were fabricated | ⚠️ |
| 16 | Support | Ticket → Firestore ✅ (done previously) | ✅ |
| 17 | Vehicles/Addresses CRUD | Synced ✅, but no edit, no set-primary, delete without confirmation | ⚠️ |
| 18 | Session | App always restarted at login screen even with valid Firebase session | ❌ |
| 19 | Booking detail | "Simulate expert progress" demo button mutated status locally | ❌ |
| 20 | Delete account | Dialog dismissed only — fake flow | ❌ |
| 21 | Home states | No loading/empty/error states; crashes if lists empty (`vehicles[0]`) | ❌ |

## Implementation plan (executed)

1. **Data layer:** extract models to `lib/data/app_data.dart`; Firestore access to
   `lib/data/repository.dart` (`WashProRepository`). `AppState` starts **empty** —
   no fabricated user, vehicle, address, booking, subscription or notification.
2. **Session:** restore Firebase session on launch (splash gate → load → Shell);
   load/create `users/{uid}` profile; greeting/address/avatar from profile.
3. **Catalog:** load `services`, `plans`, `appConfig/homeBanner` from Firestore
   (admin seed now writes all three); local constants remain only as offline fallback.
4. **Home:** stateful, bookings stream, loading skeleton, empty states with CTAs,
   computed next-slot + computed max plan saving, selected (default) address persisted
   via `addresses.isDefault`, garage empty/primary states.
5. **Booking:** guards for missing vehicle/address, real time-based slot availability,
   double-submit guard, idempotent booking IDs, honest payment state
   (`awaiting_payment` until a server verifies — Razorpay sheet no longer fakes success;
   cash flow unchanged).
6. **Plans:** subscribe creates `pending_payment` subscription (no fake mandate);
   pause/resume/skip/change-time/cancel sync to Firestore (rules extended for `timeWindow`).
7. **Notifications:** loaded from `notifications` (recipientUid), mark-read/mark-all-read
   persisted, tap opens linked booking.
8. **Profile:** edit name → Firestore; member-since from profile `createdAt`;
   delete account = recorded deletion request ticket + honest copy.
9. **Rules:** subscriptions `timeWindow` added to customer-updatable keys; redeployed.
10. **Tests:** model/repository-logic unit tests (pricing from Firestore-shaped maps,
    savings, next-slot, idempotency), widget test for auth + empty home states.

## Known blockers (documented, not faked)

- **Cloud Functions not deployed** (Spark plan) → no server-side price re-validation,
  Razorpay order/verify, assignment engine. Client writes remain rules-constrained
  (owner-scoped, whitelisted fields/statuses). Upgrade path: Blaze → deploy `functions/`.
- **Phone provider** must be enabled in Firebase Console (cannot be done via CLI).
- **FCM push** requires APNs key (iOS) / Play services device testing; in-app
  notification records are live, push transport is a follow-up.
- **Vehicle images / Storage** not enabled in this project; vehicle image upload is
  intentionally absent rather than faked.

## Screen checklist

- [x] Auth (Email + Google only — Phone OTP removed on request, session restore, new-user basic-details onboarding)
- [x] Home (profile, address, banner config, next slot, savings, upcoming stream, garage, services)
- [x] Booking flow ×4 steps (guards, real slots, idempotent create, honest payment)
- [x] Success (status reflects awaiting_payment vs confirmed/cash)
- [x] Bookings (refresh, reschedule/cancel synced)
- [x] Booking detail (live fields, verify+rating synced, demo-simulate button removed)
- [x] Plans (Firestore catalog, pending_payment subscribe, synced lifecycle actions)
- [x] Profile (edit, member-since, deletion request, sign-out)
- [x] Vehicles (add/delete confirm/set-primary synced, empty state)
- [x] Addresses (add/delete/set-default synced, selected persisted)
- [x] Payments & refunds (real booking payment states, empty state)
- [x] Notifications (Firestore, read state, deep-link to booking)
- [x] Support (Firestore tickets)
