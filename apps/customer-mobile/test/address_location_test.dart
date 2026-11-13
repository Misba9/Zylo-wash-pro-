import 'package:flutter_test/flutter_test.dart';
import 'package:washpro_customer/data/app_data.dart';

void main() {
  group('Addr coordinates', () {
    test('hasCoordinates rejects null/NaN/out-of-range', () {
      expect(Addr('1', 'Home', 'line', 'area', 'kondapur', 'B1').hasCoordinates,
          isFalse);
      expect(
          Addr('1', 'Home', 'line', 'area', 'kondapur', 'B1',
                  latitude: double.nan, longitude: 78)
              .hasCoordinates,
          isFalse);
      expect(
          Addr('1', 'Home', 'line', 'area', 'kondapur', 'B1',
                  latitude: 91, longitude: 78)
              .hasCoordinates,
          isFalse);
      expect(
          Addr('1', 'Home', 'line', 'area', 'kondapur', 'B1',
                  latitude: 17.4622, longitude: 78.3568)
              .hasCoordinates,
          isTrue);
    });

    test('isValidLatLng helper', () {
      expect(isValidLatLng(17.4, 78.3), isTrue);
      expect(isValidLatLng(null, 78.3), isFalse);
      expect(isValidLatLng(17.4, 200), isFalse);
    });

    test('toServiceLocationSnapshot copies exact map coords', () {
      final a = Addr('addr_1', 'Home', 'Tower B', 'Kondapur', 'kondapur', '1204',
          latitude: 17.462201, longitude: 78.356812, city: 'Hyderabad',
          postalCode: '500084', building: 'Tower B', state: 'Telangana',
          formattedAddress: 'Flat 1204, My Home Tridasa, Kondapur');
      final snap = a.toServiceLocationSnapshot();
      expect(snap['addressId'], 'addr_1');
      expect(snap['latitude'], 17.462201);
      expect(snap['longitude'], 78.356812);
      expect(snap['formattedAddress'], contains('Kondapur'));
      expect(snap['city'], 'Hyderabad');
    });

    test('snapshot omits invented coords for legacy addresses', () {
      final legacy = Addr('old', 'Parents', 'Lane 3', 'Charminar', 'begumpet', '—',
          city: 'Hyderabad', formattedAddress: 'Lane 3, Charminar');
      final snap = legacy.toServiceLocationSnapshot();
      expect(snap['latitude'], isNull);
      expect(snap['longitude'], isNull);
      expect(snap['formattedAddress'], contains('Charminar'));
    });

    test('editing saved address does not mutate a prior snapshot map', () {
      final a = Addr('addr_1', 'Home', 'Tower B', 'Kondapur', 'kondapur', '1204',
          latitude: 17.4622, longitude: 78.3568);
      final snap = Map<String, dynamic>.from(a.toServiceLocationSnapshot());
      a.latitude = 17.5;
      a.longitude = 78.4;
      expect(snap['latitude'], 17.4622);
      expect(snap['longitude'], 78.3568);
      expect(a.latitude, 17.5);
    });
  });
}
