import 'dart:async';
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
  /// Creates a Razorpay order via the createPaymentOrder Cloud Function,
  /// opens checkout, then verifies the signature server-side (verifyPayment).
  /// Keys live ONLY on the server (Firebase secrets); the app receives the
  /// public keyId from createPaymentOrder. Set keys with:
  ///   firebase functions:secrets:set RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET
  static Future<PaymentResult> payBooking({
    required String bookingId,
    required String name,
    required String email,
    required String phone,
  }) async {
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
    if (keyId.isEmpty || orderId.isEmpty) {
      throw PaymentUnavailable(
          'Payment gateway keys are not configured yet. Please pay cash or pay later.');
    }

    final completer = Completer<PaymentResult>();
    final rzp = Razorpay();
    void cleanup() {
      rzp.clear();
    }

    rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS,
        (PaymentSuccessResponse r) async {
      cleanup();
      try {
        await functions.httpsCallable('verifyPayment').call({
          'bookingId': bookingId,
          'razorpayOrderId': r.orderId ?? orderId,
          'razorpayPaymentId': r.paymentId ?? '',
          'razorpaySignature': r.signature ?? '',
        });
        if (!completer.isCompleted)
          completer.complete(PaymentResult(r.paymentId ?? '', orderId));
      } on FirebaseFunctionsException catch (e) {
        if (!completer.isCompleted)
          completer.completeError(PaymentUnavailable(
              'Payment received but verification failed (${e.code}). Our team will reconcile it — do not pay again.'));
      } catch (_) {
        if (!completer.isCompleted)
          completer.completeError(PaymentUnavailable(
              'Payment received but verification is pending. Our team will reconcile it — do not pay again.'));
      }
    });
    rzp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      cleanup();
      if (!completer.isCompleted)
        completer.completeError(PaymentUnavailable(
            r.message ?? 'Payment was cancelled or failed. You can retry.'));
    });
    rzp.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {});

    rzp.open({
      'key': keyId,
      'amount': amount,
      'currency': 'INR',
      'order_id': orderId,
      'name': 'WashPro',
      'description': 'Doorstep car wash — $bookingId',
      'prefill': {'contact': phone, 'email': email, 'name': name},
      'theme': {'color': '#0A3828'},
    });
    return completer.future;
  }
}
