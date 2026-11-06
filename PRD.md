# WashPro — Product Requirements Document & Technical Implementation Plan

**Version:** 1.0  
**Status:** Implementation-ready specification  
**Initial market:** Hyderabad, Telangana, India  
**Product:** Doorstep car washing and detailing platform  
**Backend:** Firebase  
**Timezone:** `Asia/Kolkata`  
**Currency:** INR (₹)

---

## 1. Executive Summary

WashPro is a doorstep car-washing and detailing platform that connects customers with verified washing workers at their home, apartment parking, office or other supported parking locations.

The platform consists of three applications:

1. **Customer mobile app:** Flutter.
2. **Worker application:** React, Vite and installable Progressive Web App (PWA).
3. **Admin dashboard:** React, Vite and TypeScript.

Firebase will provide authentication, database, file storage, server-side business logic, notifications, scheduling, monitoring and application protection.

The initial release will support:

- Multiple saved vehicles and addresses.
- Instant and scheduled washing.
- Body wash, interior cleaning and deep cleaning.
- Prepaid subscriptions and supported recurring billing.
- Hybrid worker assignment: automatic recommendations and administrator control.
- Online payment and cash collection.
- Worker navigation and location sharing during the active trip to a booking.
- Before-and-after photos and customer completion verification.
- Operational management, refunds, support and reporting.

### Product objectives

- Make booking a wash simple enough to complete in a few steps.
- Provide predictable, reliable service scheduling.
- Help workers complete jobs with minimal app navigation.
- Give administrators visibility into every booking and exception.
- Encourage repeat customers through subscription plans.
- Maintain accurate payment, visit-credit and worker-payout records.

## 2. Confirmed Product Decisions

| Decision | Final specification |
|---|---|
| Launch market | Hyderabad |
| Customer app | Flutter |
| Worker interface | Mobile-first PWA |
| Admin dashboard | React + Vite |
| Backend | Firebase |
| Database | Cloud Firestore |
| Authentication | Firebase Authentication |
| Business logic | Cloud Functions for Firebase, 2nd gen |
| Media storage | Cloud Storage for Firebase |
| Push notifications | Firebase Cloud Messaging |
| Worker assignment | Hybrid: automated recommendations plus admin control |
| Payment methods | Online payments and cash |
| Subscriptions | Prepaid plans and recurring billing |
| Worker location | Only during an active trip to an assigned booking |
| Maps | Google Maps Platform |
| Payment gateway | Razorpay integration, subject to merchant onboarding and supported payment features |
| Initial currency | INR |
| Initial language | English; architecture should allow additional languages |

---

# 3. System Architecture

## 3.1 High-level architecture

```text
CUSTOMER APP             WORKER PWA             ADMIN DASHBOARD
Flutter                  React + Vite           React + Vite
    |                        |                       |
    +------------------------+-----------------------+
                             |
                    Firebase SDKs / HTTPS
                             |
    +-------------------------------------------------------+
    |                   FIREBASE BACKEND                    |
    |                                                       |
    | Firebase Authentication                              |
    | Cloud Firestore                                      |
    | Cloud Storage                                        |
    | Cloud Functions Gen 2                                |
    | Firebase Cloud Messaging                             |
    | Cloud Scheduler / scheduled functions                |
    | Firebase App Check                                   |
    | Firebase Crashlytics / Analytics / Cloud Logging     |
    +-------------------------------------------------------+
                             |
                 TRUSTED SERVER-SIDE OPERATIONS
                             |
       +---------------------+--------------------+
       |                     |                    |
   Razorpay API          Google Maps          Email/SMS
   and webhooks          Platform             providers
```

The browser and mobile applications may read or update only the data permitted by Security Rules. Sensitive operations must go through authenticated, validated Cloud Functions.

### Architecture principles

1. Firestore is the source of truth for bookings, assignments and subscription records.
2. Cloud Functions own privileged state transitions and financial operations.
3. Clients must never decide authoritative prices, payment success or worker permissions.
4. Firestore transactions protect concurrent assignments and visit-credit changes.
5. All retriable financial and scheduling operations must be idempotent.
6. Push notifications are delivery mechanisms, not the source of truth.
7. Every sensitive administrative action must be auditable.

## 3.2 Firebase services

