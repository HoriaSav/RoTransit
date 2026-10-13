import '../../../core/branding/operator_branding.dart';
import '../domain/route_models.dart';

const kBrasovCityItem = CityItem(
  id: kBrasovCityId,
  name: kBrasovCityName,
  country: 'Romania',
);

CityItem resolveCatalogCity(
  List<CityItem> cities, {
  String? preferredId,
  String? preferredName,
}) {
  CityItem? byId(String id) {
    for (final city in cities) {
      if (city.id == id &&
          isCityAvailable(cityId: city.id, cityName: city.name)) {
        return city;
      }
    }
    return null;
  }

  final wantedId = isUnresolvedCityId(preferredId)
      ? kBrasovCityId
      : preferredId!.trim();
  final byWanted = byId(wantedId);
  if (byWanted != null) return byWanted;

  final brasov = byId(kBrasovCityId);
  if (brasov != null) return brasov;

  final needle = preferredName?.trim().toLowerCase() ?? '';
  if (needle.isNotEmpty) {
    for (final city in cities) {
      if (city.name.trim().toLowerCase() == needle &&
          isCityAvailable(cityId: city.id, cityName: city.name)) {
        return city;
      }
    }
  }

  for (final city in cities) {
    if (isCityAvailable(cityId: city.id, cityName: city.name)) return city;
  }
  return kBrasovCityItem;
}
