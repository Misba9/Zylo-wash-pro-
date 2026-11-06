import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_data.dart';

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
        AppState.userName =
            (m['name'] ?? authUser?.displayName ?? '').toString();
        AppState.userPhone =
            (m['phone'] ?? authUser?.phoneNumber ?? '').toString();
        AppState.userEmail = (m['email'] ?? authUser?.email ?? '').toString();
        final c = m['createdAt'];
        AppState.memberSince = c is Timestamp ? c.toDate() : null;
      } else {
        AppState.userName = authUser?.displayName ?? '';
        AppState.userPhone = authUser?.phoneNumber ?? '';
        AppState.userEmail = authUser?.email ?? '';
        await uref.set({
          'name': AppState.userName,
          'phone': AppState.userPhone,
          'email': AppState.userEmail,
          'createdAt': FieldValue.serverTimestamp(),
        });
        AppState.memberSince = DateTime.now();
      }
      AppState.profileLoaded = true;

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
              m['nickname'] ?? 'Car',
              m['category'] ?? 'suv',
              m['make'] ?? '',
              m['model'] ?? '',
              m['color'] ?? '',
              m['registrationNumber'] ?? '')
            ..isDefault = (m['isDefault'] ?? false) == true;
        }));

      final ads = await _fs
          .collection('addresses')
          .where('ownerUid', isEqualTo: uid)
          .get();
      AppState.addresses
        ..clear()
        ..addAll(ads.docs.map((d) {
          final m = d.data();
          return Addr(
              d.id,
              m['label'] ?? 'Address',
              m['line'] ?? '',
              m['area'] ?? 'Hyderabad',
              m['areaId'] ?? 'kondapur',
              m['slot'] ?? '')
            ..isDefault = (m['isDefault'] ?? false) == true;
        }));

      final bs = await _fs
          .collection('bookings')
          .where('customerUid', isEqualTo: uid)
          .get();
      AppState.bookings
        ..clear()
        ..addAll(bs.docs.map(_bookingFromDoc));
      _sortBookings();

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
    } catch (e) {
      AppState.loadError =
          'Could not load your data. Check connection and retry.';
    }
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
          ? (AppState.selectedAddress ??
              Addr('', 'Address', (m['addressSnapshot'] ?? '').toString(),
                  'Hyderabad', 'kondapur', ''))
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
        'addressLabel': '${b.addr.label} - ${b.addr.area}',
        'addressSnapshot': '${b.addr.line} - ${b.addr.slot}',
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
        'priceSnapshot': {
          'currency': 'INR',
          'subtotalPaise': b.servicePaise + 2900,
          'discountPaise': 7500,
          'taxPaise': 0,
          'totalPaise': b.totalPaise,
          'pricingVersion': 'hyd-2026.10-v1'
        },
        'paymentMethod': b.payMethod == 'CASH' ? 'cash' : 'online',
        'paymentStatus': b.payStatus,
        'subscriptionId': null,
        'occurrenceId': null,
        'checklistDone': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _fs.collection('payments').add({
        'bookingId': b.id,
        'customerUid': fbUid,
        'customerName': AppState.userName,
        'amountPaise': b.totalPaise,
        'method': b.payMethod.toLowerCase(),
        'status': b.payStatus == 'paid' ? 'paid' : 'pending',
        'providerRef': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
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

  // ---------- Vehicles ----------
  static Future<void> saveVehicle(Vehicle v) async {
    if (!live) return;
    try {
      final ref = await _fs.collection('vehicles').add({
        'ownerUid': fbUid,
        'nickname': v.nickname,
        'category': v.category,
        'make': v.make,
        'model': v.model,
        'color': v.color,
        'registrationNumber': v.reg,
        'isDefault': v.isDefault,
        'createdAt': FieldValue.serverTimestamp(),
      });
      v.id = ref.id;
    } catch (_) {}
  }

  static Future<void> updateVehicle(Vehicle v) async {
    if (!live) return;
    try {
      await _fs.collection('vehicles').doc(v.id).update({
        'nickname': v.nickname,
        'category': v.category,
        'make': v.make,
        'model': v.model,
        'color': v.color,
        'registrationNumber': v.reg,
        'isDefault': v.isDefault,
      });
    } catch (_) {}
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

  // ---------- Addresses ----------
  static Future<void> saveAddress(Addr a) async {
    if (!live) return;
    try {
      final ref = await _fs.collection('addresses').add({
        'ownerUid': fbUid,
        'label': a.label,
        'line': a.line,
        'area': a.area,
        'areaId': a.areaId,
        'slot': a.slot,
        'isDefault': a.isDefault,
        'createdAt': FieldValue.serverTimestamp(),
      });
      a.id = ref.id;
    } catch (_) {}
  }

  static Future<void> updateAddress(Addr a) async {
    if (!live) return;
    try {
      await _fs.collection('addresses').doc(a.id).update({
        'label': a.label,
        'line': a.line,
        'area': a.area,
        'areaId': a.areaId,
        'slot': a.slot,
        'isDefault': a.isDefault,
      });
    } catch (_) {}
  }

  static Future<void> deleteAddress(String id) async {
    if (!live) return;
    try {
      await _fs.collection('addresses').doc(id).delete();
    } catch (_) {}
  }

  static Future<void> setDefaultAddress(String id) async {
    for (final a in AppState.addresses) {
      a.isDefault = a.id == id;
    }
    if (!live) return;
    try {
      final batch = _fs.batch();
      for (final a in AppState.addresses) {
        batch.update(
            _fs.collection('addresses').doc(a.id), {'isDefault': a.isDefault});
      }
      await batch.commit();
    } catch (_) {}
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
