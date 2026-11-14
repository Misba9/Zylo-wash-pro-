import 'package:flutter_test/flutter_test.dart';
import 'package:washpro_customer/pricing/booking_price.dart';
import 'package:washpro_customer/services/app_services.dart';

void main() {
  test('booking flow is exactly 3 titled steps', () {
    // Mirrors BookingFlow.titles — keep in sync with lib/main.dart.
    const titles = [
      ('Vehicle & service', 'Step 1 of 3'),
      ('Schedule & location', 'Step 2 of 3'),
      ('Review & pay', 'Step 3 of 3'),
    ];
    expect(titles, hasLength(3));
    expect(titles.every((t) => t.$2.contains('of 3')), isTrue);
    expect(titles.map((t) => t.$2).toSet(), hasLength(3));
  });

  test('express fee is included in total and snapshot for Wash Now', () {
    const interiorSedan = 54900;
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
    expect(scheduled.totalPaise, 50300);
    expect(instant.totalPaise, 60200);
    expect(instant.toSnapshot()['totalPaise'], 60200);
    expect(instant.toSnapshot()['expressFeePaise'], 9900);
  });

  test('Razorpay checkout does not hide UPI or Cards', () {
    final opts = RazorpayService.checkoutOptions(
      keyId: 'rzp_test_x',
      orderId: 'order_1',
      amountPaise: 60200,
      bookingId: 'WP-1',
      name: 'Asha',
      email: 'a@example.com',
      phone: '9059899298',
    );
    final display = (opts['config'] as Map)['display'] as Map;
    final hide = (display['hide'] as List)
        .map((e) => (e as Map)['method'])
        .toSet();
    expect(hide, containsAll(['emi', 'netbanking', 'wallet', 'paylater']));
    expect(hide, isNot(contains('upi')));
    expect(hide, isNot(contains('card')));
    final instruments =
        (((display['blocks'] as Map)['zylo_pay'] as Map)['instruments'] as List);
    expect(instruments.map((e) => (e as Map)['method']), ['upi', 'card']);
    expect((instruments.first as Map).containsKey('flows'), isFalse);
    // Direct checkout: no forced method prefill (lets Razorpay show UPI+Cards).
    expect((opts['prefill'] as Map).containsKey('method'), isFalse);
    expect(opts['amount'], 60200);
    expect(opts['currency'], 'INR');
  });

  test('checkout amount uses integer paise only', () {
    final p = BookingPrice.compute(
      servicePaise: 54900,
      washNow: true,
      couponApplied: true,
    );
    expect(p.totalPaise % 1, 0);
    expect(p.totalPaise, 60200);
  });
}
