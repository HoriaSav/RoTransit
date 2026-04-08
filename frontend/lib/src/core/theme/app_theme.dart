import 'package:flutter/material.dart';

class AppTheme {
  static const _seed = Color(0xFF0D4FB3);
  static const authPrimaryBlue = Color(0xFF0A4FB8);
  static const authDarkButton = Color(0xFF121418);
  static const authScreenBackground = Color(0xFFF7F8F4);
  static const authCardBackground = Color(0xFFFFFFFF);
  static const authMutedText = Color(0xFF6A6E79);
  static const authBodyText = Color(0xFF1A1E27);
  static const authLegalText = Color(0xFF273043);
  static const authTransportText = Color(0xFF8E939B);

  static const BorderRadius authCardRadius = BorderRadius.all(Radius.circular(36));
  static const BorderRadius authPillRadius = BorderRadius.all(Radius.circular(999));
  static const BorderRadius authLogoRadius = BorderRadius.all(Radius.circular(24));

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        scaffoldBackgroundColor: authScreenBackground,
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontSize: 52,
            height: 1,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: authPrimaryBlue,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: authBodyText,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            height: 1.4,
            fontWeight: FontWeight.w500,
            color: authBodyText,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w500,
            color: authMutedText,
          ),
          labelLarge: TextStyle(
            fontSize: 13,
            height: 1.2,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.6,
            color: authTransportText,
          ),
        ),
      );

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
      );
}