| Service | Usage |
|---|---|
| Firebase Authentication | Customer, worker and administrator identity |
| Cloud Firestore | Core application database |
| Cloud Functions Gen 2 | Booking, assignment, payment and subscription logic |
| Cloud Storage for Firebase | Before/after photos and permitted documents |
| Firebase Cloud Messaging | Push notifications |
| Cloud Scheduler | Recurring visits, reminders and reconciliation jobs |
| Firebase App Check | Reduce unauthorized access from unofficial clients |
| Firebase Crashlytics | Flutter crash reporting |
| Firebase Analytics | Customer journey and product usage |
| Cloud Logging and Monitoring | Backend errors, alerts and operational diagnostics |
| Firebase Emulator Suite | Local integration testing |

Use a Firebase billing plan that supports the production services and usage required. Establish budget alerts and cost monitoring before opening the service to customers.

---

# 4. User Roles and Permissions

## 4.1 Customer

- Manage own profile, vehicles and addresses.
- View services and prices.
- Book and cancel eligible services.
- Purchase and manage subscriptions.
- View own payment history.
- Track the assigned worker during an active trip.
- View service evidence and verify completion.
- Submit ratings and support requests.

## 4.2 Worker

- Manage permitted profile fields.
- Set availability when approved.
- View assigned jobs.
- Accept or acknowledge eligible assignments.
- Navigate to the customer's service location.
- Start a trip and share location during that trip.
- Check in, upload photos and complete checklists.
- Request customer verification.
- View own earnings and job history.

## 4.3 Operations administrator

- View and manage bookings.
- Review automated worker recommendations.
- Assign and reassign workers.
- Resolve delays, cancellations and service exceptions.
- Manage worker schedules and service areas.

## 4.4 Finance administrator

- Review transactions and payment exceptions.
- Reconcile cash collections.
- Process authorized refunds.
- Review worker earnings and payout records.

## 4.5 Super administrator

- Configure services, prices, roles and service areas.
- Manage privileged access.
- Review audit logs.
- Configure operational policies.

Use separate permissions for operations, support and finance. Do not grant unrestricted administrator privileges to every staff member.

---

# 5. Customer App Requirements

## 5.1 Authentication

- Mobile number and OTP authentication.
- Secure session persistence.
- Profile onboarding.
- Logout and account deletion.
- OTP retry limits and expiration.
- Appropriate handling of network failures.

## 5.2 Home screen

Display:

- Greeting and notification indicator.
- Selected service address.
- Primary Book a Wash action.
- Wash Now shortcut.
- Subscribe shortcut.
- Saved vehicles.
- Upcoming booking.
- Active subscription.
- Recent bookings.

Only show confirmed booking statuses after receiving authoritative backend data.

## 5.3 Vehicle management

Support multiple vehicles.

```text
Vehicle
- id
- ownerUid
- nickname
- category
- make
- model
- color
- registrationNumber
- isDefault
- createdAt
- updatedAt
```

Vehicle categories and pricing eligibility must be configurable. Only the vehicle owner or an authorized administrator may modify vehicle records.

## 5.4 Address management

```text
Address
- id
- ownerUid
- label
- recipientName
- contactPhone
- addressLine
- locality
- city
- postalCode
- apartment
- building
- flatNumber
- parkingSlot
- accessInstructions
- latitude
- longitude
- serviceAreaId
- createdAt
- updatedAt
```

Support saved addresses and map-pin placement. Validate service availability before accepting a booking.

## 5.5 Service catalog

Initial services:

**Body Wash**
- Exterior cleaning.
- Configurable service inclusions.
- Vehicle-specific pricing and duration.

**Interior Cleaning**
- Vacuuming and interior surface cleaning.
- Configurable inclusions and exclusions.

**Deep Cleaning**
- Detailed cleaning checklist.
- Longer service duration.
- Optional add-ons.

All prices and service availability must be retrieved from authoritative backend records.

## 5.6 Instant booking

Flow:

1. Select vehicle.
2. Select service.
3. Select address.
4. Check service availability.
5. Review price and estimated arrival.
6. Choose online payment or permitted cash payment.
7. Confirm the booking.
8. View confirmation and assigned worker when available.

The backend must prevent duplicate bookings and concurrent overbooking.

## 5.7 Scheduled booking

- Choose a date and available slot.
- View estimated service duration.
- Receive confirmation.
- Reschedule or cancel according to policy.
- Receive notifications about assignment and schedule changes.

The server must validate the slot again when the booking is submitted.

## 5.8 Subscription management

Customers can:

- Purchase a prepaid plan.
- Enrol in an eligible recurring plan.
- View upcoming visits and remaining credits.
- Skip eligible visits.
- Pause or resume where permitted.
- Change a schedule.
- View renewal status.
- Cancel a plan under the applicable policy.

The UI must clearly distinguish prepaid visit credits from automatic recurring billing.

