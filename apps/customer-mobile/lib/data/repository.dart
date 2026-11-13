import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_data.dart';

/// Result of an address write — UI must not show success until [ok] is true.
class AddressWriteResult {
  const AddressWriteResult.ok({this.addressId})
      : ok = true,
        message = null,
        code = null;
  const AddressWriteResult.fail(this.message, {this.code, this.addressId})
      : ok = false;
  final bool ok;
  final String? message;
  final String? code;
  final String? addressId;
}

/// WashProRepository — the ONLY Firestore access point for the customer app.
/// UI widgets read/mutate [AppState] and call these methods; no Firestore
/// queries live inside widgets. Every query is scoped to the signed-in uid
/// and backed by Firestore Security Rules (owner-only collections).
class WashProRepository {
  static FirebaseFirestore get _fs => FirebaseFirestore.instance;

  /// Set by the app shell: surfaces write failures instead of failing silently
  /// (poor-network handling). Firestore queues writes offline and retries,
  /// but permission/shape errors must reach the user.
  static void Function(String message)? onWriteError;
  static void _report(String what) =>
      onWriteError?.call('Could not save $what. Check connection and retry.');

  /// Prevents double-tap duplicate address writes.
  static bool _addressWriteInFlight = false;
  static bool get addressWriteInFlight => _addressWriteInFlight;

