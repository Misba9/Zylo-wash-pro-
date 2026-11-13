# ZYLO Admin Control Center — Phase 1 Audit & Implementation Plan

**Project:** wash-pro-7f3b1 · **Brand:** ZYLO  
**Date:** 2026-11-11  
**Status:** Phase 1 complete (audit + plan). Phase 2 in progress.

---

## 1. Existing architecture (preserve)

| App | Path | Stack | Role |
|-----|------|-------|------|
| Customer | `apps/customer-mobile` | Flutter + Firebase | Booking, Razorpay, OTP |
| Worker | `apps/worker-pwa` (`@zylo/field`) | React/Vite/TS | Jobs, checklist, location |
| Admin | `apps/admin-dashboard` | React/Vite/TS | Ops console (ZYLO Control) |
| Website | `apps/website` | React/Vite | Marketing |
| Backend | `functions/` | Cloud Functions Gen 2 | Payments, bookings, FCM, audit |
| Types | `packages/shared-types` | TS | Catalog + status machine |
| Hosting | `hosting/unified` | Static | zyloo.co.in |

**Do not** create a second admin app or duplicate backend. Extend these.

**Firebase:** Auth, Firestore, Functions, Storage, FCM, Hosting — project `wash-pro-7f3b1`.

---

## 2. Maturity gap matrix

| Module | Today | Target | Gap |
|--------|-------|--------|-----|
| Dashboard KPIs | Partial counts; some vanity metrics | Live KPIs + period compare + drill-down | High |
| Analytics / charts | Missing | Aggregated + interactive | High |
| Services CRUD | Edit prices only | Full CRUD, images, categories, order | High |
| Pricing engine | Fragmented (Flutter / CF / Firestore) | Single server quote + snapshot | **Critical** |
| Packages | Hardcoded / mismatched IDs | Firestore `plans` admin CRUD | High |
| Add-ons | Const lists | Firestore `addons` | High |
| Coupons | `WELCOME75` hardcoded | Collection + atomic redeem | High |
| Service areas | Rules + CF check; no admin CRUD | Full area/slots admin | Medium |
| Bookings | Strong | Keep; wire assign via CF | Low–Med |
| Workers | Strong | Performance analytics | Med |
| Customers | Inferred from bookings | Users CRM | Med |
| Payments | CF strong; admin thin | Callables + exports | Med |
| App config | Seeded banner only | Typed config UI | Med |
| Notifications | FCM trigger exists | Admin broadcast center | Med |
| Reports | CSV only | Filtered + Excel | Med |
| RBAC | Rules + demo role switcher | Claims + granular UI | High |
| Audit logs | Implemented | Expand coverage | Low |

---

## 3. Critical inconsistencies (fix first)

1. **Multiple price sources** — Flutter `BookingPrice` (fees/coupon), Firestore `services` (admin seed ₹499…), `shared-types` / Functions `PRICES` (₹299…), customer writes own `priceSnapshot`.
2. **`createPaymentOrder` trusts booking snapshot** — never re-quotes.
3. **Customer booking path** often bypasses `createBooking` callable.
4. **`plans` collection** used by apps but **missing Firestore rules** (catch-all deny).
5. **Admin** mutates Firestore directly — rarely calls Cloud Functions.
6. Vehicle model is hatchback/sedan/suv/luxury; product asks for **5-seater / 7-seater** — map without breaking history.

---

## 4. Proposed catalog schema (extend, don’t duplicate)

New / extended collections (reuse names where present):

| Collection | Purpose |
|------------|---------|
| `serviceCategories` | Unlimited categories (exterior, detailing, …) |
| `services` | Extended: categoryId, images, duration, seat prices, featured, sortOrder, active/archived |
| `addons` | Compatible services/vehicles, pricePaise, duration |
| `plans` | Subscription packages (fix rules!) |
| `coupons` | Codes, limits, validity, atomic `redemptions` subcollection |
| `pricingRules` | Weekend/peak/express/area/promo with priority + validity |
| `serviceAreas` | Areas, hours, slots, express, restrictions |
| `appConfig` | Versioned customer/worker/global docs |
| `banners` | Optional; or embed in `appConfig` |
| `analyticsDaily` / `analyticsMonthly` | Scheduled aggregates |
| `adminAuditLogs` | Prefer extend existing `auditLogs` |

**Money:** integer paise · **Currency:** INR · **TZ:** Asia/Kolkata  
**Bookings:** immutable `priceSnapshot` forever.

**Seat pricing:** store `pricePaise.seater5` / `pricePaise.seater7`; map legacy categories:
- 5-seater ← hatchback, sedan  
- 7-seater ← suv, luxury  

---

## 5. Phased delivery (locked)

| Phase | Scope | Exit criteria |
|-------|--------|----------------|
| **1** | Audit + plan | This document |
| **2** | Services, pricing engine, packages, add-ons | Admin CRUD; `quoteBookingPrice` CF; Flutter/worker read Firestore |
| **3** | Coupons, areas, app config | Server coupon redeem; area validation; config listeners |
| **4** | Wire customer + worker apps | No rebuild for catalog/price/config changes |
| **5** | Bookings/customers/workers/finance admin depth | CF for assign/refund; CRM; verified payments |
| **6** | Analytics aggregates + reports | Real data only; exports |
| **7** | RBAC + rules + audit | Claims enforced; no self-elevation |
| **8** | Cross-app integration tests | Acceptance criteria §21 |

---

## 6. Phase 2 immediate build order

1. Types + Firestore rules for `plans`, `addons`, `coupons`, `serviceCategories`.
2. Server `quoteBookingPrice` / harden booking create to use Firestore catalog + fees from `appConfig`.
3. Admin modules: Services, Pricing calculator, Packages, Add-ons (ZYLO brand tokens).
4. Seed + migrate existing service docs to seat-class prices (paise).
5. Flutter: load catalog + quote from server (fallback offline only).

---

## 7. Non-negotiables

- Preserve Auth, Razorpay verify, cash bookings, historical snapshots.
- No dummy analytics.
- No secrets in public `appConfig`.
- No frontend-only permission checks.
- Do not mark platform “complete” until §21 acceptance flows pass end-to-end.
