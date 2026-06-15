import 'package:flutter/material.dart';

/// App-specific colors that are not covered by [ColorScheme] alone.
@immutable
class AppExtraColors extends ThemeExtension<AppExtraColors> {
  const AppExtraColors({
    required this.shellFrame,
    required this.shellHeader,
    required this.tabBackground,
    required this.searchFormCard,
    required this.searchFormShadow,
    required this.searchGradientTop,
    required this.searchGradientMid,
    required this.searchGradientBottom,
    required this.floatingNavBackground,
    required this.floatingNavIndicator,
    required this.recentTileBackground,
    required this.recentTileBorder,
    required this.swapButtonBackground,
    required this.durationBadgeBackground,
    required this.mapFabBackground,
    required this.walkExtraColor,
    required this.walkBestColor,
    required this.durationBestColor,
  });

  final Color shellFrame;
  final Color shellHeader;
  final Color tabBackground;
  final Color searchFormCard;
  final Color searchFormShadow;
  final Color searchGradientTop;
  final Color searchGradientMid;
  final Color searchGradientBottom;
  final Color floatingNavBackground;
  final Color floatingNavIndicator;
  final Color recentTileBackground;
  final Color recentTileBorder;
  final Color swapButtonBackground;
  final Color durationBadgeBackground;
  final Color mapFabBackground;
  final Color walkExtraColor;
  final Color walkBestColor;
  final Color durationBestColor;

  static const light = AppExtraColors(
    shellFrame: Color(0xFFF7F8F4),
    shellHeader: Color(0xFFFFFFFF),
    tabBackground: Color(0xFFF7F8F4),
    searchFormCard: Color(0xFFFFFFFF),
    searchFormShadow: Color(0x1A0A3E96),
    searchGradientTop: Color(0x4D000000),
    searchGradientMid: Color(0x29000000),
    searchGradientBottom: Color(0xE6F7F8F4),
    floatingNavBackground: Color(0xF5FFFFFF),
    floatingNavIndicator: Color(0xFFDCE8F8),
    recentTileBackground: Color(0xFFFFFFFF),
    recentTileBorder: Color(0xFFE2E8F0),
    swapButtonBackground: Color(0xFFFFFFFF),
    durationBadgeBackground: Color(0xFFEDF2F8),
    mapFabBackground: Color(0xFF0A3E96),
    walkExtraColor: Color(0xD98A6D55),
    walkBestColor: Color(0xD93E7A59),
    durationBestColor: Color(0xE03D7A52),
  );

  static const dark = AppExtraColors(
    shellFrame: Color(0xFF0E1116),
    shellHeader: Color(0xFF161B22),
    tabBackground: Color(0xFF0E1116),
    searchFormCard: Color(0xF01C2128),
    searchFormShadow: Color(0x66000000),
    searchGradientTop: Color(0x80000000),
    searchGradientMid: Color(0x52000000),
    searchGradientBottom: Color(0xE60E1116),
    floatingNavBackground: Color(0xF01C2128),
    floatingNavIndicator: Color(0xFF2D4A73),
    recentTileBackground: Color(0xFF1A2330),
    recentTileBorder: Color(0xFF3D4D63),
    swapButtonBackground: Color(0xFF2A3441),
    durationBadgeBackground: Color(0xFF344155),
    mapFabBackground: Color(0xFF2563EB),
    walkExtraColor: Color(0xFFD4A574),
    walkBestColor: Color(0xFF6EE7A0),
    durationBestColor: Color(0xFF7DD3A0),
  );

  @override
  AppExtraColors copyWith({
    Color? shellFrame,
    Color? shellHeader,
    Color? tabBackground,
    Color? searchFormCard,
    Color? searchFormShadow,
    Color? searchGradientTop,
    Color? searchGradientMid,
    Color? searchGradientBottom,
    Color? floatingNavBackground,
    Color? floatingNavIndicator,
    Color? recentTileBackground,
    Color? recentTileBorder,
    Color? swapButtonBackground,
    Color? durationBadgeBackground,
    Color? mapFabBackground,
    Color? walkExtraColor,
    Color? walkBestColor,
    Color? durationBestColor,
  }) {
    return AppExtraColors(
      shellFrame: shellFrame ?? this.shellFrame,
      shellHeader: shellHeader ?? this.shellHeader,
      tabBackground: tabBackground ?? this.tabBackground,
      searchFormCard: searchFormCard ?? this.searchFormCard,
      searchFormShadow: searchFormShadow ?? this.searchFormShadow,
      searchGradientTop: searchGradientTop ?? this.searchGradientTop,
      searchGradientMid: searchGradientMid ?? this.searchGradientMid,
      searchGradientBottom: searchGradientBottom ?? this.searchGradientBottom,
      floatingNavBackground:
          floatingNavBackground ?? this.floatingNavBackground,
      floatingNavIndicator: floatingNavIndicator ?? this.floatingNavIndicator,
      recentTileBackground: recentTileBackground ?? this.recentTileBackground,
      recentTileBorder: recentTileBorder ?? this.recentTileBorder,
      swapButtonBackground: swapButtonBackground ?? this.swapButtonBackground,
      durationBadgeBackground:
          durationBadgeBackground ?? this.durationBadgeBackground,
      mapFabBackground: mapFabBackground ?? this.mapFabBackground,
      walkExtraColor: walkExtraColor ?? this.walkExtraColor,
      walkBestColor: walkBestColor ?? this.walkBestColor,
      durationBestColor: durationBestColor ?? this.durationBestColor,
    );
  }

  @override
  AppExtraColors lerp(ThemeExtension<AppExtraColors>? other, double t) {
    if (other is! AppExtraColors) return this;
    return AppExtraColors(
      shellFrame: Color.lerp(shellFrame, other.shellFrame, t)!,
      shellHeader: Color.lerp(shellHeader, other.shellHeader, t)!,
      tabBackground: Color.lerp(tabBackground, other.tabBackground, t)!,
      searchFormCard: Color.lerp(searchFormCard, other.searchFormCard, t)!,
      searchFormShadow: Color.lerp(searchFormShadow, other.searchFormShadow, t)!,
      searchGradientTop:
          Color.lerp(searchGradientTop, other.searchGradientTop, t)!,
      searchGradientMid:
          Color.lerp(searchGradientMid, other.searchGradientMid, t)!,
      searchGradientBottom:
          Color.lerp(searchGradientBottom, other.searchGradientBottom, t)!,
      floatingNavBackground:
          Color.lerp(floatingNavBackground, other.floatingNavBackground, t)!,
      floatingNavIndicator:
          Color.lerp(floatingNavIndicator, other.floatingNavIndicator, t)!,
      recentTileBackground:
          Color.lerp(recentTileBackground, other.recentTileBackground, t)!,
      recentTileBorder: Color.lerp(recentTileBorder, other.recentTileBorder, t)!,
      swapButtonBackground:
          Color.lerp(swapButtonBackground, other.swapButtonBackground, t)!,
      durationBadgeBackground:
          Color.lerp(durationBadgeBackground, other.durationBadgeBackground, t)!,
      mapFabBackground: Color.lerp(mapFabBackground, other.mapFabBackground, t)!,
      walkExtraColor: Color.lerp(walkExtraColor, other.walkExtraColor, t)!,
      walkBestColor: Color.lerp(walkBestColor, other.walkBestColor, t)!,
      durationBestColor:
          Color.lerp(durationBestColor, other.durationBestColor, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppExtraColors get extraColors =>
      Theme.of(this).extension<AppExtraColors>() ?? AppExtraColors.light;
}
