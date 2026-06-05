/// Operator logos and city availability (frontend-only until multi-city launch).
library;

/// Stable Brasov city id from [db/postgres/init/001_init.sql].
const kBrasovCityId = '93715d42-5523-4195-8743-53b6819488c9';

/// Bucharest seed id — listed in API but not selectable yet.
const kBucharestCityId = 'a1b2c3d4-e5f6-4789-a012-3456789abcde';

const kRatbvLogoAsset = 'assets/operators/ratBv.png';

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
