# Google Play Compliance — ZYLO Customer (`com.washpro.customer`)

## App identity
| Field | Value |
|-------|-------|
| Application ID | `com.washpro.customer` |
| Version | `1.2.0` (versionCode **3**) |
| targetSdk / compileSdk | Flutter default **36** |
| minSdk | **24** |
| Signing | Upload keystore via `android/key.properties` (gitignored); release **fails** if missing |

## Listing (prepare manually in Play Console)
- App name: ZYLO  
- Category: Lifestyle / House & Home  
- Short / full description: doorstep car wash Hyderabad  
- Contact: support email (use production mailbox)  
- Website: https://zyloo.co.in  
- Privacy policy URL: https://wash-pro-customer.web.app/privacy.html  
- Account deletion URL: https://wash-pro-customer.web.app/delete-account.html  

## Data Safety (verify before submit)
| Data | Collected? | Shared? | Purpose |
|------|------------|---------|---------|
| Phone number | Yes (Auth) | No | Account |
| Name | Yes | No | Profile/booking |
| Approximate/precise location | Yes (addresses) | With assigned worker/admin | Service delivery |
| Photos | Optional evidence | Worker/admin | Job QC |
| Purchase history | Yes (payments) | Razorpay processor | Transactions |
| Device IDs / FCM | Yes | Firebase | Notifications |

Ads: **None** (verify no ad SDKs before claiming).

## Account deletion
- In-app: Settings → Delete account  
- Web: delete-account.html  
- Backend: `deleteMyAccount` callable  

## Permissions (AndroidManifest)
- INTERNET, NETWORK_STATE  
- COARSE/FINE location (foreground address pin) — **no background location**  
- POST_NOTIFICATIONS (runtime)  
- Camera only if used for profile — confirm before Data Safety  

## Reviewer access
Provide Firebase Console **test phone numbers** (not production admin).  
Never publish Super Admin credentials as reviewer login.

## Closed testing
If the Play developer account is a personal account created after 13 Nov 2023, confirm current closed-testing tester/day requirements before production access. Organization accounts may differ — verify in Console.

## Live payment checklist (manual — do not automate)
1. Switch secrets to Live keys only after Test Mode E2E pass.  
2. UPI Intent + QR on physical device with UPI apps.  
3. Webhook URL on Live Dashboard.  
4. Refund smoke test ₹1.  
5. Do not ship Test Mode keys in a production AAB.
