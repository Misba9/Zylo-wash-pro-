import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washpro_customer/screens/payment_options_page.dart';
import 'package:washpro_customer/services/app_services.dart';
import 'package:washpro_customer/theme/washpro_theme.dart';

void main() {
  test('prefillContact keeps last 10 Indian digits', () {
    expect(RazorpayService.prefillContact('+91 90598 99298'), '9059899298');
    expect(RazorpayService.prefillContact('9059899298'), '9059899298');
    expect(RazorpayService.prefillContact('919059899298'), '9059899298');
  });

  test('checkout options hide EMI/netbanking/wallet/paylater via config.display',
      () {
    final opts = RazorpayService.checkoutOptions(
      keyId: 'rzp_test_x',
      orderId: 'order_1',
      amountPaise: 60200,
      bookingId: 'WP-1',
      name: 'Asha',
      email: 'a@example.com',
      phone: '+919059899298',
      preferredMethod: 'upi',
    );
    expect(opts.containsKey('method'), isFalse); // unreliable on Flutter SDK
    final display = (opts['config'] as Map)['display'] as Map;
    final hide = (display['hide'] as List)
        .map((e) => (e as Map)['method'])
        .toSet();
    expect(hide, containsAll(['emi', 'netbanking', 'wallet', 'paylater']));
    expect(hide, isNot(contains('upi')));
    expect(hide, isNot(contains('card')));
    expect(display.containsKey('blocks'), isFalse);
    expect(display['sequence'], ['upi', 'card']);
    expect((display['preferences'] as Map)['show_default_blocks'], isTrue);
    expect((opts['prefill'] as Map)['method'], 'upi');
    expect((opts['prefill'] as Map)['contact'], '9059899298');
    expect(opts['key'], 'rzp_test_x');
    expect(opts['notes'], containsPair('checkoutMode', 'test'));
    expect(opts['notes'], containsPair('configStrategy', 'default_hide'));
  });

  test('direct checkout without preferredMethod leaves UPI+Cards available', () {
    final opts = RazorpayService.checkoutOptions(
      keyId: 'rzp_test_x',
      orderId: 'order_direct',
      amountPaise: 60200,
      bookingId: 'WP-d',
      name: 'Asha',
      email: 'a@example.com',
      phone: '9059899298',
    );
    expect((opts['prefill'] as Map).containsKey('method'), isFalse);
    expect(opts['amount'], 60200);
    expect(opts['currency'], 'INR');
    final display = (opts['config'] as Map)['display'] as Map;
    expect(display.containsKey('blocks'), isFalse);
    expect(display['sequence'], ['upi', 'card']);
    final safe = RazorpayService.jsonSafeOptions(opts);
    expect(safe['order_id'], 'order_direct');
    expect(((safe['config'] as Map)['display'] as Map)['sequence'],
        ['upi', 'card']);
  });

  test('card preference is prefilled without inventing extra keys', () {
    final opts = RazorpayService.checkoutOptions(
      keyId: 'rzp_test_x',
      orderId: 'order_2',
      amountPaise: 10000,
      bookingId: 'WP-2',
      name: 'Asha',
      email: 'a@example.com',
      phone: '9059899298',
      preferredMethod: 'card',
    );
    expect((opts['prefill'] as Map)['method'], 'card');
    expect((opts['prefill'] as Map)['contact'], '9059899298');
  });

  test('unsupported preferredMethod is not written into prefill', () {
    final opts = RazorpayService.checkoutOptions(
      keyId: 'rzp_test_x',
      orderId: 'order_3',
      amountPaise: 10000,
      bookingId: 'WP-3',
      name: 'Asha',
      email: 'a@example.com',
      phone: '9059899298',
      preferredMethod: 'wallet',
    );
    expect((opts['prefill'] as Map).containsKey('method'), isFalse);
  });

  testWidgets('Payment Options shows UPI + Cards only', (tester) async {
    OnlinePayMethod? result;
    await tester.pumpWidget(MaterialApp(
      theme: WashProTheme.light,
      home: Builder(builder: (context) {
        return Scaffold(
          body: FilledButton(
            onPressed: () async {
              result = await Navigator.push<OnlinePayMethod>(
                context,
                MaterialPageRoute(
                  builder: (_) => const PaymentOptionsPage(
                    amountPaise: 60200,
                    offerLabel: 'Introductory discount · You save ₹75',
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        );
      }),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Payment Options'), findsOneWidget);
    expect(find.text('UPI'), findsOneWidget);
    expect(find.text('Popular'), findsOneWidget);
    expect(find.text('Cards'), findsOneWidget);
    expect(find.text('BHIM'), findsOneWidget);
    expect(find.text('Available Offers'), findsOneWidget);
    expect(find.text('Netbanking'), findsNothing);
    expect(find.text('EMI'), findsNothing);
    expect(find.text('Pay Later'), findsNothing);
    expect(find.text('Wallets'), findsNothing);
    expect(find.text('Secure payments powered by Razorpay'), findsOneWidget);

    await tester.tap(find.text('Cards'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(result, OnlinePayMethod.card);
    expect(result!.razorpayPrefill, 'card');
  });

  testWidgets('Payment Options hides offers when none provided', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PaymentOptionsPage(amountPaise: 49900),
    ));
    await tester.pump();
    expect(find.text('Available Offers'), findsNothing);
    expect(find.text('UPI'), findsOneWidget);
    expect(find.text('Cards'), findsOneWidget);
  });

  testWidgets('Payment Options works in dark theme', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: WashProTheme.dark,
      home: const PaymentOptionsPage(amountPaise: 49900),
    ));
    await tester.pump();
    expect(find.text('Payment Options'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, WpColors.darkBg);
  });
}
