import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global navigator so deep links / push taps can route from anywhere.
final appNavKey = GlobalKey<NavigatorState>();

// ---------------- Theme (light / dark / system) ----------------
class AppTheme {
  static final mode = ValueNotifier<ThemeMode>(ThemeMode.system);
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    mode.value = switch (p.getString('themeMode')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    final p = await SharedPreferences.getInstance();
    await p.setString(
        'themeMode',
        switch (m) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          _ => 'system',
        });
  }
}

// ---------------- Connectivity (offline / poor network) ----------------
class NetStatus {
  static final online = ValueNotifier<bool>(true);
  static StreamSubscription? _sub;
  static void init() {
    final c = Connectivity();
    c.checkConnectivity().then(_apply).catchError((_) {});
    _sub?.cancel();
    _sub = c.onConnectivityChanged.listen(_apply, onError: (_) {});
  }

  static void _apply(List<ConnectivityResult> r) =>
      online.value = r.any((x) => x != ConnectivityResult.none);
}

// ---------------- Push notifications (FCM) ----------------
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  // Background/terminated delivery is rendered by the system tray from the
  // notification payload sent by the server (Functions / admin sender).
}

class PushService {
  static StreamSubscription? _refreshSub, _msgSub, _tapSub;

  /// Call after sign-in. Requests permission (Android 13+ / iOS), stores the
  /// device token on users/{uid}.fcmToken (allowed by Firestore rules), and
  /// forwards foreground messages + taps to [onMessage] / [onTap].
  /// User preference (Settings → Push notifications). Default ON.
  static Future<bool> enabled() async =>
      (await SharedPreferences.getInstance()).getBool('pushEnabled') ?? true;

  static Future<void> setEnabled(String? uid, bool on) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('pushEnabled', on);
    try {
      if (!on) {
        await FirebaseMessaging.instance.deleteToken();
        if (uid != null) {
          await FirebaseFirestore.instance.collection('users').doc(uid).set(
              {'fcmToken': FieldValue.delete(),
               'updatedAt': FieldValue.serverTimestamp()},
              SetOptions(merge: true));
        }
      } else if (uid != null) {
        await _saveToken(uid, await FirebaseMessaging.instance.getToken());
      }
    } catch (_) {}
  }

  static Future<void> initForUser(String uid,
      {void Function(RemoteMessage m)? onMessage,
      void Function(RemoteMessage m)? onTap}) async {
    if (!await enabled()) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission(alert: true, badge: true, sound: true);
      await _saveToken(uid, await fm.getToken());
      _refreshSub?.cancel();
      _refreshSub = fm.onTokenRefresh.listen((t) => _saveToken(uid, t));
      _msgSub?.cancel();
      if (onMessage != null)
        _msgSub = FirebaseMessaging.onMessage.listen(onMessage);
      _tapSub?.cancel();
      if (onTap != null) {
        _tapSub = FirebaseMessaging.onMessageOpenedApp.listen(onTap);
        final initial = await fm.getInitialMessage();
        if (initial != null) onTap(initial);
      }
    } catch (_) {
      // Push is best-effort: never block the app on FCM setup.
    }
  }

  static Future<void> _saveToken(String uid, String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}

// ---------------- Razorpay online payments ----------------
/// Raised when online checkout cannot run yet (Functions not deployed, or
/// Razorpay keys/secrets not configured on the server). UI falls back to
/// "pay later / pay cash" — a booking is NEVER marked paid client-side.
class PaymentUnavailable implements Exception {
  PaymentUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

class PaymentResult {
  PaymentResult(this.paymentId, this.orderId);
  final String paymentId, orderId;
}

class RazorpayService {
  static bool _checkoutOpen = false;

  /// Last 10 digits for Razorpay prefill.contact.
  static String prefillContact(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) return digits.substring(digits.length - 10);
    return digits;
  }