  /// Maps Firestore / auth failures to safe user-facing copy (no secrets).
  static String mapFirestoreError(Object e, {required String operation}) {
    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':
          return 'You do not have permission to $operation. Sign in again and retry.';
        case 'unauthenticated':
          return 'Please sign in again to $operation.';
        case 'unavailable':
        case 'network-request-failed':
          return 'Network unavailable. Check your connection and retry.';
        case 'deadline-exceeded':
          return 'The request timed out. Please retry.';
        case 'not-found':
          return 'That address was not found. Refresh and try again.';
        case 'failed-precondition':
          return 'Could not $operation right now. Please retry.';
        case 'invalid-argument':
          return 'Some address details are invalid. Adjust and retry.';
        default:
          return 'Could not $operation. Please retry.';
      }
    }
    return 'Could not $operation. Please retry.';
  }

  static void _logAddressOp({
    required String operation,
    required String path,
    required int ms,
    Object? error,
  }) {
    final code = error is FirebaseException ? error.code : (error == null ? 'ok' : 'unknown');
    final authed = FirebaseAuth.instance.currentUser != null;
    developer.log(
      'addressOp op=$operation path=$path code=$code ms=$ms authed=$authed',
      name: 'WashPro.addresses',
    );
  }

  /// A profile counts as complete when we at least know the customer's name.
  /// New users (no users/{uid} doc, or a doc without a name) are routed to
  /// the basic-details form right after login; returning users skip it.
  static bool get isProfileComplete => AppState.userName.trim().isNotEmpty;

  /// Persist the basic details collected after a first login.
  static Future<void> saveBasicDetails(
      {required String name, String phone = '', String email = ''}) async {
    AppState.userName = name.trim();
    if (phone.trim().isNotEmpty) AppState.userPhone = phone.trim();
    if (email.trim().isNotEmpty) AppState.userEmail = email.trim();
    AppState.profileLoaded = true;
    if (!live) return;
    try {
      await _fs.collection('users').doc(fbUid).set({
        'name': AppState.userName,
        'phone': AppState.userPhone,
        'email': AppState.userEmail,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await FirebaseAuth.instance.currentUser
          ?.updateDisplayName(AppState.userName);
    } catch (_) {}
  }

  static bool get live => fbLive && fbUid != null;

  // ---------- Catalog (services / plans / home banner) ----------
  static Future<void> loadCatalog() async {
    if (!fbLive) return;
    try {
      final sv = await _fs
          .collection('services')
          .where('active', isEqualTo: true)
          .get();
      if (sv.docs.isNotEmpty) {
        final loaded = sv.docs.map((d) {
          final fb = services.where((s) => s.id == d.id);
          return Service.fromFirestore(
              d.id, d.data(), fb.isEmpty ? null : fb.first);
        }).toList();
        services = loaded;
      }
      final pl =
          await _fs.collection('plans').where('active', isEqualTo: true).get();
      if (pl.docs.isNotEmpty) {
        final loaded = pl.docs.map((d) {
          final fb = plans.where((p) => p.id == d.id);
          return Plan.fromFirestore(
              d.id, d.data(), fb.isEmpty ? null : fb.first);
        }).toList()
          ..sort((a, b) => a.visits.compareTo(b.visits));
        plans = loaded;
      }
      final cfg = await _fs.collection('appConfig').doc('homeBanner').get();
      if (cfg.exists) {
        final m = cfg.data()!;
        AppState.banner
          ..pill = (m['pill'] ?? AppState.banner.pill).toString()
          ..heading = (m['heading'] ?? AppState.banner.heading).toString()
          ..sub =
              (m['subheading'] ?? m['sub'] ?? AppState.banner.sub).toString()
          ..cta = (m['cta'] ?? AppState.banner.cta).toString()
          ..imageUrl = m['imageUrl']?.toString()
          ..active = (m['active'] ?? true) == true;
      }
      AppState.catalogLoaded = true;
    } catch (_) {
      // Offline / not seeded yet: local catalog fallback stays in place.
    }
  }

  // ---------- Session: profile + everything the user owns ----------
  static Future<void> loadFor(String uid, {User? authUser}) async {
    fbUid = uid;
    AppState.loadError = '';
    await loadCatalog();
    try {
      // Profile (users/{uid})
      final uref = _fs.collection('users').doc(uid);
      final udoc = await uref.get();
      if (udoc.exists) {
        final m = udoc.data()!;
        // Preserve existing profile fields — never overwrite on every login.
        AppState.userName =
            (m['name'] ?? authUser?.displayName ?? '').toString();
        final existingPhone = (m['phone'] ?? '').toString().trim();
        AppState.userPhone = existingPhone.isNotEmpty
            ? existingPhone
            : (authUser?.phoneNumber ?? '').toString();
        final existingEmail = (m['email'] ?? '').toString().trim();
        AppState.userEmail = existingEmail.isNotEmpty
            ? existingEmail
            : (authUser?.email ?? '').toString();
        final c = m['createdAt'];
        AppState.memberSince = c is Timestamp ? c.toDate() : null;
        // Touch last login only; do not rewrite name/phone/email.
        try {
          await uref.set({
            'lastLoginAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            if (existingPhone.isEmpty &&
                (authUser?.phoneNumber?.isNotEmpty ?? false))
              'phone': authUser!.phoneNumber,
            if (existingEmail.isEmpty && (authUser?.email?.isNotEmpty ?? false))
              'email': authUser!.email,
          }, SetOptions(merge: true));
        } catch (_) {}
      } else {
        AppState.userName = authUser?.displayName ?? '';
        AppState.userPhone = authUser?.phoneNumber ?? '';
        AppState.userEmail = authUser?.email ?? '';
        await uref.set({
          'name': AppState.userName,
          'phone': AppState.userPhone,
          'email': AppState.userEmail,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
          'authProvider': (authUser?.phoneNumber?.isNotEmpty ?? false)
              ? 'phone'
              : (authUser?.providerData.isNotEmpty == true
                  ? authUser!.providerData.first.providerId
                  : 'unknown'),
        });
        AppState.memberSince = DateTime.now();
      }
      AppState.profileLoaded = true;

      try {
        final vs = await _fs
            .collection('vehicles')
            .where('ownerUid', isEqualTo: uid)
            .get();
        AppState.vehicles
          ..clear()
          ..addAll(vs.docs.map((d) {
            final m = d.data();
            return Vehicle(
                d.id,
                (m['nickname'] ?? m['name'] ?? 'Car').toString(),
                (m['category'] ?? 'sedan').toString(),
                (m['make'] ?? '').toString(),
                (m['model'] ?? '').toString(),
                (m['color'] ?? '').toString(),
                (m['registrationNumber'] ?? m['reg'] ?? '').toString(),
                seating: m['seating']?.toString())
              ..isDefault = (m['isDefault'] ?? false) == true;
          }));
      } catch (_) {
        AppState.loadError =
            'Could not load your vehicles. Check connection and retry.';
      }

      // Load each collection independently so a failure later cannot wipe
      // a successfully loaded address list (empty-state flash bug).
      await _reloadAddresses(uid);

      try {
        final bs = await _fs
            .collection('bookings')
            .where('customerUid', isEqualTo: uid)
            .get();
        AppState.bookings
          ..clear()
          ..addAll(bs.docs.map(_bookingFromDoc));
        _sortBookings();
      } catch (_) {
        AppState.loadError =
            'Could not load your bookings. Check connection and retry.';
      }

      try {
        final ss = await _fs
            .collection('subscriptions')
            .where('customerUid', isEqualTo: uid)
            .get();
        AppState.subs
          ..clear()
          ..addAll(ss.docs.map((d) {
            final m = d.data();
            final pl = plans.firstWhere((x) => x.id == m['planId'],
                orElse: () => plans[1]);
            final veh = AppState.vehicles.where((v) => v.id == m['vehicleId']);
            final s = Sub(
                pl,
                veh.isEmpty
                    ? (AppState.primaryVehicle ??
                        Vehicle('', 'Car', 'suv', '', '', '', ''))
                    : veh.first)
              ..id = d.id
              ..status = (m['status'] ?? 'active').toString();
            s.visitsLeft = ((m['visitBalance'] ?? 0) as num).round();
            return s;
          }));
      } catch (_) {}

      try {
        final ns = await _fs
            .collection('notifications')
            .where('recipientUid', isEqualTo: uid)
            .get();
        AppState.notifications
          ..clear()
          ..addAll(ns.docs.map((d) {
            final m = d.data();
            return AppNotification(
                d.id,
                (m['title'] ?? 'Update').toString(),
                (m['body'] ?? '').toString(),
                (m['read'] ?? false) == true,
                m['bookingId']?.toString());
          }));
      } catch (_) {}
    } catch (e) {
      AppState.loadError =
          'Could not load your data. Check connection and retry.';
    }
  }

  static Addr _addrFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return Addr(
        d.id,
        (m['label'] ?? 'Address').toString(),
        (m['line'] ?? m['addressLine'] ?? '').toString(),
        (m['area'] ?? m['locality'] ?? '').toString(),
        (m['areaId'] ?? m['serviceAreaId'] ?? 'kondapur').toString(),
        (m['slot'] ?? m['parkingSlot'] ?? '').toString(),
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
        city: (m['city'] ?? '').toString(),
        postalCode: (m['postalCode'] ?? '').toString(),
        building: (m['building'] ?? '').toString(),
        state: (m['state'] ?? '').toString(),
        country: (m['country'] ?? 'India').toString(),
        formattedAddress:
            (m['formattedAddress'] ?? m['displayName'] ?? '').toString())
      ..isDefault = (m['isDefault'] ?? false) == true;
  }

  /// Replaces [AppState.addresses] only after a successful Firestore read.
  static Future<bool> _reloadAddresses(String uid) async {
    try {
      final ads = await _fs
          .collection('addresses')
          .where('ownerUid', isEqualTo: uid)
          .get();
      AppState.addresses
        ..clear()
        ..addAll(ads.docs.map(_addrFromDoc));
      return true;
    } catch (e) {
      AppState.loadError =
          mapFirestoreError(e, operation: 'load addresses');
      // Keep previously loaded addresses visible.
      return false;
    }
  }

  static Future<bool> reloadAddresses() async {
    if (fbUid == null) return false;
    return _reloadAddresses(fbUid!);
  }

  static void _sortBookings() =>
      AppState.bookings.sort((a, b) => b.when.compareTo(a.when));

  static Booking _bookingFromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final svc = services.firstWhere((s) => s.id == m['serviceId'],
        orElse: () => services[0]);
    final veh = AppState.vehicles.where((v) => v.id == m['vehicleId']);
    final adr = AppState.addresses.where((a) => a.id == m['addressId']);
    final bk = Booking(
      d.id,
      svc,
      veh.isEmpty
          ? (AppState.primaryVehicle ??
              Vehicle('', 'Car', 'suv', '', '', '', ''))
          : veh.first,
      adr.isEmpty
          ? _addrFromServiceLocation(m)
          : adr.first,
      (m['status'] ?? 'confirmed').toString(),
      (m['scheduledAt'] is Timestamp)
          ? (m['scheduledAt'] as Timestamp).toDate()
          : DateTime.now(),
      (m['time'] ?? '10:30 AM').toString(),
      ((((m['priceSnapshot'] ?? const {}) as Map)['totalPaise'] ?? 0) as num)
          .round(),
      svc.price(veh.isEmpty ? 'suv' : veh.first.category),
      (m['paymentMethod'] ?? 'online').toString() == 'cash' ? 'CASH' : 'UPI',
      (m['paymentStatus'] ?? 'pending').toString(),
      (m['bookingType'] ?? 'scheduled').toString(),
    );
    bk.worker = m['workerName']?.toString();
    bk.rating = (m['rating'] as num?)?.round();
    return bk;
  }

  /// Real-time bookings for the signed-in customer (Home + Bookings screens).
  /// Stream failures surface via AppState.loadError so screens can show an
  /// error state with Retry instead of a silently stale list.
  static Stream<List<Booking>> watchBookings() {
    if (!live) return Stream.value(AppState.bookings);
    return _fs
        .collection('bookings')
        .where('customerUid', isEqualTo: fbUid)
        .snapshots()
        .map((snap) {
      AppState.loadError = '';
      AppState.bookings
        ..clear()
        ..addAll(snap.docs.map(_bookingFromDoc));
      _sortBookings();
      return AppState.bookings;
    }).handleError((Object _) {
      AppState.loadError =
          'Could not load your data. Check connection and retry.';
      return AppState.bookings;
    });
  }

  static Future<void> refreshMine() async {
    if (fbUid != null) await loadFor(fbUid!);
  }

  // ---------- Profile ----------
  static Future<void> saveProfile({required String name}) async {
    AppState.userName = name.trim();
    if (!live) return;
    try {
      await _fs.collection('users').doc(fbUid).update({
        'name': AppState.userName,
        'updatedAt': FieldValue.serverTimestamp()
      });
      await FirebaseAuth.instance.currentUser
          ?.updateDisplayName(AppState.userName);
    } catch (_) {}
  }

  static Future<void> requestAccountDeletion() async {
    await saveTicket('Account deletion request', category: 'account');
  }

  // ---------- Bookings ----------
  static Future<void> saveBooking(Booking b) async {
    if (!live) return;
    try {
      await _fs.collection('bookings').doc(b.id).set({
        'customerUid': fbUid,
        'customerName': AppState.userName,
        'customerPhone': AppState.userPhone,
        'vehicleId': b.vehicle.id,
        'vehicleLabel': b.vehicle.fullLabel,
        'vehicleCategory': b.vehicle.category,
        'addressId': b.addr.id,
        'addressLabel':
            '${b.addr.label}${b.addr.area.isNotEmpty ? ' — ${b.addr.area}' : ''}',
        'addressSnapshot': b.addr.displayFormatted,
        'serviceLocation': {
          ...b.addr.toServiceLocationSnapshot(),
          'capturedAt': DateTime.now().toUtc().toIso8601String(),
        },
        'serviceLocationCapturedAt': FieldValue.serverTimestamp(),
        'serviceAreaId': b.addr.areaId,
        'serviceId': b.service.id,
        'serviceName': b.service.name,
        'assignedWorkerUid': null,
        'workerName': null,
        'bookingType': b.type,
        'status': b.status,
        'scheduledAt': Timestamp.fromDate(b.when),
        'time': b.time,
        'estimatedDurationMinutes': 50,
        'priceSnapshot': () {
          // Keep totalPaise identical to Review & Pay / Razorpay order amount.
          // Instant bookings include Wash Now express (₹99). Never invent tax.
          const fee = 2900;
          final express = b.type == 'instant' ? 9900 : 0;
          final discount =
              (b.servicePaise + fee + express - b.totalPaise).clamp(0, 1 << 30);
          return {
            'currency': 'INR',
            'subtotalPaise': b.servicePaise,
            'serviceFeePaise': fee,
            'expressFeePaise': express,
            'discountPaise': discount,
            'taxPaise': 0,
            'totalPaise': b.totalPaise,
            'pricingVersion': 'hyd-2026.10-v1',
            if (discount > 0) 'couponCode': 'WELCOME75',
          };
        }(),
        'paymentMethod': b.payMethod == 'CASH' ? 'cash' : 'online',
        'paymentStatus': b.payStatus,
        'subscriptionId': null,
        'occurrenceId': null,
        'checklistDone': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Online payments: createPaymentOrder Cloud Function creates the
      // authoritative pending payment + Razorpay order. Client must NOT
      // invent a duplicate payments row (or mark anything paid).
      if (b.payMethod == 'CASH') {
        await _fs.collection('payments').add({
          'bookingId': b.id,
          'customerUid': fbUid,
          'customerId': fbUid,
          'customerName': AppState.userName,
          'amountPaise': b.totalPaise,
          'currency': 'INR',
          'paymentGateway': 'cash',
          'method': 'cash',
          'status': 'pending',
          'paymentStatus': 'pending',
          'providerRef': null,
          'razorpaySignatureVerified': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {
      _report('your booking');
    }
  }

  static Future<void> patchBooking(
      String id, Map<String, dynamic> patch) async {
    if (!live) return;
    try {
      await _fs
          .collection('bookings')
          .doc(id)
          .update({...patch, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (_) {
      _report('booking update');
    }
  }

  /// Customer verifies wash completion via trusted Cloud Function (not a
  /// direct status write — rules block client self-complete).
  static Future<void> verifyCompletion(String bookingId, {int? rating}) async {
    if (!live) return;
    await FirebaseFunctions.instance.httpsCallable('verifyCompletion').call({
      'bookingId': bookingId,
      if (rating != null) 'rating': rating,
    });
  }

  // ---------- Vehicles ----------
  static Future<void> saveVehicle(Vehicle v) async {
    if (!live) return;
    try {
      final ref = await _fs.collection('vehicles').add({
        'ownerUid': fbUid,
        'nickname': v.nickname,
        'name': v.nickname,
        'category': v.pricingCategory,
        'seating': v.seating,
        'make': v.make,
        'model': v.model,
        'color': v.color,
        'registrationNumber': v.reg,
        'isDefault': v.isDefault,
        'createdAt': FieldValue.serverTimestamp(),
      });
      v.id = ref.id;
    } catch (_) {
      _report('your vehicle');
    }
  }

  static Future<void> updateVehicle(Vehicle v) async {
    if (!live) return;
    try {
      await _fs.collection('vehicles').doc(v.id).update({
        'nickname': v.nickname,
        'name': v.nickname,
        'category': v.pricingCategory,
        'seating': v.seating,
        'make': v.make,
        'model': v.model,
        'color': v.color,
        'registrationNumber': v.reg,
        'isDefault': v.isDefault,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      _report('vehicle update');
    }
  }

  static Future<void> deleteVehicle(String id) async {
    if (!live) return;
    try {
      await _fs.collection('vehicles').doc(id).delete();
    } catch (_) {}
  }

  static Future<void> setPrimaryVehicle(String id) async {
    for (final v in AppState.vehicles) {
      v.isDefault = v.id == id;
    }
    if (!live) return;
    try {
      final batch = _fs.batch();
      for (final v in AppState.vehicles) {
        batch.update(
            _fs.collection('vehicles').doc(v.id), {'isDefault': v.isDefault});
      }
      await batch.commit();
    } catch (_) {}
  }

  /// Prefer immutable booking.serviceLocation over a live saved address.
  static Addr _addrFromServiceLocation(Map<String, dynamic> m) {
    final sl = (m['serviceLocation'] is Map)
        ? Map<String, dynamic>.from(m['serviceLocation'] as Map)
        : <String, dynamic>{};
    final lat = (sl['latitude'] as num?)?.toDouble() ??
        (m['serviceLatitude'] as num?)?.toDouble();
    final lng = (sl['longitude'] as num?)?.toDouble() ??
        (m['serviceLongitude'] as num?)?.toDouble();
    return Addr(
      (sl['addressId'] ?? m['addressId'] ?? '').toString(),
      (sl['addressLabel'] ?? m['addressLabel'] ?? 'Address').toString(),
      (sl['street'] ?? sl['formattedAddress'] ?? m['addressSnapshot'] ?? '')
          .toString(),
      (sl['locality'] ?? '').toString(),
      (m['serviceAreaId'] ?? 'kondapur').toString(),
      (sl['building'] ?? '').toString(),
      latitude: lat,
      longitude: lng,
      city: (sl['city'] ?? '').toString(),
      postalCode: (sl['postalCode'] ?? '').toString(),
      building: (sl['building'] ?? '').toString(),
      state: (sl['state'] ?? '').toString(),
      country: (sl['country'] ?? 'India').toString(),
      formattedAddress: (sl['formattedAddress'] ?? m['addressSnapshot'] ?? '')
          .toString(),
    );
  }

  // ---------- Addresses ----------
  /// Local optimistic ids used historically: `a` + epoch millis.
  /// Real Firestore auto-ids never match this pattern.
  static bool isPersistedAddressId(String id) {
    if (id.isEmpty) return false;
    if (RegExp(r'^a\d{10,}$').hasMatch(id)) return false;
    return true;
  }

  static Map<String, dynamic> _addressPayload(Addr a, {required String ownerUid}) {
    final payload = <String, dynamic>{
      'ownerUid': ownerUid,
      'label': a.label,
      'line': a.line,
      'addressLine': a.line,
      'area': a.area,
      'locality': a.area,
      'areaId': a.areaId,
      'serviceAreaId': a.areaId,
      'slot': a.slot,
      'parkingSlot': a.slot,
      'isDefault': a.isDefault,
      'city': a.city,
      'postalCode': a.postalCode,
      'building': a.building,
      'state': a.state,
      'country': a.country.isNotEmpty ? a.country : 'India',
      'formattedAddress': a.displayFormatted,
    };
    // Numeric doubles only when valid — never invent city-center coords.
    if (a.hasCoordinates) {
      payload['latitude'] = a.latitude;
      payload['longitude'] = a.longitude;
    }
    return payload;
  }

  static String? _requireOwnerUid() {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid == null || authUid.isEmpty) return null;
    // Keep session pointer aligned with Auth (guards stale fbUid).
    fbUid = authUid;
    return authUid;
  }

  /// Creates a new address document under `addresses/{autoId}`.
  /// Does NOT mutate [AppState.addresses] — caller adds only after success.
  static Future<AddressWriteResult> saveAddress(Addr a) async {
    if (_addressWriteInFlight) {
      return const AddressWriteResult.fail(
          'Save already in progress. Please wait.',
          code: 'in-flight');
    }
    if (!fbLive) {
      return const AddressWriteResult.fail(
          'Cloud sync is unavailable. Restart the app and retry.',
          code: 'offline-config');
    }
    final ownerUid = _requireOwnerUid();
    if (ownerUid == null) {
      return const AddressWriteResult.fail(
          'Please sign in again to save an address.',
          code: 'unauthenticated');
    }
    if (a.hasCoordinates == false &&
        (a.latitude != null || a.longitude != null)) {
      return const AddressWriteResult.fail(
          'Invalid map coordinates. Adjust the pin and retry.',
          code: 'invalid-argument');
    }

    // Soft de-dupe against already-persisted addresses (~11m).
    for (final existing in AppState.addresses) {
      if (!isPersistedAddressId(existing.id)) continue;
      if (a.hasCoordinates &&
          existing.hasCoordinates &&
          (existing.latitude! - a.latitude!).abs() < 0.0001 &&
          (existing.longitude! - a.longitude!).abs() < 0.0001) {
        existing
          ..label = a.label
          ..line = a.line
          ..area = a.area
          ..slot = a.slot
          ..city = a.city
          ..postalCode = a.postalCode
          ..building = a.building
          ..state = a.state
          ..country = a.country
          ..formattedAddress = a.formattedAddress
          ..latitude = a.latitude
          ..longitude = a.longitude;
        final upd = await updateAddress(existing);
        if (upd.ok) a.id = existing.id;
        return upd;
      }
    }

    _addressWriteInFlight = true;
    final sw = Stopwatch()..start();
    final path = 'addresses/(new)';
    try {
      final makeDefault = a.isDefault || AppState.addresses.isEmpty;
      a.isDefault = makeDefault;
      final ref = _fs.collection('addresses').doc();
      final payload = {
        ..._addressPayload(a, ownerUid: ownerUid),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await ref.set(payload);
      a.id = ref.id;
      if (makeDefault) {
        await _setDefaultAddressPointers(ref.id, ownerUid: ownerUid);
      }
      _logAddressOp(operation: 'create', path: 'addresses/${ref.id}', ms: sw.elapsedMilliseconds);
      return AddressWriteResult.ok(addressId: ref.id);
    } catch (e) {
      _logAddressOp(
          operation: 'create', path: path, ms: sw.elapsedMilliseconds, error: e);
      final msg = mapFirestoreError(e, operation: 'save your address');
      onWriteError?.call(msg);
      return AddressWriteResult.fail(msg,
          code: e is FirebaseException ? e.code : 'unknown');
    } finally {
      _addressWriteInFlight = false;
    }
  }

  /// Updates an existing `addresses/{id}` document. Requires a persisted id.
  static Future<AddressWriteResult> updateAddress(Addr a) async {
    if (_addressWriteInFlight) {
      return const AddressWriteResult.fail(
          'Save already in progress. Please wait.',
          code: 'in-flight');
    }
    if (!fbLive) {
      return const AddressWriteResult.fail(
          'Cloud sync is unavailable. Restart the app and retry.',
          code: 'offline-config');
    }
    final ownerUid = _requireOwnerUid();
    if (ownerUid == null) {
      return const AddressWriteResult.fail(
          'Please sign in again to update an address.',
          code: 'unauthenticated');
    }
    if (!isPersistedAddressId(a.id)) {
      // Local-only id from a previous failed optimistic add — create instead.
      return saveAddress(a);
    }

    _addressWriteInFlight = true;
    final sw = Stopwatch()..start();
    final path = 'addresses/${a.id}';
    try {
      var ref = _fs.collection('addresses').doc(a.id);
      final snap = await ref.get();
      if (!snap.exists) {
        // Stale / never-persisted id — create one document (no duplicate list entry).
        ref = _fs.collection('addresses').doc();
        await ref.set({
          ..._addressPayload(a, ownerUid: ownerUid),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        a.id = ref.id;
        _logAddressOp(
            operation: 'create-on-missing',
            path: 'addresses/${ref.id}',
            ms: sw.elapsedMilliseconds);
        return AddressWriteResult.ok(addressId: ref.id);
      }
      final data = snap.data();
      if (data != null && data['ownerUid'] != null && data['ownerUid'] != ownerUid) {
        final msg = mapFirestoreError(
            FirebaseException(
                plugin: 'cloud_firestore', code: 'permission-denied'),
            operation: 'update this address');
        onWriteError?.call(msg);
        return AddressWriteResult.fail(msg, code: 'permission-denied');
      }
      // set+merge keeps legacy fields and avoids NOT_FOUND from update().
      await ref.set({
        ..._addressPayload(a, ownerUid: ownerUid),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _logAddressOp(operation: 'update', path: path, ms: sw.elapsedMilliseconds);
      return AddressWriteResult.ok(addressId: a.id);
    } catch (e) {
      _logAddressOp(
          operation: 'update', path: path, ms: sw.elapsedMilliseconds, error: e);
      final msg = mapFirestoreError(e, operation: 'update this address');
      onWriteError?.call(msg);
      return AddressWriteResult.fail(msg,
          code: e is FirebaseException ? e.code : 'unknown');
    } finally {
      _addressWriteInFlight = false;
    }
  }

  static Future<AddressWriteResult> deleteAddress(String id) async {
    if (!live) {
      return const AddressWriteResult.fail(
          'Cloud sync is unavailable.', code: 'offline-config');
    }
    final ownerUid = _requireOwnerUid();
    if (ownerUid == null) {
      return const AddressWriteResult.fail(
          'Please sign in again to delete an address.',
          code: 'unauthenticated');
    }
    if (!isPersistedAddressId(id)) {
      AppState.addresses.removeWhere((x) => x.id == id);
      return AddressWriteResult.ok(addressId: id);
    }
    final sw = Stopwatch()..start();
    final path = 'addresses/$id';
    try {
      await _fs.collection('addresses').doc(id).delete();
      _logAddressOp(operation: 'delete', path: path, ms: sw.elapsedMilliseconds);
      return AddressWriteResult.ok(addressId: id);
    } catch (e) {
      _logAddressOp(
          operation: 'delete', path: path, ms: sw.elapsedMilliseconds, error: e);
      final msg = mapFirestoreError(e, operation: 'delete this address');
      onWriteError?.call(msg);
      return AddressWriteResult.fail(msg,
          code: e is FirebaseException ? e.code : 'unknown');
    }
  }

  static Future<void> _setDefaultAddressPointers(String id,
      {required String ownerUid}) async {
    final batch = _fs.batch();
    for (final a in AppState.addresses) {
      if (!isPersistedAddressId(a.id)) continue;
      final next = a.id == id;
      a.isDefault = next;
      batch.set(
          _fs.collection('addresses').doc(a.id),
          {'isDefault': next, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true));
    }
    // Also mark the target doc (may not yet be in AppState during create).
    batch.set(
        _fs.collection('addresses').doc(id),
        {'isDefault': true, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true));
    batch.set(
        _fs.collection('users').doc(ownerUid),
        {
          'defaultAddressId': id,
          'selectedAddressId': id,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));
    await batch.commit();
  }

  static Future<AddressWriteResult> setDefaultAddress(String id) async {
    for (final a in AppState.addresses) {
      a.isDefault = a.id == id;
    }
    if (!live) return const AddressWriteResult.ok();
    final ownerUid = _requireOwnerUid();
    if (ownerUid == null) {
      return const AddressWriteResult.fail(
          'Please sign in again to select an address.',
          code: 'unauthenticated');
    }
    if (!isPersistedAddressId(id)) {
      return const AddressWriteResult.fail(
          'Address is not saved yet. Save it first.',
          code: 'failed-precondition');
    }
    final sw = Stopwatch()..start();
    try {
      await _setDefaultAddressPointers(id, ownerUid: ownerUid);
      _logAddressOp(
          operation: 'setDefault',
          path: 'addresses/$id',
          ms: sw.elapsedMilliseconds);
      return AddressWriteResult.ok(addressId: id);
    } catch (e) {
      _logAddressOp(
          operation: 'setDefault',
          path: 'addresses/$id',
          ms: sw.elapsedMilliseconds,
          error: e);
      final msg = mapFirestoreError(e, operation: 'select this address');
      onWriteError?.call(msg);
      return AddressWriteResult.fail(msg,
          code: e is FirebaseException ? e.code : 'unknown');
    }
  }

  // ---------- Subscriptions ----------
  static Future<String?> saveSub(Sub s) async {
    if (!live) return null;
    try {
      final ref = await _fs.collection('subscriptions').add({
        'customerUid': fbUid,
        'vehicleId': s.vehicle.id,
        'vehicleLabel': s.vehicle.label,
        'addressId': AppState.selectedAddress?.id,
        'planId': s.plan.id,
        'planName': s.plan.name,
        'billingMode': s.plan.mode,
        'status': s.status,
        'frequency': 'alternate_days',
        'timeWindow': '07:00-09:00',
        'visitBalance': s.visitsLeft,
        'totalVisits': s.plan.visits,
        'nextVisitAt':
            Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
        'createdAt': FieldValue.serverTimestamp(),
      });
      s.id = ref.id;
      return ref.id;
    } catch (_) {
      return null;
    }
  }

  static Future<void> patchSub(String? id, Map<String, dynamic> patch) async {
    if (!live || id == null) return;
    try {
      await _fs
          .collection('subscriptions')
          .doc(id)
          .update({...patch, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  // ---------- Support / notifications ----------
  static Future<void> saveTicket(String subject,
      {String category = 'general'}) async {
    if (!live) return;
    try {
      await _fs.collection('supportTickets').add({
        'customerUid': fbUid,
        'customerName': AppState.userName,
        'customerPhone': AppState.userPhone,
        'subject': subject,
        'description': subject,
        'category': category,
        'status': 'open',
        'priority': 'normal',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  static Future<void> markNotificationRead(String id) async {
    final n = AppState.notifications.where((x) => x.id == id);
    if (n.isNotEmpty) n.first.read = true;
    if (!live) return;
    try {
      await _fs.collection('notifications').doc(id).update({'read': true});
    } catch (_) {}
  }

  static Future<void> markAllNotificationsRead() async {
    for (final n in AppState.notifications) {
      n.read = true;
    }
    if (!live) return;
    try {
      final batch = _fs.batch();
      for (final n in AppState.notifications) {
        batch.update(_fs.collection('notifications').doc(n.id), {'read': true});
      }
      await batch.commit();
    } catch (_) {}
  }
}
