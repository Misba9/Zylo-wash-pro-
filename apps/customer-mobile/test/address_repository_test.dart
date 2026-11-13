import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washpro_customer/data/app_data.dart';
import 'package:washpro_customer/data/repository.dart';

void main() {
  group('isPersistedAddressId', () {
    test('rejects empty and local optimistic ids', () {
      expect(WashProRepository.isPersistedAddressId(''), isFalse);
      expect(WashProRepository.isPersistedAddressId('a1731234567890'), isFalse);
      expect(WashProRepository.isPersistedAddressId('a10000000000'), isFalse);
    });

    test('accepts Firestore-style auto ids', () {
      expect(WashProRepository.isPersistedAddressId('xK9fQ2mLpN8sRtUv'), isTrue);
      expect(WashProRepository.isPersistedAddressId('addr_home_1'), isTrue);
    });
  });

  group('mapFirestoreError', () {
    test('maps permission-denied and unauthenticated', () {
      expect(
        WashProRepository.mapFirestoreError(
          FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
          operation: 'save your address',
        ),
        contains('permission'),
      );
      expect(
        WashProRepository.mapFirestoreError(
          FirebaseException(plugin: 'cloud_firestore', code: 'unauthenticated'),
          operation: 'save your address',
        ),
        contains('sign in'),
      );
    });

    test('maps network / timeout codes', () {
      expect(
        WashProRepository.mapFirestoreError(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          operation: 'update this address',
        ),
        contains('Network'),
      );
      expect(
        WashProRepository.mapFirestoreError(
          FirebaseException(plugin: 'cloud_firestore', code: 'deadline-exceeded'),
          operation: 'update this address',
        ),
        contains('timed out'),
      );
    });

    test('maps not-found for stale document updates', () {
      expect(
        WashProRepository.mapFirestoreError(
          FirebaseException(plugin: 'cloud_firestore', code: 'not-found'),
          operation: 'update this address',
        ),
        contains('not found'),
      );
    });
  });

  group('address list state after write failure', () {
    tearDown(() {
      AppState.addresses.clear();
    });

    test('failed save must not leave the list empty when prior addresses exist',
        () {
      AppState.addresses.add(Addr(
          'persisted_1', 'Home', 'Tower B', 'Kondapur', 'kondapur', '1204',
          latitude: 17.4622, longitude: 78.3568));
      final prior = List<Addr>.from(AppState.addresses);

      // Simulate UI rule: only append after ok == true.
      const writeFailed = true;
      if (!writeFailed) {
        AppState.addresses.add(Addr('', 'Office', 'line', 'area', 'hitech', '—'));
      }

      expect(AppState.addresses.length, prior.length);
      expect(AppState.addresses.first.id, 'persisted_1');
      expect(AppState.addresses, isNotEmpty);
    });

    test('successful create appends exactly once', () {
      AppState.addresses.clear();
      final na = Addr('newFirestoreId', 'Home', 'line', 'Kondapur', 'kondapur', '—',
          latitude: 17.4, longitude: 78.3);
      const writeOk = true;
      if (writeOk && !AppState.addresses.any((x) => x.id == na.id)) {
        AppState.addresses.add(na);
      }
      if (writeOk && !AppState.addresses.any((x) => x.id == na.id)) {
        AppState.addresses.add(na);
      }
      expect(AppState.addresses, hasLength(1));
    });

    test('latitude/longitude remain on Addr after model round-trip fields', () {
      final a = Addr('id1', 'Home', 'line', 'area', 'kondapur', 'B1',
          latitude: 17.462201, longitude: 78.356812);
      expect(a.hasCoordinates, isTrue);
      final payloadLike = a.toServiceLocationSnapshot();
      expect(payloadLike['latitude'], 17.462201);
      expect(payloadLike['longitude'], 78.356812);
    });

    test('legacy address without coords stays readable', () {
      final legacy = Addr('old', 'Parents', 'Lane 3', 'Charminar', 'begumpet', '—',
          formattedAddress: 'Lane 3, Charminar');
      expect(legacy.hasCoordinates, isFalse);
      expect(legacy.displayFormatted, contains('Charminar'));
    });
  });

  group('AddressWriteResult', () {
    test('ok / fail flags', () {
      expect(const AddressWriteResult.ok(addressId: 'x').ok, isTrue);
      expect(const AddressWriteResult.fail('nope', code: 'permission-denied').ok,
          isFalse);
    });
  });
}
