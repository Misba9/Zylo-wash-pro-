# Known Issues — ZYLO

## Accepted for pilot / closed testing
1. **App Check** not enabled — monitor abuse; enable Play Integrity before broad release.  
2. **Booking create** still writes Firestore from Flutter; payment amount corrected server-side at order creation. Full CF-only create is follow-up.  
3. **UPI Intent/QR** unavailable under Razorpay Test keys — Test Collect + Cards only.  
4. **Admin RBAC** sidebar role switcher is demo UX; real enforcement is claims + rules.  
5. **Analytics charts** placeholders until `analyticsDaily` aggregators ship.  
6. **Coupon WELCOME75** hardcoded fallback in Functions if Firestore coupon missing — seed coupon on activate.  

## Fixed recently (see BUG_REPORT)
- Client underpayment for Razorpay orders  
- Customer self-complete  
- Subscription balance client tampering  
- Over-broad Storage evidence reads  
- Silent debug signing on release  

## Do not regress
- Never invent GPS coordinates  
- Never mark paid from Flutter alone  
- Never commit Live Razorpay secrets or keystore  
