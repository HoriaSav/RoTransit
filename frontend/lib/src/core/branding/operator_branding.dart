/// Operator logos and city availability (frontend-only until multi-city launch).
library;

import 'package:flutter/material.dart';

import '../theme/app_extra_colors.dart';

/// Stable Brasov city id from [db/postgres/init/001_init.sql].
const kBrasovCityId = '93715d42-5523-4195-8743-53b6819488c9';

/// Bucharest seed id — listed in API but not selectable yet.
const kBucharestCityId = 'a1b2c3d4-e5f6-4789-a012-3456789abcde';

const kRatbvLogoAsset = 'assets/operators/ratBv_noBg.png';

/// Full-color RATBV mark on white; reads better on dark app chrome than [kRatbvLogoAsset].
const kRatbvLogoOnLightAsset = 'assets/operators/ratBv.png';

bool isCityAvailable({required String cityId, required String cityName}) {
  if (cityId == kBucharestCityId) return false;
  if (cityName.trim().toLowerCase() == 'bucharest') return false;
  return true;
}

/// Bundled operator logo for [cityId] / [cityName], or null for generic fallback.
String? operatorLogoAssetForCity({required String cityId, String cityName = ''}) {
  final name = cityName.trim().toLowerCase();
  if (cityId == kBrasovCityId ||
      name == 'brasov' ||
      (cityId.isEmpty && name.isEmpty)) {
    return kRatbvLogoAsset;
  }
  return null;
}

/// Display asset tuned for headers (prefers the full-color mark when available).
String? operatorHeaderLogoAssetForCity({
  required String cityId,
  String cityName = '',
}) {
  final logo = operatorLogoAssetForCity(cityId: cityId, cityName: cityName);
  if (logo == kRatbvLogoAsset) {
    return kRatbvLogoOnLightAsset;
  }
  return logo;
}

/// Operator logo for tab headers: centered, crisp on dark backgrounds.
Widget operatorBrandMark({
  required BuildContext context,
  required String? logoAsset,
  double height = 34,
}) {
  final scheme = Theme.of(context).colorScheme;
  final extra = Theme.of(context).extension<AppExtraColors>() ?? AppExtraColors.light;
  final isDark = scheme.brightness == Brightness.dark;

  if (logoAsset == null) {
    return Icon(
      Icons.directions_bus_rounded,
      size: height + 2,
      color: scheme.primary,
    );
  }

  final image = Image.asset(
    logoAsset,
    height: height,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    errorBuilder: (_, __, ___) => Icon(
      Icons.directions_bus_rounded,
      size: height + 2,
      color: scheme.primary,
    ),
  );

  return DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: isDark ? Colors.transparent : extra.recentTileBorder,
      ),
      boxShadow: [
        BoxShadow(
          color: isDark ? const Color(0x33000000) : const Color(0x140A3E96),
          blurRadius: isDark ? 10 : 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: image,
    ),
  );
}
