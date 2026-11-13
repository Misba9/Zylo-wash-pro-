import 'package:flutter/material.dart';
import '../data/app_data.dart';
import '../theme/washpro_theme.dart';

typedef BookingFormatter = String Function(DateTime d);
typedef MoneyFormatter = String Function(int paise);
typedef StatusPillBuilder = Widget Function(String status);

/// Home / bookings list card for an upcoming wash — theme-aware.
class UpcomingBookingCard extends StatelessWidget {
  const UpcomingBookingCard({
    super.key,
    required this.booking,
    required this.onOpen,
    required this.formatDate,
    required this.formatMoney,
    required this.statusPill,
    this.months = const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ],
  });

  final Booking booking;
  final VoidCallback onOpen;
  final BookingFormatter formatDate;
  final MoneyFormatter formatMoney;
  final StatusPillBuilder statusPill;
  final List<String> months;

  String get _payLabel {
    final p = booking.payStatus.toLowerCase();
    if (p == 'paid') return 'Paid';
    if (booking.payMethod == 'CASH') {
      if (p == 'collected') return 'Cash collected';
      return 'Cash after wash';
    }
    if (p.contains('verif')) return 'Verification pending';
    if (p == 'failed') return 'Payment failed';
    return 'Awaiting payment';
  }

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final ink = context.wpInk;
    final muted = context.wpMuted;
    final card = context.wpCard;
    final line = context.wpLine;
    final mint = context.wpMint;
    final primary = context.wpPrimary;

    return Material(
      color: card,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: mint,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${b.when.day}',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: primary,
                          ),
                        ),
                        Text(
                          months[b.when.month - 1].toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            statusPill(b.status),
                            Text(
                              b.time,
                              style: TextStyle(
                                color: muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          b.service.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: ink,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            b.vehicle.displayName,
                            if (b.vehicle.reg.trim().isNotEmpty) b.vehicle.reg,
                          ].join(' · '),
                          style: TextStyle(
                            color: muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                formatDate(b.when),
                style: TextStyle(color: muted, fontSize: 12.5),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (b.addr.label.trim().isNotEmpty) b.addr.label,
                  if (b.addr.slot.trim().isNotEmpty) b.addr.slot,
                ].where((s) => s.trim().isNotEmpty).join(' · '),
                style: TextStyle(color: muted, fontSize: 12.5),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (b.addr.line.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  b.addr.line,
                  style: TextStyle(color: muted, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: mint,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _payLabel,
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatMoney(b.totalPaise),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: ink,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onOpen,
                    child: Text(
                      'View details',
                      style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
