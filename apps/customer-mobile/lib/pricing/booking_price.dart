/// Trusted client-side booking price breakdown.
///
/// Must stay aligned with the booking `priceSnapshot.totalPaise` written to
/// Firestore and the amount Razorpay orders from `createPaymentOrder`.
///
/// Historical UI mismatch (₹602 vs ₹503):
/// Interior sedan @ ₹549 + ₹29 fee − ₹75 coupon = **₹503** (scheduled).
/// Same booking with Wash Now express ₹99 = **₹602**.
/// The gap is exactly [expressFeePaise], not rounding or Razorpay conversion.
class BookingPrice {
  static const int kServiceFeePaise = 2900;
  static const int kExpressFeePaise = 9900;
  static const int kWelcomeDiscountPaise = 7500;
  static const String welcomeCouponCode = 'WELCOME75';

  /// Back-compat aliases used by UI copy.
  static const int expressFeePaise = kExpressFeePaise;
  static const int welcomeDiscountPaise = kWelcomeDiscountPaise;

  const BookingPrice({
    required this.servicePaise,
    required this.serviceFeePaise,
    required this.expressFeePaiseApplied,
    required this.discountPaise,
    required this.taxPaise,
    required this.totalPaise,
    this.couponCode,
  });

  final int servicePaise;
  final int serviceFeePaise;
  final int expressFeePaiseApplied;
  final int discountPaise;
  final int taxPaise;
  final int totalPaise;
  final String? couponCode;

  factory BookingPrice.compute({
    required int servicePaise,
    bool washNow = false,
    bool couponApplied = true,
  }) {
    const fee = kServiceFeePaise;
    final express = washNow ? kExpressFeePaise : 0;
    final discount = couponApplied ? kWelcomeDiscountPaise : 0;
    const tax = 0;
    final total = servicePaise + fee + express - discount + tax;
    assert(total >= 100, 'Booking total must be at least ₹1');
    return BookingPrice(
      servicePaise: servicePaise,
      serviceFeePaise: fee,
      expressFeePaiseApplied: express,
      discountPaise: discount,
      taxPaise: tax,
      totalPaise: total,
      couponCode: couponApplied ? welcomeCouponCode : null,
    );
  }

  /// Firestore `priceSnapshot` — createPaymentOrder reads `totalPaise`.
  Map<String, dynamic> toSnapshot({String pricingVersion = 'hyd-2026.10-v1'}) =>
      {
        'currency': 'INR',
        'subtotalPaise': servicePaise,
        'serviceFeePaise': serviceFeePaise,
        'expressFeePaise': expressFeePaiseApplied,
        'discountPaise': discountPaise,
        'taxPaise': taxPaise,
        'totalPaise': totalPaise,
        'pricingVersion': pricingVersion,
        if (couponCode != null) 'couponCode': couponCode,
      };

  int get totalRupees => totalPaise ~/ 100;
}
