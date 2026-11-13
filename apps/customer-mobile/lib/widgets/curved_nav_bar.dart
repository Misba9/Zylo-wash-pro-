import 'package:flutter/material.dart';
import '../theme/washpro_theme.dart';

class CurvedNavItem {
  const CurvedNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Premium floating dock navigation with soft curved top corners.
class CurvedBottomNav extends StatelessWidget {
  const CurvedBottomNav({
    super.key,
    required this.index,
    required this.onChanged,
    required this.items,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final List<CurvedNavItem> items;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final isDark = context.isDark;
    final bg = isDark ? WpColors.darkElevated : Colors.white;
    final shadow = isDark
        ? Colors.black.withValues(alpha: .45)
        : WpColors.primary.withValues(alpha: .10);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 10 + (bottom > 0 ? bottom * .35 : 0)),
      child: Material(
        color: Colors.transparent,
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: context.wpLine.withValues(alpha: .85)),
            boxShadow: [
              BoxShadow(
                color: shadow,
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavTile(
                    item: items[i],
                    selected: i == index,
                    onTap: () => onChanged(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final CurvedNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = context.wpPrimary;
    final muted = context.wpMuted;
    final pill = context.isDark ? WpColors.darkSurface : WpColors.mint;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? pill : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? item.activeIcon : item.icon,
              size: 22,
              color: selected ? primary : muted,
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? primary : muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
