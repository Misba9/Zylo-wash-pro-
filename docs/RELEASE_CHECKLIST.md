# Release Checklist — ZYLO Android

## Before building AAB
- [ ] Increment `pubspec.yaml` versionName / versionCode if needed (`1.2.0+3` current)
- [ ] `android/key.properties` + upload keystore present
- [ ] Firebase `google-services.json` is wash-pro-7f3b1 production
- [ ] SHA-1/256 registered in Firebase for Phone Auth
- [ ] Deploy latest `firestore.rules`, `storage.rules`, Functions (`trusted_amount`)
- [ ] Razorpay still **Test** until Live checklist complete
- [ ] No demo OTP / debug bypass in source
- [ ] Privacy + delete-account URLs return 200
- [ ] Crashlytics enabled (if used)

## Build (local — no Play upload without approval)
```bash
cd apps/customer-mobile
flutter clean
flutter pub get
flutter build appbundle --release
# Artifact: build/app/outputs/bundle/release/app-release.aab
```

## After AAB
- [ ] Verify package `com.washpro.customer`
- [ ] Verify signing (upload cert)
- [ ] Internal testing track upload (manual)
- [ ] Closed testing with ≥ required testers if applicable
- [ ] Production access / rollout only after scorecard green

## Explicitly out of scope without approval
- `firebase deploy` to production  
- Razorpay Live Mode  
- Play Console production release  
- Deleting production records  
