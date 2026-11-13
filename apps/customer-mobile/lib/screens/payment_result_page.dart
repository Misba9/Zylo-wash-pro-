import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../theme/washpro_theme.dart';

enum PaymentUiOutcome {
  processing,
  successful,
  failed,
  cancelled,
  verificationPending,
  cashPending,
}

/// Clear payment / booking outcome screen — never claims success while verifying.
class PaymentResultPage extends StatelessWidget {
  const PaymentResultPage({
    super.key,
    required this.booking,
    required this.outcome,
    required this.amountLabel,
    this.message,
    this.onPrimary,
    this.primaryLabel,
    this.onSecondary,
    this.secondaryLabel,
  });

  final Booking booking;
  final PaymentUiOutcome outcome;
  final String amountLabel;
  final String? message;
  final VoidCallback? onPrimary;
  final String? primaryLabel;
  final VoidCallback? onSecondary;
  final String? secondaryLabel;

  (String title, String subtitle, IconData icon, Color accent) get _copy {
    switch (outcome) {
      case PaymentUiOutcome.processing:
        return (
          'Payment processing',
          'Secure checkout is open. Do not close the app until Razorpay finishes.',
          Icons.hourglass_top_rounded,
          WpColors.accent,
        );
      case PaymentUiOutcome.successful:
        return (
          'Payment successful',
          'Your payment was verified securely. Booking is confirmed.',
          Icons.check_circle_rounded,
          WpColors.secondary,
        );
      case PaymentUiOutcome.failed:
        return (
          'Payment failed',
          'No charge was completed. You can retry safely — duplicate payments are blocked server-side.',
          Icons.error_outline_rounded,
          WpColors.error,
        );
      case PaymentUiOutcome.cancelled:
        return (
          'Payment cancelled',
          'Checkout was closed before payment completed. Your booking is still awaiting payment.',
          Icons.cancel_outlined,
          WpColors.accent,
        );
      case PaymentUiOutcome.verificationPending:
        return (
          'Verification pending',
          'Payment may have been received but is not confirmed yet. Do not pay again — we will reconcile it.',
          Icons.verified_user_outlined,
          WpColors.accent,
        );
      case PaymentUiOutcome.cashPending:
        return (
          'Cash payment pending',
          'Pay the washing expert after the service. Online checkout was not used.',
          Icons.payments_outlined,
          WpColors.secondary,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    final ink = context.wpInk;
    final muted = context.wpMuted;
    final card = context.wpCard;
    final line = context.wpLine;

    return Scaffold(
      backgroundColor: context.wpBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ZYLO',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: .6,
                    color: ink,
                    fontSize: 16,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: copy.$4.withValues(alpha: .14),
                ),
                child: outcome == PaymentUiOutcome.processing
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: CircularProgressIndicator(color: copy.$4),
                      )
                    : Icon(copy.$3, size: 42, color: copy.$4),
              ),
              const SizedBox(height: 22),
              Text(
                copy.$1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: ink,
                  letterSpacing: -.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message ?? copy.$2,
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, height: 1.45, fontSize: 14),
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(booking.service.name,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: ink)),
                    const SizedBox(height: 4),
                    Text(
                      '${booking.vehicle.displayName}'
                      '${booking.vehicle.reg.trim().isNotEmpty ? ' · ${booking.vehicle.reg}' : ''}',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('Amount',
                            style: TextStyle(color: muted, fontSize: 13)),
                        const Spacer(),
                        Text(amountLabel,
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                color: ink)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Booking ${booking.id}',
                        style: TextStyle(color: muted, fontSize: 12)),
                  ],
                ),
              ),
              const Spacer(),
              if (onPrimary != null)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: onPrimary,
                    style: FilledButton.styleFrom(
                      backgroundColor: WpColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(primaryLabel ?? 'Continue',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ),
              if (onSecondary != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: onSecondary,
                    child: Text(secondaryLabel ?? 'Back',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
