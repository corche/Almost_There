import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const orange = Color(0xFFFF6900);
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final surface = Color(dark ? 0xFF0C0C09 : 0xFFF4F4F0);
    final card = Color(dark ? 0xFF1D1D16 : 0xFFFFFFFF);
    final secondary = Color(dark ? 0xFF2B2B22 : 0xFFE8E8E3);
    final text = Color(dark ? 0xFFFBFBF9 : 0xFF1D1D16);
    final muted = Color(dark ? 0xFFABAB9C : 0xFF5B5B4B);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: orange,
          brightness: brightness,
        ).copyWith(
          primary: orange,
          onPrimary: const Color(0xFF231006),
          surface: card,
          onSurface: text,
          onSurfaceVariant: muted,
          surfaceContainer: secondary,
          surfaceContainerHighest: secondary,
          outline: muted,
          outlineVariant: dark
              ? const Color(0xFF34342A)
              : const Color(0xFFE1E1D9),
          secondary: const Color(0xFF77805B),
        );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      fontFamily: 'Malgun Gothic',
    );
    return base.copyWith(
      textTheme: base.textTheme
          .apply(bodyColor: text, displayColor: text)
          .copyWith(
            headlineLarge: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              height: 1.35,
              letterSpacing: -1.4,
              color: text,
            ),
            headlineMedium: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.4,
              letterSpacing: -1,
              color: text,
            ),
            titleLarge: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: -.7,
              color: text,
            ),
            titleMedium: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: text,
            ),
            bodyMedium: TextStyle(fontSize: 14, height: 1.6, color: text),
            bodySmall: TextStyle(fontSize: 12, height: 1.5, color: muted),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 54),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          foregroundColor: text,
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: secondary,
        contentPadding: const EdgeInsets.all(17),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: orange, width: 1.5),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Colors.white : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? orange : secondary,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: orange.withValues(alpha: .12),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? orange : muted,
          ),
        ),
      ),
    );
  }
}
