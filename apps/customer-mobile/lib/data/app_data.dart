import 'package:flutter/material.dart';

// WashPro data layer — models, catalog and session state.
// No fabricated customer data lives here: AppState lists start EMPTY and are
// populated only from Firestore (WashProRepository) for the signed-in user.
// `services` / `plans` defaults below are the offline catalog fallback only;
// the live catalog is loaded from Firestore collections and replaces them.

bool fbLive = false;
String? fbUid;

// ---------- Catalog models ----------
class Service {
  const Service(this.id, this.name, this.tag, this.icon, this.base, this.mins,
      this.inclusions, this.checklist, this.cashEligible, this.popular,
      [this.priceMap]);
  final String id, name, tag;
  final IconData icon;
  final int base, mins;
  final List<String> inclusions, checklist;
  final bool cashEligible, popular;
  final Map<String, int>? priceMap; // exact per-category paise from Firestore

  int price(String cat) {
    final exact = priceMap?[cat];
    if (exact != null) return exact;
    return base +
        {'hatchback': 0, 'sedan': 5000, 'suv': 15000, 'luxury': 30000}[cat]! +
        (id == 'deep-clean'
            ? {
                'hatchback': 0,
                'sedan': 10000,
                'suv': 25000,
                'luxury': 50000
              }[cat]!
            : 0);
  }

  String duration(String cat) => id == 'deep-clean'
      ? '2.5 hrs'
      : '${mins + (cat == 'suv' ? 10 : cat == 'luxury' ? 20 : 0)} min';

  /// Build from a Firestore `services/{id}` doc (prices stored in rupees).
  factory Service.fromFirestore(
      String id, Map<String, dynamic> m, Service? fallback) {
    int rs(String k) => ((m[k] ?? 0) as num).round() * 100;
    final hasPrices = m['hatchback'] != null;
    return Service(
      id,
      (m['name'] ?? fallback?.name ?? id).toString(),
      (m['tagline'] ?? m['tag'] ?? fallback?.tag ?? '').toString(),
      fallback?.icon ?? Icons.auto_awesome,
      hasPrices ? rs('hatchback') : (fallback?.base ?? 49900),
      ((m['durationMinutes'] ?? m['duration'] ?? fallback?.mins ?? 45) as num)
          .round(),
      fallback?.inclusions ?? const ['Complete service'],
      fallback?.checklist ?? const ['Service', 'Final inspection'],
      (m['cashEligible'] ?? fallback?.cashEligible ?? true) == true,
      (m['popular'] ?? fallback?.popular ?? false) == true,
      hasPrices
          ? {
              'hatchback': rs('hatchback'),
              'sedan': rs('sedan'),
              'suv': rs('suv'),
              'luxury': rs('luxury')
            }
          : fallback?.priceMap,
    );
  }
}

List<Service> services = <Service>[
  const Service(
      'body-wash',
      'Body Wash',
      'Foam wash, wheels & exterior finish',
      Icons.auto_awesome,
      49900,
      40,
      [
        'Foam exterior wash',
        'Tyre & rim cleaning',
        'Glass cleaning',
        'Microfibre dry'
      ],
      [
        'Pre-rinse & foam',
        'Hand wash panels',
        'Tyres & rims',
        'Glass & mirrors',
        'Dry & shine',
        'Final inspection'
      ],
      true,
      false),
  const Service(
      'interior',
      'Interior Refresh',
      'Vacuum, dashboard & surface care',
      Icons.airline_seat_recline_normal,
      69900,
      60,
      [
        'Full vacuum',
        'Dashboard detailing',
        'Door pads & glass',
        'Vent dusting'
      ],
      [
        'Vacuum cabin',
        'Seats & boot',
        'Dashboard & console',
        'Door pads & glass',
        'Vents',
        'Final check'
      ],
      true,
      false),
  const Service(
      'deep-clean',
      'Deep Detail',
      'Complete interior & exterior restoration',
      Icons.verified_user,
      149900,
      150,
      [
        'Body Wash + Interior',
        'Seat & carpet shampoo',
        'Leather condition',
        'AC sanitisation'
      ],
      [
        'Exterior foam & clay',
        'Engine bay gentle clean',
        'Seat shampoo',
        'Leather care',
        'Interior detail',
        'Final QC photos'
      ],
      false,
      true),
];

const addons = [
  ('tyre-polish', 'Tyre Polish', 9900),
  ('fragrance', 'Interior Fragrance', 14900),
  ('leather-care', 'Leather Care', 29900),
  ('ac-sanitise', 'AC Sanitisation', 24900)
];

class Plan {
  const Plan(this.id, this.name, this.kicker, this.visits, this.perWash,
      this.total, this.save, this.mode);
  final String id, name, kicker, mode;
  final int visits, perWash, total, save;

  factory Plan.fromFirestore(
          String id, Map<String, dynamic> m, Plan? fallback) =>
      Plan(
        id,
        (m['name'] ?? fallback?.name ?? id).toString(),
        (m['kicker'] ?? fallback?.kicker ?? '').toString(),
        ((m['visits'] ?? fallback?.visits ?? 0) as num).round(),
        ((m['perWashPaise'] ?? fallback?.perWash ?? 0) as num).round(),
        ((m['totalPaise'] ?? fallback?.total ?? 0) as num).round(),
        ((m['savePercent'] ?? fallback?.save ?? 0) as num).round(),
        (m['billingMode'] ?? m['mode'] ?? fallback?.mode ?? 'prepaid')
            .toString(),
      );
}