---

# 6. Worker PWA Requirements

## 6.1 Worker dashboard

Display:

- Today's schedule.
- Next job.
- Assigned jobs.
- Active trip.
- In-progress jobs.
- Completed jobs.
- Pending actions.
- Earnings summary.

## 6.2 Job workflow

```text
Assignment received
        |
        v
Review booking
        |
        v
Start trip
        |
        v
Navigate to location
        |
        v
Arrive and check in
        |
        v
Upload before photos
        |
        v
Perform service checklist
        |
        v
Upload after photos
        |
        v
Request customer verification
        |
        v
Complete authorized workflow
```

Workers must not be able to bypass mandatory steps by editing Firestore documents directly.

## 6.3 Location tracking

Tracking is enabled only while the worker is traveling to an assigned booking.

Requirements:

- Request location permission at the appropriate moment.
- Start a trip through an authenticated backend operation.
- Accept location updates only from the assigned worker during the valid trip.
- Store the last known coordinates and update timestamp.
- Display the last update time to the customer.
- Stop tracking when arrival is recorded, the trip is cancelled or the assignment is revoked.
- Reject stale or invalid updates.
- Limit update frequency to balance usefulness and cost.

A reasonable initial target is one update every 15–30 seconds while the worker is actively traveling, subject to testing and device limitations.

Because the worker interface is a PWA, continuous tracking cannot be guaranteed when the browser is suspended or closed. The interface must communicate stale location states honestly.

## 6.4 Job evidence

Each job should support:

- Required before photos.
- Required after photos.
- Service checklist.
- Upload progress.
- Retry after network failure.
- Authorized evidence review.

Photos must be stored privately. Firestore contains their metadata and Storage paths rather than public image URLs.

## 6.5 PWA requirements

- Installable manifest.
- HTTPS.
- Mobile-responsive layout.
- Appropriate service worker caching.
- Online/offline status.
- Safe retry mechanisms.
- Accessible touch controls.
- No caching of sensitive customer records in public or shared browser caches.

---

# 7. Admin Dashboard Requirements

## 7.1 Dashboard overview

Show:

- Bookings today.
- Unassigned bookings.
- Active jobs.
- Completed and cancelled jobs.
- Active subscriptions.
- Payment exceptions.
- Worker availability.
- Revenue and refunds.
- Open support tickets.
- Customer satisfaction.

## 7.2 Booking management

Administrators can:

- Search and filter bookings.
- Inspect booking timelines.
- Review assignment recommendations.
- Assign and reassign workers.
- Reschedule or cancel eligible bookings.
- Review job evidence.
- Resolve exceptions.
- View payment and refund states.
- Add internal notes.

## 7.3 Hybrid worker assignment

The backend should recommend eligible workers based on:

1. Worker approval and active status.
2. Supported service area.
3. Service and vehicle eligibility.
4. Availability and working hours.
5. Existing job conflicts.
6. Estimated travel distance.
7. Workload and expected service duration.
8. Reliability and service quality, when sufficient data exists.

The system generates a ranked recommendation. An authorized administrator may confirm or override it, with an audit reason for exceptional overrides.

For the initial release, use a straightforward scoring system. Do not introduce expensive route optimization until actual operational data justifies it.

## 7.4 Service and pricing management

Administrators can configure:

- Service categories.
- Prices by vehicle type.
- Duration and checklist.
- Service area eligibility.
- Add-ons and discounts.
- Subscription plans.
- Cancellation policies.
- Cash-payment eligibility.

Every confirmed booking must preserve its agreed price snapshot.

## 7.5 Finance and reporting

Support:

- Online payment reconciliation.
- Cash collection reconciliation.
- Refund records.
- Worker earnings and payout records.
- Booking and subscription reports.
- CSV exports.
- Audit logs.

Revenue reporting must distinguish booked value, collected payments, refunds, pending transactions and net operating revenue.

---

# 8. Firestore Data Model

Use the following top-level collections. Add subcollections where unbounded histories or event records require them.

