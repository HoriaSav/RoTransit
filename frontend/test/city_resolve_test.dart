import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/core/branding/operator_branding.dart';
import 'package:rotransit/src/features/routes/data/city_catalog.dart';
import 'package:rotransit/src/features/routes/domain/route_models.dart';

void main() {
  test('legacy preview UUID is treated as unresolved', () {
    expect(isUnresolvedCityId(''), isTrue);
    expect(isUnresolvedCityId(kLegacyPlaceholderCityId), isTrue);
    expect(isUnresolvedCityId(kBrasovCityId), isFalse);
    expect(resolvedCityId(kLegacyPlaceholderCityId), kBrasovCityId);
    expect(resolvedCityId(null), kBrasovCityId);
  });

  test('catalog resolution prefers Brasov over other cities and placeholders', () {
    const other = CityItem(
      id: 'other-city',
      name: 'Cluj-Napoca',
      country: 'Romania',
    );
    const brasov = kBrasovCityItem;
    final resolved = resolveCatalogCity(
      [other, brasov],
      preferredId: kLegacyPlaceholderCityId,
    );
    expect(isCityAvailable(cityId: other.id, cityName: other.name), isFalse);
    expect(isCityAvailable(cityId: kBrasovCityId, cityName: kBrasovCityName), isTrue);
    expect(resolved.id, kBrasovCityId);
    expect(resolveCatalogCity(const []).id, kBrasovCityId);
  });
}
