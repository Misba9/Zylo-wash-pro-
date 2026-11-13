import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

/// Result of a successful OTP send (mobile / iOS). Web uses [WebPhoneSession].
/// Named to avoid clashing with firebase_auth's PhoneCodeSent typedef.
class PhoneOtpSession {
  PhoneOtpSession({
    required this.verificationId,
    required this.resendToken,
    required this.e164,
  });
  final String verificationId;
  final int? resendToken;
  final String e164;
}

/// Web confirmation session (Firebase reCAPTCHA handled by the SDK).
class WebPhoneSession {
  WebPhoneSession(this.confirmation, this.e164);
  final ConfirmationResult confirmation;
  final String e164;
}

/// Normalises an Indian mobile number to E.164 (+91XXXXXXXXXX).
/// Accepts 10 digits, 91XXXXXXXXXX, or +91XXXXXXXXXX. Returns null if invalid.
String? toIndianE164(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  String ten;
  if (digits.length == 10) {
    ten = digits;
  } else if (digits.length == 12 && digits.startsWith('91')) {
    ten = digits.substring(2);
  } else if (digits.length == 11 && digits.startsWith('0')) {
    ten = digits.substring(1);
  } else {
    return null;
  }
  // Indian mobiles start with 6–9.
  if (!RegExp(r'^[6-9]\d{9}$').hasMatch(ten)) return null;
  return '+91$ten';
}

String formatIndianDisplay(String e164) {
  final d = e164.replaceAll(RegExp(r'\D'), '');
  final ten = d.length >= 10 ? d.substring(d.length - 10) : d;
  if (ten.length != 10) return e164;
  return '+91 ${ten.substring(0, 5)} ${ten.substring(5)}';
}

/// Redacts an E.164 number for logs: +919059899298 → +91******9298
String redactE164(String e164) {
  final d = e164.replaceAll(RegExp(r'\D'), '');
  if (d.length < 4) return '***';
  final last4 = d.substring(d.length - 4);
  final cc = d.length > 10 ? d.substring(0, d.length - 10) : '';
  return '+$cc******$last4';
}

void _logPhoneAuth(String event, {String? code, String? message, String? e164}) {
  final project = Firebase.apps.isEmpty
      ? '(no-app)'
      : Firebase.app().options.projectId;
  final appId = Firebase.apps.isEmpty ? '' : Firebase.app().options.appId;
  final parts = <String>[
    '[PhoneAuth]',
    event,
    'project=$project',
    if (appId.isNotEmpty) 'appId=$appId',
    'platform=${kIsWeb ? 'web' : 'mobile'}',
    if (e164 != null) 'phone=${redactE164(e164)}',
    if (code != null) 'code=$code',
    if (message != null && message.isNotEmpty) 'message=$message',
  ];
  debugPrint(parts.join(' '));
}

/// Maps Firebase Auth errors to clear user copy.
/// Never treats a local flag as "Phone disabled" — only Firebase error codes/messages.
String friendlyPhoneAuthError(FirebaseAuthException e) {
  final msg = (e.message ?? '').toLowerCase();
  _logPhoneAuth('error', code: e.code, message: e.message);

  switch (e.code) {
    case 'invalid-phone-number':
      return 'Enter a valid 10-digit Indian mobile number.';
    case 'too-many-requests':
      return 'Too many attempts. Please wait a few minutes and try again.';
    case 'quota-exceeded':
      return 'SMS quota exceeded for today. Please try again later.';
    case 'session-expired':
    case 'code-expired':
      return 'This OTP has expired. Request a new code.';
    case 'invalid-verification-code':
      return 'Incorrect OTP. Please check and try again.';
    case 'invalid-verification-id':
      return 'Verification session expired. Request a new OTP.';
    case 'network-request-failed':
      return 'Network error. Check your connection and try again.';
    case 'captcha-check-failed':
      return 'reCAPTCHA verification failed. Please try again.';
    case 'missing-client-identifier':
      return 'Phone auth setup incomplete for this build. Add Android SHA-1/SHA-256 in Firebase Console → Project settings.';
    case 'app-not-authorized':
      return 'This app build is not authorised. Add the signing SHA-1/SHA-256 for com.washpro.customer in Firebase Console.';
    case 'billing-not-enabled':
      return 'SMS billing is not enabled on this Firebase project (Blaze plan required for live SMS).';
    case 'user-disabled':
      return 'This account has been disabled. Contact support.';
    case 'operation-not-allowed':
      // Firebase often returns this for disabled Phone provider OR blocked SMS regions.
      if (msg.contains('region') ||
          msg.contains('sms') ||
          msg.contains('blocked')) {
        return 'SMS to this country is blocked. In Firebase Console → Authentication → Settings → SMS region policy, allow India (IN).';
      }
      return 'Firebase rejected Phone sign-in (operation-not-allowed). In Console → Authentication → Sign-in method, enable Phone, then allow India under SMS region policy. Test numbers are configured only in Console — never in the app.';
    default:
      return 'Could not verify phone (${e.code}). Please try again.';
  }
}