| Collection | Purpose |
|---|---|
| `users` | Customer profiles |
| `workers` | Worker profiles and approval status |
| `vehicles` | Saved vehicles |
| `addresses` | Saved service addresses |
| `services` | Service catalog |
| `serviceAreas` | Hyderabad coverage zones |
| `pricingRules` | Authoritative pricing |
| `bookings` | Booking and job state |
| `subscriptions` | Customer subscription records |
| `subscriptionOccurrences` | Individual recurring visits |
| `payments` | Payment attempts and confirmed transactions |
| `refunds` | Refund lifecycle |
| `workerShifts` | Worker availability and working hours |
| `workerAssignments` | Assignment history and decisions |
| `workerLocations` | Latest active-trip location |
| `jobEvidence` | Photo metadata and checklist results |
| `reviews` | Customer ratings |
| `notifications` | In-app notification history |
| `supportTickets` | Complaints and resolutions |
| `payouts` | Worker payout records |
| `auditLogs` | Sensitive action history |
| `webhookEvents` | Processed gateway event identifiers |
| `idempotencyKeys` | Duplicate-operation prevention |
| `appConfig` | Non-secret application configuration |

## 8.1 Booking schema

```typescript
type BookingStatus =
  | "requested"
  | "awaiting_payment"
  | "confirmed"
  | "assigned"
  | "en_route"
  | "arrived"
  | "in_progress"
  | "pending_verification"
  | "completed"
  | "cancelled"
  | "under_review";

interface Booking {
  id: string;
  customerUid: string;
  vehicleId: string;
  addressId: string;
  serviceId: string;
  serviceAreaId: string;

  assignedWorkerUid: string | null;

  bookingType: "instant" | "scheduled" | "subscription";
  status: BookingStatus;

  scheduledAt: FirebaseFirestore.Timestamp;
  estimatedDurationMinutes: number;

  priceSnapshot: {
    currency: "INR";
    subtotalPaise: number;
    discountPaise: number;
    taxPaise: number;
    totalPaise: number;
    pricingVersion: string;
  };

  paymentMethod: "online" | "cash";
  paymentStatus:
    | "not_required"
    | "pending"
    | "authorized"
    | "paid"
    | "failed"
    | "refund_pending"
    | "partially_refunded"
    | "refunded";

  subscriptionId: string | null;
  occurrenceId: string | null;

  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
  completedAt: FirebaseFirestore.Timestamp | null;
}
```

This is an initial schema, not a complete application type definition. Add cancellation metadata, address snapshots, service snapshots, assignment history references and other fields required by the final workflows.

## 8.2 Subscription schema

```typescript
interface Subscription {
  id: string;
  customerUid: string;
  vehicleId: string;
  addressId: string;
  planId: string;

  billingMode: "prepaid" | "recurring";
  status:
    | "pending_payment"
    | "active"
    | "paused"
    | "past_due"
    | "cancelled"
    | "expired";

  schedule: {
    frequency: "daily" | "alternate_days" | "weekly" | "custom";
    weekdays?: number[];
    timeWindow: string;
    timezone: "Asia/Kolkata";
  };

  visitBalance: number;
  currentPeriodStart: FirebaseFirestore.Timestamp;
  currentPeriodEnd: FirebaseFirestore.Timestamp;

  nextRenewalAt: FirebaseFirestore.Timestamp | null;
  billingProvider: string | null;
  providerSubscriptionId: string | null;

  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
}
```

Use immutable occurrence records to represent individual scheduled visits. Each occurrence must have a unique key that prevents duplicate generation.

## 8.3 Money and timestamps

- Store INR amounts as integer paise.
- Store timestamps using Firestore Timestamp.
- Use server timestamps for authoritative event times.
- Store booking price snapshots rather than recalculating historical bookings using current prices.
- Store gateway transaction references without exposing payment secrets.
- Keep customer addresses and sensitive records private.

---

# 9. Firestore Security Rules

Security Rules must default to denying access. Allow only the operations explicitly needed by each role.

The following is a **starter policy pattern**. It must be expanded and tested against the complete schema before deployment.

