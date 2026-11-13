import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Zylo brand design tokens — light & dark.
class WpColors {
  static const primary = Color(0xFF123F36);
  static const secondary = Color(0xFF2A6B5C);
  static const accent = Color(0xFFC49A45);
  static const highlight = Color(0xFF65BDA5);
  static const mint = Color(0xFFDFF3E7);
  static const mintBg = Color(0xFFF2F7F3);

  static const ink = Color(0xFF122019);
  static const muted = Color(0xFF71857A);
  static const line = Color(0xFFE4EEE7);

  // Dark surfaces
  static const darkBg = Color(0xFF101A17);
  static const darkSurface = Color(0xFF182722);
  static const darkElevated = Color(0xFF20352D);
  static const darkText = Color(0xFFF2F5F3);
  static const darkMuted = Color(0xFFAAB8B1);
  static const darkLine = Color(0xFF30433B);
  static const error = Color(0xFFEF6A5B);

  static const radiusCard = 22.0;
  static const radiusBtn = 14.0;
  static const radiusPill = 999.0;
}

class WashProTheme {
  static ThemeData get light {
    final scheme = ColorScheme.light(
      primary: WpColors.primary,
      onPrimary: Colors.white,
      secondary: WpColors.secondary,
      onSecondary: Colors.white,
      tertiary: WpColors.accent,
      surface: Colors.white,
      onSurface: WpColors.ink,
      surfaceContainerHighest: WpColors.mint,
      outline: WpColors.line,
      error: WpColors.error,
      onError: Colors.white,
    );
    return _base(scheme, Brightness.light, WpColors.mintBg, WpColors.ink);
  }

  static ThemeData get dark {
    final scheme = ColorScheme.dark(
      primary: WpColors.secondary,
      onPrimary: Colors.white,
      secondary: WpColors.highlight,
      onSecondary: WpColors.darkBg,
      tertiary: WpColors.accent,
      surface: WpColors.darkSurface,
      onSurface: WpColors.darkText,
      surfaceContainerHighest: WpColors.darkElevated,
      outline: WpColors.darkLine,
      error: WpColors.error,
      onError: Colors.white,
    );
    return _base(scheme, Brightness.dark, WpColors.darkBg, WpColors.darkText);
  }

  static ThemeData _base(
      ColorScheme scheme, Brightness brightness, Color scaffold, Color fg) {
    final isDark = brightness == Brightness.dark;
    final muted = isDark ? WpColors.darkMuted : WpColors.muted;
    final card = isDark ? WpColors.darkSurface : Colors.white;
    final inputFill = isDark ? WpColors.darkElevated : Colors.white;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      primaryColor: scheme.primary,
      dividerColor: scheme.outline,
      cardColor: card,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: fg,
        centerTitle: true,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: fg,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
        iconTheme: IconThemeData(color: fg),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WpColors.radiusCard),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        modalBackgroundColor: card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? WpColors.darkElevated : WpColors.primary,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        hintStyle: TextStyle(color: muted),
        labelStyle: TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: WpColors.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WpColors.radiusBtn),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WpColors.radiusBtn),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? WpColors.highlight : WpColors.secondary,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WpColors.radiusBtn),
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? scheme.primary : null),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.all(scheme.primary),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? scheme.primary : muted),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? scheme.primary.withValues(alpha: .35)
                : scheme.outline),
      ),
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: scheme.primary),
      dividerTheme: DividerThemeData(color: scheme.outline, thickness: 1),
      iconTheme: IconThemeData(color: fg),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: fg,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: isDark ? WpColors.darkElevated : WpColors.mint,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 11,
              fontWeight: s.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
              color: s.contains(WidgetState.selected) ? scheme.primary : muted,
            )),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: fg, fontSize: 16),
        bodyMedium: TextStyle(color: fg, fontSize: 14),
        bodySmall: TextStyle(color: muted, fontSize: 12.5),
        titleLarge: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 22),
        titleMedium: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 17),
        titleSmall: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14),
        labelLarge: TextStyle(color: muted, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Theme-aware surface colors for widgets that still use design tokens.
extension WpThemeX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get wpCard =>
      isDark ? WpColors.darkSurface : Colors.white;
  Color get wpBg => Theme.of(this).scaffoldBackgroundColor;
  Color get wpInk => Theme.of(this).colorScheme.onSurface;
  Color get wpMuted =>
      isDark ? WpColors.darkMuted : WpColors.muted;
  Color get wpLine => Theme.of(this).colorScheme.outline;
  Color get wpPrimary => Theme.of(this).colorScheme.primary;
  Color get wpMint =>
      isDark ? WpColors.darkElevated : WpColors.mint;
  Color get wpHighlight =>
      isDark ? WpColors.highlight : const Color(0xFF39C98B);
}