  /// Checkout options for razorpay_flutter Standard Checkout (v1.4.x).
  ///
  /// Cards-only root causes (addressed here):
  /// 1. Custom `config.display.blocks` + `show_default_blocks: false` drops the
  ///    whole UPI method when no UPI sub-flow is available for the key/account
  ///    (common in Test Mode when Collect is restricted and Intent/QR are Live-only).
  /// 2. Forcing `upi.flows: [intent,collect,qr]` worsened that filter.
  ///
  /// Strategy: keep Razorpay **default** method blocks, only `hide` methods we
  /// do not want, and put UPI before Cards. Do not invent QR / fake UPI UI.
  ///
  /// Availability (Razorpay / NPCI):
  /// - **Test**: UPI Collect VPA (`success@razorpay` / `failure@razorpay`) when
  ///   Collect is still enabled on the merchant account.
  /// - **Live**: UPI Intent (apps + Manifest `<queries>`); QR mainly on wide
  ///   screens (≥ ~485dp) — not expected on typical phones.
  /// - Never mark bookings paid client-side.
  static Map<String, dynamic> checkoutOptions({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String bookingId,
    required String name,
    required String email,
    required String phone,
    String? preferredMethod,
  }) {
    final contact = prefillContact(phone);
    final prefill = <String, dynamic>{
      if (contact.isNotEmpty) 'contact': contact,
      if (email.trim().isNotEmpty) 'email': email.trim(),
      if (name.trim().isNotEmpty) 'name': name.trim(),
    };
    if (preferredMethod == 'upi' || preferredMethod == 'card') {
      prefill['method'] = preferredMethod;
    }
    final checkoutMode = keyId.startsWith('rzp_live_')
        ? 'live'
        : keyId.startsWith('rzp_test_')
            ? 'test'
            : 'unknown';
    return {
      'key': keyId,
      'amount': amountPaise,
      'currency': 'INR',
      'order_id': orderId,
      'name': 'Zylo',
      'description': 'Doorstep car wash — $bookingId',
      'prefill': prefill,
      'config': {
        'display': {
          // No custom blocks — Standard Checkout defaults retain UPI when the
          // account offers Collect (Test) or Intent (Live).
          'hide': [
            {'method': 'emi'},
            {'method': 'netbanking'},
            {'method': 'wallet'},
            {'method': 'paylater'},
            {'method': 'cardless_emi'},
          ],
          'sequence': ['upi', 'card'],
          'preferences': {'show_default_blocks': true},
        },
      },
      'theme': {'color': '#123F36'},
      'retry': {'enabled': true, 'max_count': 1},
      'send_sms_hash': true,
      'notes': {
        'bookingId': bookingId,
        'checkoutMode': checkoutMode,
        'configStrategy': 'default_hide',
      },
    };
  }

  /// Ensure nested maps/lists are plain JSON types for the Android MethodChannel
  /// → `new JSONObject(map)` bridge (avoids odd nested Map encoding).
  static Map<String, dynamic> jsonSafeOptions(Map<String, dynamic> options) {
    return Map<String, dynamic>.from(
      jsonDecode(jsonEncode(options)) as Map<dynamic, dynamic>,
    );
  }

  /// Safe diagnostics — never logs key secret, signature, or full PAN/VPA.
  static void logCheckoutDiag(String event, Map<String, Object?> fields) {
    final parts = fields.entries
        .map((e) => '${e.key}=${e.value}')
        .join(' ');
    debugPrint('[Razorpay] $event $parts');
  }

