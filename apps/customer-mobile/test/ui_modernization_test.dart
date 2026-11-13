import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:washpro_customer/data/app_data.dart';
import 'package:washpro_customer/services/app_services.dart';
import 'package:washpro_customer/theme/washpro_theme.dart';
import 'package:washpro_customer/widgets/vehicle_sheet.dart';
import 'package:washpro_customer/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Theme architecture', () {
    test('light and dark ThemeData are complete', () {
      expect(WashProTheme.light.brightness, Brightness.light);
      expect(WashProTheme.dark.brightness, Brightness.dark);
      expect(WashProTheme.light.scaffoldBackgroundColor, WpColors.mintBg);
      expect(WashProTheme.dark.scaffoldBackgroundColor, WpColors.darkBg);
      expect(WashProTheme.light.colorScheme.primary, WpColors.primary);
      expect(WashProTheme.dark.colorScheme.primary, WpColors.secondary);
    });

    test('theme preference persists', () async {
      SharedPreferences.setMockInitialValues({});
      await AppTheme.set(ThemeMode.dark);
      expect(AppTheme.mode.value, ThemeMode.dark);
      await AppTheme.load();
      expect(AppTheme.mode.value, ThemeMode.dark);
      await AppTheme.set(ThemeMode.system);
      expect(AppTheme.mode.value, ThemeMode.system);
    });
  });

  group('Vehicle model compatibility', () {
    test('new seating maps to pricing categories without rewriting legacy', () {
      final modern = Vehicle('1', 'Creta', 'sedan', '', 'Creta', '', 'TS 09 AB 1234',
          seating: '5');
      expect(modern.pricingCategory, 'sedan');
      expect(modern.seatingLabel, '5 Seater');
      expect(modern.displayName, 'Creta');

      final seven = Vehicle('2', 'Fortuner', 'suv', '', 'Fortuner', '', 'TS 09 CD 9999',
          seating: '7');
      expect(seven.pricingCategory, 'suv');
      expect(seven.seatingLabel, '7 Seater');

      // Legacy SUV is NOT auto-assumed to be 7-seater.
      final legacy = Vehicle('3', 'Old SUV', 'suv', 'Toyota', 'Fortuner', 'White', 'TS 01 AA 1111');
      expect(legacy.seating, isNull);
      expect(legacy.pricingCategory, 'suv');
      expect(legacy.seatingLabel, 'SUV');
      expect(Vehicle.pricingCategoryForSeating('5'), 'sedan');
      expect(Vehicle.pricingCategoryForSeating('7'), 'suv');
    });

    test('address display helpers avoid empty/malformed labels', () {
      final a = Addr('1', 'Home', 'Road 12', 'Kondapur', 'kondapur', '54',
          city: 'Hyderabad');
      expect(a.titleLine, '54 · Home');
      expect(a.subtitleLine.contains('Road 12'), isTrue);
      final empty = Addr('2', '', '', '', 'kondapur', '');
      expect(empty.titleLine, 'Address');
    });
  });

  testWidgets('auth screen renders in dark theme', (tester) async {
    SharedPreferences.setMockInitialValues({'themeMode': 'dark'});
    await AppTheme.load();
    await tester.pumpWidget(const WashProApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Send OTP'), findsOneWidget);
    final scaffold = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(scaffold.themeMode, ThemeMode.dark);
  });

  testWidgets('vehicle sheet shows only three fields', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: WashProTheme.light,
      home: Scaffold(
        body: Builder(builder: (context) {
          return FilledButton(
            onPressed: () => showVehicleSheet(context, () {}),
            child: const Text('Open'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Add Vehicle'), findsOneWidget);
    expect(find.text('Vehicle name'), findsOneWidget);
    expect(find.text('Registration number'), findsOneWidget);
    expect(find.text('5 Seater'), findsOneWidget);
    expect(find.text('7 Seater'), findsOneWidget);
    expect(find.text('Make (Tata)'), findsNothing);
    expect(find.text('Category'), findsNothing);
  });
}