List<Plan> plans = <Plan>[
  const Plan('weekly', 'Weekly Shine', 'Best for personal cars', 4, 39900,
      159600, 20, 'prepaid'),
  const Plan('alternate', 'Alternate Days', 'Most loved by commuters', 15,
      23900, 358500, 28, 'prepaid'),
  const Plan('daily', 'Daily Essential', 'Always looking showroom-ready', 26,
      18900, 491400, 34, 'recurring'),
];

// ---------- User-owned models ----------
class Vehicle {
  Vehicle(this.id, this.nickname, this.category, this.make, this.model,
      this.color, this.reg);
  String id, nickname, category, make, model, color, reg;
  bool isDefault = false;
  String get label => '$make $model';
  String get fullLabel => '$make $model · $reg';
}

class Addr {
  Addr(this.id, this.label, this.line, this.area, this.areaId, this.slot);
  String id, label, line, area, areaId, slot;
  bool isDefault = false;
}

class Booking {
  Booking(
      this.id,
      this.service,
      this.vehicle,
      this.addr,
      this.status,
      this.when,
      this.time,
      this.totalPaise,
      this.servicePaise,
      this.payMethod,
      this.payStatus,
      this.type);
  String id, status, time, payMethod, payStatus, type;
  Service service;
  Vehicle vehicle;
  Addr addr;
  DateTime when;
  int totalPaise, servicePaise;
  String? worker;
  int? rating;
  String? providerRef; // Razorpay payment id after verified payment
}

class Sub {
  Sub(this.plan, this.vehicle);
  String? id;
  Plan plan;
  Vehicle vehicle;
  String status = 'active';
  int visitsLeft = 0;
}

class AppNotification {
  AppNotification(this.id, this.title, this.body, this.read, [this.bookingId]);
  String id, title, body;
  bool read;
  String? bookingId;
}

class HomeBanner {
  String pill = 'DOORSTEP DETAILING';
  String heading = 'Your car deserves a fresh start.';
  String sub = 'Expert care, right where you park.';
  String cta = 'Book a wash';
  String? imageUrl;
  bool active = true;
}

// ---------- Session / app state (empty until loaded from backend) ----------
class AppState {
  static String userName = '';
  static String userPhone = '';
  static String userEmail = '';
  static DateTime? memberSince;
  static bool profileLoaded = false;
  static bool catalogLoaded = false;
  static String loadError = '';

  static final vehicles = <Vehicle>[];
  static final addresses = <Addr>[];
  static final bookings = <Booking>[];
  static final subs = <Sub>[];
  static final notifications = <AppNotification>[];
  static final banner = HomeBanner();

  static String get displayName =>
      userName.trim().isNotEmpty ? userName.trim() : 'there';
  static String get firstName => displayName.split(' ').first;
  static String get initials {
    final n = userName.trim();
    if (n.isEmpty) return 'WP';
    final parts = n.split(RegExp(r'\s+'));
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : ''))
        .toUpperCase();
  }

  static Vehicle? get primaryVehicle {
    if (vehicles.isEmpty) return null;
    return vehicles.firstWhere((v) => v.isDefault,
        orElse: () => vehicles.first);
  }

  static Addr? get selectedAddress {
    if (addresses.isEmpty) return null;
    return addresses.firstWhere((a) => a.isDefault,
        orElse: () => addresses.first);
  }

  static int get maxPlanSave =>
      plans.fold(0, (m, p) => p.save > m ? p.save : m);
  static int get unreadCount => notifications.where((n) => !n.read).length;

  static void reset() {
    userName = '';
    userPhone = '';
    userEmail = '';
    memberSince = null;
    profileLoaded = false;
    loadError = '';
    vehicles.clear();
    addresses.clear();
    bookings.clear();
    subs.clear();
    notifications.clear();
  }

  /// Unique, idempotent booking id — safe against double-tap/retry duplicates
  /// because the repository writes it with set() on the same document.
  static String nextId() => 'WP-${DateTime.now().millisecondsSinceEpoch}';
}

const statusLabel = {
  'requested': 'Requested',
  'awaiting_payment': 'Awaiting Payment',
  'confirmed': 'Confirmed',
  'assigned': 'Worker Assigned',
  'en_route': 'On the Way',
  'arrived': 'Arrived',
  'in_progress': 'In Progress',
  'pending_verification': 'Verify Completion',
  'completed': 'Completed',
  'cancelled': 'Cancelled'
};

// ---------- Slot availability (real, time-based) ----------
const slotTimes = [
  '08:00 AM',
  '09:00 AM',
  '10:30 AM',
  '12:00 PM',
  '02:30 PM',
  '04:00 PM'
];

DateTime slotDateTime(DateTime day, String t) {
  final parts = t.split(' ');
  final hm = parts[0].split(':');
  var h = int.parse(hm[0]);
  final min = int.parse(hm[1]);
  final pm = parts[1] == 'PM';
  if (pm && h != 12) h += 12;
  if (!pm && h == 12) h = 0;
  return DateTime(day.year, day.month, day.day, h, min);
}

/// A slot is bookable if it starts at least 45 minutes from now.
bool slotAvailable(DateTime day, String t, [DateTime? now]) =>
    slotDateTime(day, t)
        .isAfter((now ?? DateTime.now()).add(const Duration(minutes: 45)));

String nextSlotLabel([DateTime? now]) {
  final n = now ?? DateTime.now();
  for (final d in [0, 1]) {
    final day = n.add(Duration(days: d));
    for (final t in slotTimes) {
      if (slotAvailable(day, t, n))
        return d == 0 ? 'Today · $t' : 'Tomorrow · $t';
    }
  }
  return 'Tomorrow · ${slotTimes.first}';
}
