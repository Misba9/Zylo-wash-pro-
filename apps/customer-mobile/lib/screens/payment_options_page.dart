import 'package:flutter/material.dart';
import '../theme/washpro_theme.dart';

/// Online methods shown on the Zylo Payment Options screen.
/// Maps to Razorpay Checkout `prefill.method` values `upi` / `card`.
enum OnlinePayMethod { upi, card }

extension OnlinePayMethodX on OnlinePayMethod {
  String get razorpayPrefill => this == OnlinePayMethod.upi ? 'upi' : 'card';
  String get bookingLabel => this == OnlinePayMethod.upi ? 'UPI' : 'CARD';
}

/// Minimal payment method picker — UPI and Cards only.
/// Returns [OnlinePayMethod] via [Navigator.pop] when Continue is tapped.
class PaymentOptionsPage extends StatefulWidget {
  const PaymentOptionsPage({
    super.key,
    required this.amountPaise,
    this.offerLabel,
    this.initial = OnlinePayMethod.upi,
  });

  final int amountPaise;

  /// Shown only when a real applied/available offer label is provided.
  final String? offerLabel;
  final OnlinePayMethod initial;

  @override
  State<PaymentOptionsPage> createState() => _PaymentOptionsState();
}

class _PaymentOptionsState extends State<PaymentOptionsPage> {
  late OnlinePayMethod _selected = widget.initial;
  bool _submitting = false;

  String get _totalLabel {
    final rupees = widget.amountPaise / 100;
    if (rupees == rupees.roundToDouble()) {
      return '₹${rupees.round()}';
    }
    return '₹${rupees.toStringAsFixed(2)}';
  }

  void _continue() {
    if (_submitting) return;
    setState(() => _submitting = true);
    Navigator.pop(context, _selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ink = isDark ? WpColors.darkText : WpColors.ink;
    final muted = isDark ? WpColors.darkMuted : WpColors.muted;
    final line = isDark ? WpColors.darkLine : WpColors.line;
    final surface = isDark ? WpColors.darkSurface : Colors.white;
    final scaffold = theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: scaffold,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        size: 18, color: ink),
                  ),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: WpColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.directions_car_filled_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text('ZYLO',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: .6,
                          color: ink)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Text('Payment Options',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: ink,
                          letterSpacing: -.3)),
                  const SizedBox(height: 6),
                  Text('Choose how you want to pay securely.',
                      style: TextStyle(color: muted, fontSize: 14, height: 1.35)),
                  if (widget.offerLabel != null &&
                      widget.offerLabel!.trim().isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text('Available Offers',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: ink)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? WpColors.darkElevated
                            : WpColors.mint,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: line),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.local_offer_outlined,
                              color: WpColors.accent, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(widget.offerLabel!,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: ink,
                                    fontSize: 13.5)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _MethodCard(
                    selected: _selected == OnlinePayMethod.upi,
                    onTap: _submitting
                        ? null
                        : () => setState(() => _selected = OnlinePayMethod.upi),
                    icon: Icons.smartphone_rounded,
                    title: 'UPI',
                    subtitle:
                        'Google Pay · PhonePe · Paytm · Other supported apps',
                    popular: true,
                    trailing: const _BrandChips(labels: [
                      'GPay',
                      'PhonePe',
                      'Paytm',
                      'BHIM',
                    ]),
                  ),
                  const SizedBox(height: 12),
                  _MethodCard(
                    selected: _selected == OnlinePayMethod.card,
                    onTap: _submitting
                        ? null
                        : () =>
                            setState(() => _selected = OnlinePayMethod.card),
                    icon: Icons.credit_card_rounded,
                    title: 'Cards',
                    subtitle: 'Credit Card · Debit Card',
                    trailing: const _BrandChips(labels: [
                      'Visa',
                      'Mastercard',
                      'RuPay',
                    ]),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              decoration: BoxDecoration(
                color: surface,
                border: Border(top: BorderSide(color: line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('Total payable',
                          style: TextStyle(
                              color: muted,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                      const Spacer(),
                      Text(_totalLabel,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                              color: ink)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: _submitting ? null : _continue,
                      style: FilledButton.styleFrom(
                        backgroundColor: WpColors.primary,
                        disabledBackgroundColor:
                            WpColors.primary.withValues(alpha: .5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        _submitting ? 'Opening checkout…' : 'Continue',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 14, color: muted),
                      const SizedBox(width: 6),
                      Text('Secure payments powered by Razorpay',
                          style: TextStyle(color: muted, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.selected,
    required this.onTap,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.popular = false,
  });

  final bool selected;
  final VoidCallback? onTap;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final bool popular;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? WpColors.darkText : WpColors.ink;
    final muted = isDark ? WpColors.darkMuted : WpColors.muted;
    final bg = isDark ? WpColors.darkSurface : Colors.white;
    final border = selected
        ? WpColors.secondary
        : (isDark ? WpColors.darkLine : WpColors.line);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border, width: selected ? 1.8 : 1),
            boxShadow: [
              BoxShadow(
                color: WpColors.primary.withValues(alpha: isDark ? .2 : .04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isDark
                          ? WpColors.darkElevated
                          : WpColors.mintBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: WpColors.secondary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(title,
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: ink)),
                            if (popular) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: WpColors.secondary,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text('Popular',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(subtitle,
                            style: TextStyle(
                                color: muted, fontSize: 12.5, height: 1.3)),
                      ],
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: selected ? WpColors.secondary : muted,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandChips extends StatelessWidget {
  const _BrandChips({required this.labels});
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? WpColors.darkElevated : WpColors.mintBg;
    final fg = isDark ? WpColors.darkText : WpColors.primary;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: labels
          .map((l) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(l,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: fg)),
              ))
          .toList(),
    );
  }
}
