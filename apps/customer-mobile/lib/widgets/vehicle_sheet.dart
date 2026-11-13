import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/app_data.dart';
import '../data/repository.dart';
import '../theme/washpro_theme.dart';

/// Polished Add/Edit vehicle sheet — Name, Registration, 5/7 Seater only.
Future<void> showVehicleSheet(
  BuildContext context,
  VoidCallback refresh, {
  Vehicle? existing,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _VehicleSheetBody(existing: existing, refresh: refresh),
  );
}

class _VehicleSheetBody extends StatefulWidget {
  const _VehicleSheetBody({required this.refresh, this.existing});
  final Vehicle? existing;
  final VoidCallback refresh;

  @override
  State<_VehicleSheetBody> createState() => _VehicleSheetBodyState();
}

class _VehicleSheetBodyState extends State<_VehicleSheetBody> {
  late final TextEditingController name;
  late final TextEditingController reg;
  String? seating;
  String? err;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    name = TextEditingController(text: e?.displayName ?? '');
    reg = TextEditingController(text: e?.reg ?? '');
    seating = e?.seating;
    // Legacy vehicles without seating: leave null so user must choose.
  }

  @override
  void dispose() {
    name.dispose();
    reg.dispose();
    super.dispose();
  }

  String _formatReg(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleaned.length < 4) return cleaned;
    // Soft grouping: TS09MX1234 → TS 09 MX 1234 when length allows
    final buf = StringBuffer();
    for (var i = 0; i < cleaned.length; i++) {
      if (i == 2 || i == 4 || i == 6) buf.write(' ');
      buf.write(cleaned[i]);
    }
    return buf.toString().trim();
  }

  bool _validReg(String r) {
    final compact = r.replaceAll(RegExp(r'\s'), '');
    return RegExp(r'^[A-Z]{2}[0-9]{1,2}[A-Z]{0,3}[0-9]{1,4}$').hasMatch(compact) &&
        compact.length >= 6;
  }

  Future<void> _save() async {
    final n = name.text.trim();
    final r = _formatReg(reg.text);
    if (n.length < 2) {
      setState(() => err = 'Enter a vehicle name (e.g. Nexon, Creta)');
      return;
    }
    if (!_validReg(r)) {
      setState(() => err = 'Enter a valid registration (e.g. TS 09 MX 1234)');
      return;
    }
    if (seating != '5' && seating != '7') {
      setState(() => err = 'Select 5 Seater or 7 Seater');
      return;
    }
    setState(() {
      saving = true;
      err = null;
    });
    final pricingCat = Vehicle.pricingCategoryForSeating(seating!);
    try {
      if (widget.existing != null) {
        final v = widget.existing!;
        v.nickname = n;
        v.make = v.make.isEmpty ? n.split(' ').first : v.make;
        v.model = n;
        v.reg = r;
        v.seating = seating;
        v.category = pricingCat;
        await WashProRepository.updateVehicle(v);
      } else {
        final nv = Vehicle(
          'v${DateTime.now().millisecondsSinceEpoch}',
          n,
          pricingCat,
          n.split(' ').first,
          n,
          '',
          r,
          seating: seating,
        );
        if (AppState.vehicles.isEmpty) nv.isDefault = true;
        // Soft duplicate guard by registration
        final dup = AppState.vehicles.any(
            (x) => x.reg.replaceAll(' ', '') == r.replaceAll(' ', ''));
        if (dup) {
          setState(() {
            saving = false;
            err = 'A vehicle with this registration is already saved.';
          });
          return;
        }
        AppState.vehicles.add(nv);
        await WashProRepository.saveVehicle(nv);
      }
      if (mounted) Navigator.pop(context);
      widget.refresh();
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          err = 'Could not save vehicle. Check connection and retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.existing == null ? 'Add Vehicle' : 'Edit Vehicle',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('Only three details — we price by seating capacity.',
                style: TextStyle(color: context.wpMuted, fontSize: 12.5)),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Vehicle name',
                hintText: 'Enter vehicle name',
                prefixIcon: Icon(Icons.directions_car_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reg,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ]')),
                LengthLimitingTextInputFormatter(14),
              ],
              onChanged: (v) {
                final f = _formatReg(v);
                if (f != v) {
                  reg.value = TextEditingValue(
                    text: f,
                    selection: TextSelection.collapsed(offset: f.length),
                  );
                }
              },
              decoration: const InputDecoration(
                labelText: 'Registration number',
                hintText: 'Enter vehicle registration number',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
            ),
            const SizedBox(height: 14),
            Text('Vehicle category',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: context.wpInk)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _SeatCard(
                label: '5 Seater',
                icon: Icons.airline_seat_recline_normal,
                selected: seating == '5',
                onTap: () => setState(() => seating = '5'),
              )),
              const SizedBox(width: 10),
              Expanded(child: _SeatCard(
                label: '7 Seater',
                icon: Icons.airport_shuttle_outlined,
                selected: seating == '7',
                onTap: () => setState(() => seating = '7'),
              )),
            ]),
            if (err != null) ...[
              const SizedBox(height: 10),
              Text(err!, style: const TextStyle(color: WpColors.error)),
            ],
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: saving ? null : _save,
                  child: Text(saving ? 'Saving…' : 'Save'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _SeatCard extends StatelessWidget {
  const _SeatCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? context.wpMint : context.wpCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? context.wpPrimary : context.wpLine,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(children: [
          Icon(icon, color: context.wpPrimary),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: context.wpInk,
                  fontSize: 13.5)),
        ]),
      ),
    );
  }
}
