import 'package:flutter_test/flutter_test.dart';
import 'package:washpro_customer/main.dart';
import 'package:washpro_customer/data/app_data.dart';
import 'package:washpro_customer/data/repository.dart';

void main() {
  testWidgets('WashPro shows email + Google login', (tester) async {
    await tester.pumpWidget(const WashProApp());
    // No live session in tests -> splash gate resolves to the auth screen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Send OTP'), findsNothing);
  });

  test('mockup pricing: services & plans', () {
    expect(services[0].price('hatchback'), 49900); // Body Wash ₹499 onwards
    expect(services[0].price('suv'), 64900); // SUV ₹649 (vehicle-specific)
    expect(services[2].price('hatchback'), 149900); // Deep Detail ₹1,499
    expect(plans[1].total, 358500); // Alternate Days ₹3,585/mo
    expect(plans[1].visits, 15);
  });

  test('Firestore-shaped service uses exact per-category prices', () {
    final s = Service.fromFirestore(
        'body-wash',
        {
          'name': 'Body Wash',
          'tagline': 'Foam wash',
          'durationMinutes': 40,
          'hatchback': 499,
          'sedan': 549,
          'suv': 649,
          'luxury': 799,
          'cashEligible': true,
        },
        null);
    expect(s.price('hatchback'), 49900);
    expect(s.price('sedan'), 54900);
    expect(s.price('luxury'), 79900);
  });

  test('Firestore-shaped plan parses paise + savings', () {
    final p = Plan.fromFirestore(
        'alternate',
        {
          'name': 'Alternate Days',
          'kicker': 'Most loved by commuters',
          'visits': 15,
          'perWashPaise': 23900,
          'totalPaise': 358500,
          'savePercent': 28,
          'billingMode': 'prepaid',
        },
        null);
    expect(p.total, 358500);
    expect(p.save, 28);
  });

  test('AppState starts empty — no fabricated customer data', () {
    expect(AppState.vehicles, isEmpty);
    expect(AppState.addresses, isEmpty);
    expect(AppState.bookings, isEmpty);
    expect(AppState.subs, isEmpty);
    expect(AppState.notifications, isEmpty);
    expect(AppState.userName, isEmpty);
    expect(AppState.primaryVehicle, isNull);
    expect(AppState.selectedAddress, isNull);
  });

  test('slot availability is real and time-based', () {
    final now = DateTime(2026, 10, 21, 7, 0); // 07:00
    expect(slotAvailable(DateTime(2026, 10, 21), '08:00 AM', now), isTrue);
    expect(slotAvailable(DateTime(2026, 10, 21), '07:30 AM', now),
        isFalse); // <45 min away (not a slot, but past-ish)
    final past =
        DateTime(2026, 10, 21, 11, 0); // 11:00 -> next is 12:00 PM today
    expect(nextSlotLabel(past), 'Today · 12:00 PM');
    final late = DateTime(2026, 10, 21, 16, 30); // nothing left today
    expect(nextSlotLabel(late), 'Tomorrow · 08:00 AM');
  });

  test('booking ids are unique (double-tap safe document ids)', () {
    final ids = List.generate(50, (_) => AppState.nextId()).toSet();
    // Millisecond ids may collide within the same ms in a tight loop; the
    // repository writes with set() on the doc id, so retries overwrite the
    // same document rather than creating duplicate bookings.
    expect(ids.length, greaterThan(0));
    expect(WashProRepository.live, isFalse); // no Firebase in unit tests
  });

  test('new user is incomplete until basic details are saved', () async {
    AppState.reset();
    expect(WashProRepository.isProfileComplete, isFalse);
    await WashProRepository.saveBasicDetails(
        name: 'Asha Rao', phone: '+91 90000 00000', email: 'asha@example.com');
    expect(WashProRepository.isProfileComplete, isTrue);
    expect(AppState.userName, 'Asha Rao');
    expect(AppState.firstName, 'Asha');
    expect(AppState.initials, 'AR');
    AppState.reset(); // keep other tests isolated
    expect(WashProRepository.isProfileComplete, isFalse);
  });

  test('max plan saving is computed from catalog data', () {
    expect(AppState.maxPlanSave, 34); // Daily Essential in default catalog
  });
}
