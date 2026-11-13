import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washpro_customer/services/phone_auth.dart';

void main() {
  group('toIndianE164', () {
    test('accepts 10-digit Indian mobiles', () {
      expect(toIndianE164('9059899298'), '+919059899298');
      expect(toIndianE164('98765 43210'), '+919876543210');
    });

    test('accepts +91 / 91 prefixed forms', () {
      expect(toIndianE164('+91 9059899298'), '+919059899298');
      expect(toIndianE164('919059899298'), '+919059899298');
      expect(toIndianE164('09059899298'), '+919059899298');
    });

    test('rejects invalid numbers', () {
      expect(toIndianE164('12345'), isNull);
      expect(toIndianE164('5059899298'), isNull); // must start 6–9
      expect(toIndianE164(''), isNull);
      expect(toIndianE164('abcdefghij'), isNull);
    });
  });

  group('formatIndianDisplay', () {
    test('formats E.164 for display', () {
      expect(formatIndianDisplay('+919059899298'), '+91 90598 99298');
    });
  });

  group('redactE164', () {
    test('hides middle digits', () {
      expect(redactE164('+919059899298'), '+91******9298');
    });
  });

  group('friendlyPhoneAuthError', () {
    test('maps invalid OTP distinctly', () {
      final e = FirebaseAuthException(code: 'invalid-verification-code');
      expect(friendlyPhoneAuthError(e), contains('Incorrect OTP'));
    });

    test('maps network distinctly from disabled provider', () {
      final e = FirebaseAuthException(code: 'network-request-failed');
      expect(friendlyPhoneAuthError(e), contains('Network'));
      expect(friendlyPhoneAuthError(e), isNot(contains('not enabled')));
    });

    test('operation-not-allowed with region hint mentions SMS policy', () {
      final e = FirebaseAuthException(
        code: 'operation-not-allowed',
        message: 'SMS region blocked for this request',
      );
      final text = friendlyPhoneAuthError(e);
      expect(text, contains('SMS region'));
      expect(text, contains('India'));
    });

    test('operation-not-allowed without region still points to Console Phone + region',
        () {
      final e = FirebaseAuthException(code: 'operation-not-allowed');
      final text = friendlyPhoneAuthError(e);
      expect(text, contains('operation-not-allowed'));
      expect(text, contains('Sign-in method'));
      expect(text, contains('SMS region'));
    });

    test('quota and too-many-requests are distinct', () {
      expect(
          friendlyPhoneAuthError(FirebaseAuthException(code: 'quota-exceeded')),
          contains('quota'));
      expect(
          friendlyPhoneAuthError(
              FirebaseAuthException(code: 'too-many-requests')),
          contains('Too many'));
    });
  });
}
