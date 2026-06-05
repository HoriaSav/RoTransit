import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit_frontend/src/features/routes/data/offline_transit_cache_repository.dart';

void main() {
  test('offlinePackLocalDisplayVersion uses packVersion when set', () {
    const meta = OfflineTransitMeta(
      cityId: 'c1',
      anchorMondayIso: '2026-04-20',
      downloadedAtIso: '2026-04-20T12:00:00Z',
      packVersion: 'sha256:abc',
      schemaVersion: 1,
    );
    expect(offlinePackLocalDisplayVersion(meta), 'sha256:abc');
  });

  test('offlinePackLocalDisplayVersion synthesizes fingerprint when packVersion empty',
      () {
    const meta = OfflineTransitMeta(
      cityId: 'c1',
      anchorMondayIso: '2026-04-20',
      downloadedAtIso: '2026-04-20T12:00:00Z',
      packVersion: '',
      schemaVersion: 1,
    );
    final label = offlinePackLocalDisplayVersion(meta);
    expect(
      label,
      matches(RegExp(r'^local#[0-9a-f]{8} · week 2026-04-20$')),
    );
  });
}
