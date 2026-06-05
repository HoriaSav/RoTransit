import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit_frontend/src/features/routes/data/stop_suggestion_dedupe.dart';
import 'package:rotransit_frontend/src/features/routes/domain/route_models.dart';

void main() {
  test('dedupes accent and non-accent stop names when nearby', () {
    final items = <StopSearchItem>[
      const StopSearchItem(
        stopId: '1',
        name: 'Făget',
        lat: 45.0,
        lon: 25.0,
      ),
      const StopSearchItem(
        stopId: '2',
        name: 'Faget',
        lat: 45.0002,
        lon: 25.0002,
      ),
      const StopSearchItem(
        stopId: '3',
        name: 'Onix',
        lat: 45.01,
        lon: 25.01,
      ),
    ];

    final deduped = dedupeStopSearchItems(items, 10);

    expect(deduped.length, 2);
    expect(deduped.first.name, 'Făget');
    expect(deduped.any((s) => s.name == 'Onix'), isTrue);
  });
}
