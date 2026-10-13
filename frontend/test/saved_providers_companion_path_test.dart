import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/core/branding/operator_branding.dart';
import 'package:rotransit/src/features/saved/state/saved_providers.dart';
import 'package:rotransit/src/features/shell/state/navigation_provider.dart';

/// Verifies Timetable providers do not mutate searchMapState during build
/// (Riverpod forbids that; it was leaving boards empty/error forever).
void main() {
  test('empty cityId stays empty while watching pack provider start '
      '(resolve must not setCityContext during build)', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(searchMapStateProvider).cityId, isEmpty);

    // Kick the provider. Even if companion DB fails in test env, the critical
    // invariant is that city context was NOT mutated mid-build.
    final sub = container.listen(cityOfflinePackInstalledProvider, (_, __) {});
    addTearDown(sub.close);

    // Allow microtasks from the FutureProvider to run.
    await pumpEventQueue(times: 20);

    expect(
      container.read(searchMapStateProvider).cityId,
      isEmpty,
      reason: '_resolveCityId must be pure during FutureProvider build',
    );
  });

  test('known Brasov cityId is not rewritten during provider watch', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(searchMapStateProvider.notifier).setCityContext(
          cityId: kBrasovCityId,
          cityName: kBrasovCityName,
        );

    final sub = container.listen(cityOfflinePackInstalledProvider, (_, __) {});
    addTearDown(sub.close);
    await pumpEventQueue(times: 20);

    expect(container.read(searchMapStateProvider).cityId, kBrasovCityId);
    expect(container.read(searchMapStateProvider).cityName, kBrasovCityName);
  });
}