```javascript
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {

    function signedIn() {
      return request.auth != null;
    }

    function isSelf(uid) {
      return signedIn() && request.auth.uid == uid;
    }

    function hasRole(role) {
      return signedIn()
        && request.auth.token.role == role;
    }

    function isAdmin() {
      return hasRole("admin")
        || hasRole("super_admin");
    }

    function isFinance() {
      return isAdmin()
        || hasRole("finance");
    }

    match /users/{uid} {
      allow read: if isSelf(uid) || isAdmin();

      // Restrict fields in production. Never allow
      // users to grant themselves privileged roles.
      allow create: if isSelf(uid)
        && !request.resource.data.keys()
          .hasAny(["role", "admin", "isSuperAdmin"]);

      allow update: if isSelf(uid)
        && request.resource.data.diff(resource.data)
          .affectedKeys()
          .hasOnly([
            "name",
            "profileImagePath",
            "updatedAt"
          ]);

      allow delete: if false;
    }

    match /bookings/{bookingId} {
      allow read: if signedIn()
        && (
          resource.data.customerUid == request.auth.uid
          || resource.data.assignedWorkerUid
              == request.auth.uid
          || isAdmin()
        );

      // Booking creation and state transitions use
      // validated server-side functions.
      allow create, update, delete: if false;
    }

    match /payments/{paymentId} {
      allow read: if signedIn()
        && (
          resource.data.customerUid == request.auth.uid
          || isFinance()
        );

      allow write: if false;
    }

    match /auditLogs/{logId} {
      allow read: if hasRole("super_admin");
      allow write: if false;
    }

    match /webhookEvents/{eventId} {
      allow read, write: if false;
    }

    match /idempotencyKeys/{keyId} {
      allow read, write: if false;
    }

    // Add explicit rules for every remaining collection.
    // No general authenticated-user write access.

    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

### Security implementation requirements

1. Test all rules with the Firebase Emulator Suite.
2. Create separate rules for vehicles, addresses, workers, subscriptions, locations, evidence and support tickets.
3. Restrict customers to their own data.
4. Restrict workers to their own profiles and authorized assigned-job data.
5. Prevent clients from changing payment status, booking price, roles or subscription balances.
6. Use trusted functions for privileged writes.
7. Remember that server SDKs bypass Firestore Security Rules; Cloud Functions must perform their own authorization checks.
8. Never place service-account credentials or gateway secrets in client applications.
9. Do not allow users to self-assign worker or administrator roles.
10. Use short-lived, authorized access to private media.

### Storage Rules

- Allow workers to upload evidence only for their valid assigned jobs.
- Validate file size and allowed content type.
- Restrict read access to authorized customers, workers and administrators.
- Deny public access to private evidence.
- Validate upload metadata server-side where necessary.
- Enforce retention and deletion policies.

---

# 10. Cloud Functions Specification

Use TypeScript and Cloud Functions Gen 2.

Organize functions by business domain:

```text
functions/src/
├── auth/
├── users/
├── vehicles/
├── addresses/
├── services/
├── availability/
├── bookings/
├── assignments/
├── workers/
├── tracking/
├── subscriptions/
├── payments/
├── verification/
├── notifications/
├── support/
├── payouts/
├── scheduled/
└── shared/
```

## 10.1 Booking functions

| Function | Responsibility |
|---|---|
| `createBooking` | Validate customer, vehicle, address, price and slot |
| `getAvailableSlots` | Return eligible slots and capacity |
| `cancelBooking` | Enforce cancellation policy |
| `rescheduleBooking` | Validate replacement slot |
| `getBookingDetails` | Return authorized booking details |
| `updateBookingStatus` | Enforce allowed status transitions |

## 10.2 Assignment functions

| Function | Responsibility |
|---|---|
| `recommendWorkers` | Rank eligible workers |
| `assignWorker` | Confirm assignment transactionally |
| `acceptAssignment` | Record worker acknowledgement |
| `reassignWorker` | Handle reassignment and conflicts |
| `startWorkerTrip` | Validate assignment and enable tracking |
| `stopWorkerTrip` | End tracking and record trip status |
| `recordWorkerLocation` | Validate and store active-trip updates |

## 10.3 Payment functions

| Function | Responsibility |
|---|---|
| `createPaymentOrder` | Create a gateway order for an eligible booking |
| `verifyPayment` | Verify the provider result server-side |
| `handlePaymentWebhook` | Process signed gateway events idempotently |
| `recordCashCollection` | Record authorized cash collection |
| `requestRefund` | Validate refund eligibility |
| `reconcilePayments` | Identify unresolved transaction discrepancies |

## 10.4 Subscription functions

| Function | Responsibility |
|---|---|
| `createSubscription` | Validate plan, schedule and payment mode |
| `generateOccurrences` | Create due visits without duplicates |
| `skipOccurrence` | Apply skip and credit policies |
| `pauseSubscription` | Pause future eligible visits |
| `resumeSubscription` | Validate and resume schedule |
| `cancelSubscription` | Apply cancellation rules |
| `processRenewals` | Process eligible recurring billing |
| `reconcileRenewals` | Repair unresolved billing and subscription states |

## 10.5 Supporting functions

- `sendBookingNotification`
- `sendUpcomingWashReminder`
- `expirePendingBooking`
- `verifyCompletion`
- `openSupportTicket`
- `calculateWorkerEarnings`
- `processWorkerPayout`
- `writeAuditLog`

### Common function requirements

Every sensitive function must:

1. Authenticate the caller.
2. Validate the role and resource ownership.
3. Validate the request schema.
4. Read authoritative records.
5. Execute an atomic transaction where required.
6. Use idempotency for retriable operations.
7. Record relevant audit events.
8. Return structured success or failure results.
9. Avoid logging secrets and unnecessary personal information.

---

# 11. Booking and Assignment Workflows

## 11.1 Booking workflow

```text
Customer selects service
          |
          v
