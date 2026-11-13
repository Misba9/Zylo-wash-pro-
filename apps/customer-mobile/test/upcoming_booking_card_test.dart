import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washpro_customer/data/app_data.dart';
import 'package:washpro_customer/theme/washpro_theme.dart';
import 'package:washpro_customer/widgets/upcoming_booking_card.dart';

void main() {
  testWidgets('UpcomingBookingCard shows service, vehicle, pay and status',
      (tester) async {
    final b = Booking(
      'WP-1',
      services.first,
      Vehicle('v1', 'Creta', 'sedan', '', 'Creta', '', 'TS09AB1234',
          seating: '5'),
      Addr('a1', 'Home', 'Road 1', 'Kondapur', 'kondapur', 'B2'),
      'awaiting_payment',
      DateTime(2026, 11, 12),
      '10:30 AM',
      60200,
      54900,
      'UPI',
      'pending',
      'instant',
    );

    await tester.pumpWidget(MaterialApp(
      theme: WashProTheme.light,
      home: Scaffold(
        body: UpcomingBookingCard(
          booking: b,
          formatDate: (d) => 'Wednesday, 12 Nov',
          formatMoney: (p) => '₹${p ~/ 100}',
          statusPill: (s) => Text(s),
          onOpen: () {},
        ),
      ),
    ));
    await tester.pump();

    expect(find.text(services.first.name), findsOneWidget);
    expect(find.textContaining('Creta'), findsOneWidget);
    expect(find.textContaining('TS09AB1234'), findsOneWidget);
    expect(find.text('Awaiting payment'), findsOneWidget);
    expect(find.text('₹602'), findsOneWidget);
    expect(find.text('View details'), findsOneWidget);
  });

  testWidgets('UpcomingBookingCard is theme-aware in dark mode', (tester) async {
    final b = Booking(
      'WP-2',
      services.first,
      Vehicle('v1', 'City', 'sedan', '', 'City', '', 'TS09CD9999', seating: '5'),
      Addr('a1', 'Office', 'Street', 'Hitech', 'hitech', 'P1'),
      'confirmed',
      DateTime(2026, 11, 13),
      '09:00 AM',
      50300,
      54900,
      'CASH',
      'pending',
      'scheduled',
    );
    await tester.pumpWidget(MaterialApp(
      theme: WashProTheme.dark,
      home: Scaffold(
        body: UpcomingBookingCard(
          booking: b,
          formatDate: (_) => 'Thu',
          formatMoney: (p) => '₹${p ~/ 100}',
          statusPill: (s) => Text(s),
          onOpen: () {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Cash after wash'), findsOneWidget);
    expect(find.text('₹503'), findsOneWidget);
  });
}