/// Firebase Phone Authentication helpers. Never logs OTP codes or tokens.
class PhoneAuthService {
  static Future<User?> _signIn(PhoneAuthCredential cred) async {
    final result = await FirebaseAuth.instance.signInWithCredential(cred);
    return result.user;
  }

  /// Starts phone verification on Android / iOS via [FirebaseAuth.verifyPhoneNumber].
  /// [onAutoVerified] is called when Play Services auto-retrieves the SMS.
  static Future<PhoneOtpSession> verifyPhoneNumber({
    required String e164,
    int? forceResendingToken,
    void Function(User user)? onAutoVerified,
    Duration timeout = const Duration(seconds: 60),
  }) {
    final completer = Completer<PhoneOtpSession>();
    _logPhoneAuth('verifyPhoneNumber.start', e164: e164);

    FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: e164,
      timeout: timeout,
      forceResendingToken: forceResendingToken,
      verificationCompleted: (PhoneAuthCredential credential) async {
        _logPhoneAuth('verificationCompleted', e164: e164);
        try {
          final user = await _signIn(credential);
          if (user != null) onAutoVerified?.call(user);
        } catch (e) {
          _logPhoneAuth('autoSignIn.failed',
              message: e.runtimeType.toString());
          // Auto-retrieval sign-in failed; user can still enter OTP manually
          // once codeSent has completed.
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        _logPhoneAuth('verificationFailed',
            code: e.code, message: e.message, e164: e164);
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        _logPhoneAuth('codeSent', e164: e164);
        if (!completer.isCompleted) {
          completer.complete(PhoneOtpSession(
            verificationId: verificationId,
            resendToken: resendToken,
            e164: e164,
          ));
        }
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _logPhoneAuth('codeAutoRetrievalTimeout', e164: e164);
        // Auto-retrieval window closed; manual OTP entry still works.
        if (!completer.isCompleted) {
          completer.complete(PhoneOtpSession(
            verificationId: verificationId,
            resendToken: forceResendingToken,
            e164: e164,
          ));
        }
      },
    );

    return completer.future;
  }

  /// Web: uses Firebase reCAPTCHA (visible/invisible via SDK). Do not bypass.
  static Future<WebPhoneSession> signInWithPhoneNumberWeb(String e164) async {
    if (!kIsWeb) {
      throw StateError('signInWithPhoneNumberWeb is web-only');
    }
    _logPhoneAuth('signInWithPhoneNumberWeb.start', e164: e164);
    try {
      final confirmation =
          await FirebaseAuth.instance.signInWithPhoneNumber(e164);
      _logPhoneAuth('signInWithPhoneNumberWeb.codeSent', e164: e164);
      return WebPhoneSession(confirmation, e164);
    } on FirebaseAuthException catch (e) {
      _logPhoneAuth('signInWithPhoneNumberWeb.failed',
          code: e.code, message: e.message, e164: e164);
      rethrow;
    }
  }

  static Future<User?> confirmCode({
    required String verificationId,
    required String smsCode,
  }) async {
    _logPhoneAuth('confirmCode');
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );
      return _signIn(cred);
    } on FirebaseAuthException catch (e) {
      _logPhoneAuth('confirmCode.failed', code: e.code, message: e.message);
      rethrow;
    }
  }

  static Future<User?> confirmWebCode(
      ConfirmationResult confirmation, String smsCode) async {
    _logPhoneAuth('confirmWebCode');
    try {
      final result = await confirmation.confirm(smsCode.trim());
      return result.user;
    } on FirebaseAuthException catch (e) {
      _logPhoneAuth('confirmWebCode.failed',
          code: e.code, message: e.message);
      rethrow;
    }
  }
}