Validate service area and availability
          |
          v
Calculate authoritative price
          |
          v
Create booking request
          |
          v
Payment required?
     /          \
   Yes           No
    |             |
Create order   Confirm eligible
    |          cash booking
Verify gateway      |
    |               |
    +-------+-------+
            |
            v
       Confirm booking
            |
            v
  Generate worker recommendations
            |
            v
 Admin confirms or overrides
            |
            v
   Notify customer and worker
```

The backend must define reservation expiry, capacity rules and recovery behavior for abandoned payment attempts.

## 11.2 Hybrid assignment workflow

1. Find eligible workers.
2. Exclude suspended workers and conflicting assignments.
3. Calculate a recommendation score.
4. Show ranked workers to the administrator.
5. Confirm assignment using a transaction.
6. Record assignment history.
7. Notify the worker.
8. Notify the customer when appropriate.
9. Reassign if the worker becomes unavailable.

For the first release, administrator confirmation is the default. Automatic assignment can be enabled later for selected service areas.

## 11.3 Worker trip workflow

```text
Worker opens assigned booking
          |
          v
Start trip
          |
          v
Backend validates assignment
          |
          v
Location updates begin
          |
          v
Customer sees last known location
          |
          v
Worker arrives
          |
          v
Trip ends and tracking stops
```

If the worker is offline or location permission is denied, the application should show the last update and a clear status rather than inventing an ETA.

---

# 12. Payment and Subscription Design

## 12.1 Online payments

Use Razorpay through a trusted server-side integration.

Flow:

1. Customer chooses online payment.
2. Cloud Function creates a gateway order.
3. Client opens the supported checkout flow.
4. Client submits the returned payment reference.
5. Backend verifies the provider result or processes a verified webhook.
6. Backend updates payment and booking state.
7. Customer receives confirmation.

The client callback alone is insufficient proof of payment.

Use unique provider references and idempotency records to prevent duplicate processing.

## 12.2 Cash payments

Cash collection is allowed only for eligible bookings and approved service areas.

- The booking records cash as its payment method.
- The worker records the collected amount through a controlled workflow.
- A trusted backend operation updates collection status.
- Finance can reconcile collections against completed jobs.
- Differences require a reason and audit record.
- A cash booking must never be marked online-paid.

## 12.3 Prepaid subscriptions

- Customer selects a plan.
- Backend calculates the plan price.
- Customer completes payment.
- Subscription activates after payment verification.
- Visit occurrences are generated according to the schedule.
- Completing an eligible visit consumes the appropriate credit.
- Cancellation and refunds follow the configured plan policy.

Visit credits must be consumed transactionally to prevent duplicate deductions.

## 12.4 Recurring subscriptions

- Customer explicitly agrees to recurring billing terms.
- Backend creates the supported billing arrangement through the payment provider.
- Subscription status reflects provider-confirmed billing outcomes.
- Scheduled renewals use the appropriate consent and mandate flow.
- Failed renewals trigger a documented grace-period or suspension policy.
- Duplicate renewal events must not create duplicate charges or visit credits.
- Cancellation must be synchronized with the provider where applicable.

Do not assume every payment method supports automatic recurring billing. Confirm merchant onboarding, mandate support, provider requirements and applicable regulations before enabling the feature in production.

---

# 13. Notifications

Use FCM for push notifications and Firestore for persistent in-app notification records.

Events include:

- Booking confirmed.
- Worker assigned.
- Worker starts trip.
- Worker arrives.
- Service starts.
- Evidence submitted.
- Completion verified.
- Booking cancelled or rescheduled.
- Upcoming subscription visit.
- Renewal success or failure.
- Refund status changed.
- Support ticket updated.

Each notification should have an ID, recipient UID, event type, relevant resource reference, creation timestamp and read state.

Store the notification record before attempting delivery. Mark-read and delete actions must use appropriate ownership checks and must actually update the underlying record.

---

# 14. Privacy and Security

## 14.1 Personal data

- Restrict access to customer phone numbers and addresses.
- Limit precise location access to the active trip.
- Do not expose vehicle registration details unnecessarily.
- Keep private photos behind authorization.
- Provide account deletion and data-retention workflows.
- Publish an accurate privacy policy and obtain required permissions.

## 14.2 Location retention

Store current location separately from long-term job records.

- Keep the latest location needed for active tracking.
- Record trip start and end.
- Stop collecting location after arrival.
- Apply a documented retention period for historical location data.
- Delete or anonymize data when retention requirements allow.

## 14.3 Monitoring

- Configure production error alerts.
- Track failed booking and payment operations.
- Monitor Cloud Function execution and latency.
- Monitor Firestore reads and writes.
- Monitor media storage and bandwidth.
- Establish budget alerts and abuse limits.
- Review access logs and audit events.

---

# 15. Repository Structure

```text
washpro/
├── apps/
│   ├── customer-mobile/
│   ├── worker-pwa/
│   └── admin-dashboard/
├── packages/
│   ├── shared-types/
│   ├── validation-schemas/
│   └── design-tokens/
├── functions/
│   └── src/
│       ├── bookings/
│       ├── assignments/
│       ├── payments/
│       ├── subscriptions/
│       ├── tracking/
│       ├── notifications/
│       └── shared/
├── tests/
│   ├── unit/
│   ├── integration/
│   ├── security/
│   └── e2e/
├── firestore.rules
├── firestore.indexes.json
├── storage.rules
├── firebase.json
├── .firebaserc
├── docs/
│   ├── PRD.md
│   ├── architecture.md
│   ├── data-model.md
│   ├── security.md
│   ├── booking-workflow.md
│   └── deployment.md
└── README.md
```

Keep environment-specific configuration separate. Do not commit service-account credentials, gateway secrets or production private keys.

---

# 16. Deployment Plan

## 16.1 Environments

Maintain separate environments for:

- Local development.
- Staging and QA.
- Production.

Use separate Firebase projects for staging and production to avoid accidental writes to production customer or financial data.

## 16.2 Firebase setup

1. Create Firebase projects.
2. Register Android and iOS applications.
3. Register the worker and admin web applications.
4. Configure Authentication providers.
5. Create Firestore databases and indexes.
6. Configure Storage and Security Rules.
7. Initialize Cloud Functions.
8. Configure FCM.
9. Set up App Check.
10. Configure Cloud Scheduler and required service permissions.
11. Configure budgets, alerts and logs.

## 16.3 Secrets and external services

Store gateway credentials, webhook secrets and other private configuration in an appropriate managed secret store, such as Google Cloud Secret Manager.

Use separate test and live credentials.

Configure Google Maps API restrictions, permitted origins, quotas and billing.

## 16.4 Deployment targets

| Application | Deployment |
|---|---|
| Flutter Android app | Google Play internal testing, then production |
| Flutter iOS app | TestFlight, then App Store |
| Worker PWA | Firebase Hosting or equivalent HTTPS hosting |
| Admin dashboard | Firebase Hosting or equivalent HTTPS hosting |
| Cloud Functions | Firebase deployment |
| Database and storage rules | Version-controlled Firebase deployment |
| Indexes | Version-controlled Firestore index deployment |

## 16.5 CI/CD

On each pull request:

- Run linting and formatting.
- Run unit tests.
- Build the affected applications.
- Run backend tests.
- Run Firestore and Storage rules tests.
- Check dependency vulnerabilities.

On staging deployment:

- Deploy staging functions, rules, indexes and hosting.
- Run integration tests.
- Run payment sandbox tests.
- Run end-to-end smoke tests.

Production deployment requires approval and a rollback or recovery plan.

Database migrations and destructive operations must be reviewed separately from ordinary frontend deployments.

---

# 17. Testing Strategy

## 17.1 Unit tests

Test:

- Price calculations.
- Service eligibility.
- Slot availability.
- Assignment scoring.
- Booking status transitions.
- Subscription schedules.
- Visit-credit accounting.
- Cancellation and refund calculations.
- Idempotency behavior.

## 17.2 Integration tests

Use Firebase Emulator Suite for:

- Authentication.
- Firestore reads and writes.
- Security Rules.
- Cloud Functions.
- Storage access.
- Notifications and event handling where supported by the test setup.

Use provider sandbox environments for payment gateway tests.

## 17.3 Security tests

Verify that:

- Customers cannot access other customers' data.
- Workers cannot access unrelated jobs.
- Users cannot grant themselves privileged roles.
- Clients cannot modify payment status or price snapshots.
- Duplicate webhook events do not duplicate financial operations.
- Private photos cannot be read by unauthorized users.
- Unauthorized users cannot modify subscriptions or worker payouts.

## 17.4 End-to-end tests

Test complete journeys:

1. Customer registers.
2. Customer adds a vehicle.
3. Customer saves an address.
4. Customer books an instant wash.
5. Admin assigns a worker.
6. Worker starts a trip.
7. Customer sees location updates.
8. Worker completes the checklist.
9. Worker uploads before-and-after photos.
10. Customer verifies completion.
11. Payment is reconciled.
12. Customer leaves a review.

Also test scheduled booking, prepaid subscriptions, recurring renewal, cash collection, cancellation, refunds and failure recovery.

## 17.5 Load and reliability tests

Simulate:

- Concurrent booking attempts for one slot.
- Multiple workers sending location updates.
- Duplicate payment webhooks.
- Recurring occurrence generation retries.
- Large booking-history queries.
- Temporary gateway failures.
- Worker connectivity loss during uploads.

Measure Firestore usage and function costs during these tests.

---

# 18. Implementation Milestones

The following schedule is an initial planning estimate for a small, focused team. It assumes core development can proceed in parallel after the architecture and schemas are agreed.

| Milestone | Estimated duration | Deliverables |
|---|---|---|
| 1. Foundation | Week 1 | Repository, environments, Firebase setup, authentication, design system |
| 2. Backend and customer core | Weeks 2–3 | Users, vehicles, addresses, services, pricing, bookings |
| 3. Worker and admin operations | Weeks 4–5 | Worker PWA, job workflow, assignment recommendations, admin booking management |
| 4. Payments and subscriptions | Weeks 6–7 | Online and cash payment flows, prepaid plans, recurring billing integration |
| 5. Tracking and notifications | Week 8 | Active-trip tracking, FCM, evidence uploads, verification |
| 6. Hardening and pilot | Weeks 9–10 | Security testing, E2E tests, operational reports, staging and Hyderabad pilot |

Actual duration will depend on team size, payment provider approval, app-store review, mapping integration and operational readiness.

## Milestone acceptance criteria

**Milestone 1:** Authentication works and unauthorized users cannot access protected records.

**Milestone 2:** A customer can create a valid booking without overbooking or trusting client-supplied prices.

**Milestone 3:** An administrator can assign a worker, and the worker can complete an authorized job.

**Milestone 4:** Online payment reconciliation, cash collection and subscription credit accounting are correct.

**Milestone 5:** Location tracking respects the active-trip boundary and notifications reflect authoritative state.

**Milestone 6:** Critical security, payment and booking tests pass, production monitoring is active and the pilot team can resolve operational exceptions.

---

# 19. Launch Strategy — Hyderabad

## Pilot phase

Start with a limited service area and a small group of verified workers.

Before accepting public bookings:

- Confirm service coverage and operating hours.
- Finalize prices and service inclusions.
- Verify worker identity and operational readiness.
- Define cancellation, refund and customer-unavailable policies.
- Test cash reconciliation.
- Test payment gateway settlement and refund workflows.
- Verify apartment parking and access instructions.
- Train workers to capture service evidence.
- Establish support escalation procedures.
- Monitor service completion and complaints daily.

Expand service areas only when worker capacity and service quality can support the additional demand.

## Initial success metrics

Track:

- Booking conversion rate.
- Successful service completion rate.
- On-time arrival rate.
- Repeat-booking rate.
- Subscription conversion and renewal rates.
- Payment exception rate.
- Complaints per 100 completed jobs.
- Worker utilization.
- Contribution margin per wash.

Define each metric consistently before using it for business decisions.

---

# 20. Final Implementation Priorities

The development team should follow this order:

1. Finalize the data schema and booking state machine.
2. Implement Firebase environments, Authentication and Security Rules.
3. Build booking, pricing and availability functions.
4. Implement customer vehicle, address and booking flows.
5. Implement worker assignment and job execution.
6. Build admin booking operations.
7. Integrate online payments and cash reconciliation.
8. Implement prepaid subscriptions and recurring billing.
9. Add active-trip location sharing and notifications.
10. Complete security, integration and end-to-end testing.
11. Deploy staging and conduct a controlled Hyderabad pilot.
12. Launch publicly only after critical acceptance criteria pass.

**Final recommendation:** Build WashPro around reliable booking, controlled worker assignment and correct financial records first. Treat subscriptions, live tracking and operational analytics as integrated business modules, not isolated UI features. Firebase can support the initial platform effectively when Security Rules, transactional writes, idempotency and cost monitoring are designed correctly from the beginning.

The application is considered launch-ready only after the critical security, booking, payment and worker-completion acceptance criteria have been verified in staging and the production configuration has been reviewed.