  /// Creates order via createPaymentOrder, opens Checkout with server amount,
  /// verifies signature via verifyPayment. Never marks paid client-side alone.
  ///
  /// [expectedAmountPaise] must match the trusted booking total (`priceSnapshot.totalPaise`).
  /// Checkout opens only when the server order amount equals that value.
  static Future<PaymentResult> payBooking({
    required String bookingId,
    required String name,
    required String email,
    required String phone,
    required int expectedAmountPaise,
    String? preferredMethod,
  }) async {
    if (_checkoutOpen) {
      throw PaymentUnavailable(
          'Payment checkout is already open. Finish or dismiss it first.');
    }
    if (!NetStatus.online.value) {
      throw PaymentUnavailable(
          'You are offline. Connect to the internet to pay online.');
    }
    if (expectedAmountPaise < 100) {
      throw PaymentUnavailable(
          'Invalid booking amount. Please reopen the booking and try again.');
    }

    final functions = FirebaseFunctions.instance;
    Map<String, dynamic> order;
    try {
      final res = await functions
          .httpsCallable('createPaymentOrder')
          .call({'bookingId': bookingId});
      order = Map<String, dynamic>.from(res.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw PaymentUnavailable(e.message ??
          'Online payments are being activated. Please pay cash or pay later.');
    } catch (_) {
      throw PaymentUnavailable(
          'Online payments are being activated. Please pay cash or pay later.');
    }
    final keyId = (order['keyId'] ?? '').toString();
    final orderId = (order['orderId'] ?? '').toString();
    final amount = ((order['amountPaise'] ?? 0) as num).round();
    final currency = (order['currency'] ?? 'INR').toString();
    final reused = order['reused'] == true;
    if (keyId.isEmpty || orderId.isEmpty || amount < 100) {
      throw PaymentUnavailable(
          'Payment gateway keys are not configured yet. Please pay cash or pay later.');
    }
    if (!keyId.startsWith('rzp_test_') && !keyId.startsWith('rzp_live_')) {
      throw PaymentUnavailable(
          'Payment gateway key is invalid. Please pay cash or pay later.');
    }
    if (amount != expectedAmountPaise) {
      logCheckoutDiag('amountMismatch', {
        'expectedPaise': expectedAmountPaise,
        'orderPaise': amount,
        'bookingId': bookingId,
      });
      throw PaymentUnavailable(
          'Payment amount does not match this booking. Please refresh and try again.');
    }
    final keyMode = keyId.startsWith('rzp_live_')
        ? 'live'
        : keyId.startsWith('rzp_test_')
            ? 'test'
            : 'unknown';
    final orderPrefix =
        orderId.length > 10 ? '${orderId.substring(0, 10)}…' : orderId;
    final opts = jsonSafeOptions(checkoutOptions(
      keyId: keyId,
      orderId: orderId,
      amountPaise: amount,
      bookingId: bookingId,
      name: name,
      email: email,
      phone: phone,
      preferredMethod: preferredMethod,
    ));
    final display = (opts['config'] as Map)['display'] as Map;
    final hideMethods = ((display['hide'] as List?) ?? const [])
        .map((e) => (e as Map)['method']?.toString() ?? '')
        .where((m) => m.isNotEmpty)
        .join('+');
    final sequence = ((display['sequence'] as List?) ?? const [])
        .map((e) => e.toString())
        .join('>');
    final showDefaults =
        (display['preferences'] as Map?)?['show_default_blocks'] == true;
    logCheckoutDiag('orderReady', {
      'mode': keyMode,
      'keyPrefix': keyId.length > 12 ? '${keyId.substring(0, 12)}…' : keyId,
      'order': orderPrefix,
      'amountPaise': amount,
      'currency': currency,
      'reused': reused,
      'preferred': preferredMethod ?? 'auto',
      'sequence': sequence,
      'hide': hideMethods,
      'showDefaultBlocks': showDefaults,
      'upiHidden': hideMethods.split('+').contains('upi'),
      'hasCustomBlocks': display.containsKey('blocks'),
    });

    final completer = Completer<PaymentResult>();
    final rzp = Razorpay();
    var cleaned = false;
    void cleanup() {
      if (cleaned) return;
      cleaned = true;
      _checkoutOpen = false;
      rzp.clear();
    }

    Future<void> reportFailure(String? reason, String? code) async {
      try {
        await functions.httpsCallable('handlePaymentFailure').call({
          'bookingId': bookingId,
          'razorpayOrderId': orderId,
          'reason': reason,
          'code': code,
        });
      } catch (_) {}
    }

    rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) async {
      final payPrefix = (r.paymentId ?? '').length > 10
          ? '${r.paymentId!.substring(0, 10)}…'
          : (r.paymentId ?? '');
      logCheckoutDiag('clientSuccess', {
        'order': orderPrefix,
        'payment': payPrefix,
        'hasSignature': (r.signature ?? '').isNotEmpty,
      });
      try {
        await functions.httpsCallable('verifyPayment').call({
          'bookingId': bookingId,
          'razorpayOrderId': r.orderId ?? orderId,
          'razorpayPaymentId': r.paymentId ?? '',
          'razorpaySignature': r.signature ?? '',
        });
        logCheckoutDiag('verifyOk', {'order': orderPrefix, 'bookingId': bookingId});
        cleanup();
        if (!completer.isCompleted) {
          completer.complete(PaymentResult(r.paymentId ?? '', orderId));
        }
      } on FirebaseFunctionsException catch (e) {
        logCheckoutDiag('verifyFail', {
          'order': orderPrefix,
          'code': e.code,
        });
        cleanup();
        if (!completer.isCompleted) {
          completer.completeError(PaymentUnavailable(
              'Payment received but verification failed (${e.code}). Our team will reconcile it — do not pay again.'));
        }
      } catch (_) {
        logCheckoutDiag('verifyPending', {'order': orderPrefix});
        cleanup();
        if (!completer.isCompleted) {
          completer.completeError(PaymentUnavailable(
              'Payment received but verification is pending. Our team will reconcile it — do not pay again.'));
        }
      }
    });
    rzp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) async {
      final rawMsg = r.message ?? '';
      final lower = rawMsg.toLowerCase();
      final looksLikeInvalidTestQr = keyMode == 'test' &&
          (lower.contains('upi id is invalid') ||
              lower.contains('could not load banking') ||
              lower.contains('cannot pay with this qr') ||
              lower.contains('invalid vpa'));
      logCheckoutDiag('clientError', {
        'order': orderPrefix,
        'mode': keyMode,
        'code': r.code?.toString() ?? '',
        'looksLikeInvalidTestQr': looksLikeInvalidTestQr,
        // message may contain user-facing cancel text; truncate only.
        'message': rawMsg.length > 80 ? '${rawMsg.substring(0, 80)}…' : rawMsg,
      });
      await reportFailure(r.message, r.code?.toString());
      cleanup();
      if (!completer.isCompleted) {
        completer.completeError(PaymentUnavailable(looksLikeInvalidTestQr
            ? 'This is Razorpay Test Mode — QR codes cannot be paid with Google Pay or PhonePe. Use a test card, or UPI ID success@razorpay if Collect is enabled. Real UPI QR needs Live Mode keys.'
            : (rawMsg.isNotEmpty
                ? rawMsg
                : 'Payment was cancelled or failed. You can retry.')));
      }
    });
    rzp.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
      logCheckoutDiag('externalWallet', {'wallet': r.walletName ?? ''});
    });

    _checkoutOpen = true;
    try {
    logCheckoutDiag('openCheckout', {
      'mode': keyMode,
      'order': orderPrefix,
      'amountPaise': amount,
      'currency': 'INR',
      // Test Checkout may still render a QR; real UPI apps cannot pay it.
      'realUpiQrPayable': keyMode == 'live',
      'testHint': keyMode == 'test'
          ? 'use_card_or_success@razorpay_not_gpay_scan'
          : 'intent_or_live_qr',
    });
    rzp.open(opts);
    } catch (e) {
      logCheckoutDiag('openFailed', {'error': e.runtimeType.toString()});
      cleanup();
      throw PaymentUnavailable(
          'Could not open Razorpay checkout. Please try again.');
    }
    return completer.future;
  }

  /// Poll trusted payment status after app restart mid-checkout.
  static Future<Map<String, dynamic>> getStatus(String bookingId) async {
    final res = await FirebaseFunctions.instance
        .httpsCallable('getPaymentStatus')
        .call({'bookingId': bookingId});
    return Map<String, dynamic>.from(res.data as Map);
  }
}
