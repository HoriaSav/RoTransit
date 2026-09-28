import 'package:flutter/material.dart';

import 'app_extra_colors.dart';

class AppTheme {
  static const _seed = Color(0xFF0D4FB3);
  static const _primary = Color(0xFF0A3E96);
  static const _darkPrimary = Color(0xFF6EA8FF);
  static const _darkOnPrimary = Color(0xFF0A1628);
  static const _darkPrimaryContainer = Color(0xFF2D4A73);
  static const _darkOnPrimaryContainer = Color(0xFFE8F0FF);
  static const _darkOnSurface = Color(0xFFE8EDF5);
  static const _darkOnSurfaceVariant = Color(0xFFB8C4D6);

  static ThemeData get lightTheme => _buildTheme(
        brightness: Brightness.light,
        extra: AppExtraColors.light,
      );

  static ThemeData get darkTheme => _buildTheme(
        brightness: Brightness.dark,
        extra: AppExtraColors.dark,
      );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required AppExtraColors extra,
  }) {
    final isLight = brightness == Brightness.light;
    final scheme = isLight
        ? ColorScheme.fromSeed(
            seedColor: _seed,
            brightness: Brightness.light,
            primary: _primary,
            surface: const Color(0xFFF7F8F4),
            surfaceContainerHighest: const Color(0xFFE8ECF2),
          )
        : ColorScheme.fromSeed(
            seedColor: _seed,
            brightness: Brightness.dark,
            primary: _darkPrimary,
            onPrimary: _darkOnPrimary,
            primaryContainer: _darkPrimaryContainer,
            onPrimaryContainer: _darkOnPrimaryContainer,
            onSurface: _darkOnSurface,
            onSurfaceVariant: _darkOnSurfaceVariant,
            outline: const Color(0xFF5A6B82),
            surface: const Color(0xFF121418),
            surfaceContainerHighest: const Color(0xFF344155),
          );

    final borderRadius = BorderRadius.circular(12);
    final fieldRadius = BorderRadius.circular(10);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: extra.tabBackground,
      extensions: [extra],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: isLight ? 0 : 1,
        shadowColor: scheme.shadow,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: isLight ? 0.7 : 0.5),
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        modalBackgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        dividerColor: scheme.outlineVariant,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.primaryContainer,
          disabledForegroundColor: scheme.onPrimaryContainer,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.onPrimary;
          }
          return scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return scheme.surfaceContainerHighest;
        }),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        enabledBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(
            color: isLight ? Colors.black : scheme.outline,
            width: isLight ? 1.6 : 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontSize: 52,
          height: 1,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
          color: scheme.primary,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.4,
          fontWeight: FontWeight.w500,
          color: scheme.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.45,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
        labelLarge: TextStyle(
          fontSize: 13,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.6,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
