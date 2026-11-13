import 'package:flutter_test/flutter_test.dart';
import 'package:washpro_customer/pricing/booking_price.dart';

void main() {
  group('BookingPrice — ₹602 vs ₹503 root cause', () {
    // Interior Cleaning sedan hatchback catalog: 54900 paise (shared catalog).
    const interiorSedan = 54900;

    test('scheduled wash with WELCOME75 = ₹503', () {
      final p = BookingPrice.compute(
        servicePaise: interiorSedan,
        washNow: false,
        couponApplied: true,
      );
      expect(p.serviceFeePaise, 2900);
      expect(p.expressFeePaiseApplied, 0);
      expect(p.discountPaise, 7500);
      expect(p.totalPaise, 50300);
      expect(p.totalRupees, 503);
    });

    test('Wash Now adds exactly ₹99 express → ₹602', () {
      final scheduled = BookingPrice.compute(
        servicePaise: interiorSedan,
        washNow: false,
        couponApplied: true,
      );
      final instant = BookingPrice.compute(
        servicePaise: interiorSedan,
        washNow: true,
        couponApplied: true,
      );
      expect(instant.expressFeePaiseApplied, 9900);
      expect(instant.totalPaise - scheduled.totalPaise, 9900);
      expect(instant.totalPaise, 60200);
      expect(instant.totalRupees, 602);
    });

    test('removing coupon increases total by discount only', () {
      final withCoupon = BookingPrice.compute(
        servicePaise: interiorSedan,
        washNow: true,
        couponApplied: true,
      );
      final without = BookingPrice.compute(
        servicePaise: interiorSedan,
        washNow: true,
        couponApplied: false,
      );
      expect(without.totalPaise - withCoupon.totalPaise, 7500);
      expect(without.couponCode, isNull);
    });

    test('priceSnapshot total drives Razorpay amount field', () {
      final p = BookingPrice.compute(
        servicePaise: interiorSedan,
        washNow: true,
        couponApplied: true,
      );
      final snap = p.toSnapshot();
      expect(snap['totalPaise'], 60200);
      expect(snap['expressFeePaise'], 9900);
      expect(snap['currency'], 'INR');
      expect(snap['taxPaise'], 0);
    });
  });
}
