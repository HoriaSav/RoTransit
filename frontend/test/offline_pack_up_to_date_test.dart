import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit_frontend/src/features/routes/data/offline_transit_cache_repository.dart';
import 'package:rotransit_frontend/src/features/routes/data/offline_transit_sync.dart';

void main() {
  const local = OfflineTransitMeta(
    cityId: 'c1',
    anchorMondayIso: '2026-04-20',
    downloadedAtIso: '2026-04-20T12:00:00Z',
    packVersion: 'sha256:abc',
    schemaVersion: 1,
  );

  test('isOfflinePackUpToDate is false when local pack is missing', () {
    expect(
      isOfflinePackUpToDate(
        local: null,
        cloud: const OfflinePackCloudState(packVersion: 'sha256:abc'),
      ),
      isFalse,
    );
  });

  test('isOfflinePackUpToDate is true when versions match', () {
    expect(
      isOfflinePackUpToDate(
        local: local,
        cloud: const OfflinePackCloudState(packVersion: 'sha256:abc'),
      ),
      isTrue,
    );
  });

  test('isOfflinePackUpToDate is false when server version differs', () {
    expect(
      isOfflinePackUpToDate(
        local: local,
        cloud: const OfflinePackCloudState(packVersion: 'sha256:def'),
      ),
      isFalse,
    );
  });

  test('isOfflinePackUpToDate treats missing server meta as up to date', () {
    expect(
      isOfflinePackUpToDate(
        local: local,
        cloud: const OfflinePackCloudState(metaEndpointMissing: true),
      ),
      isTrue,
    );
  });

  test('isOfflinePackUpToDate allows refresh for legacy local packs', () {
    const legacyLocal = OfflineTransitMeta(
      cityId: 'c1',
      anchorMondayIso: '2026-04-20',
      downloadedAtIso: '2026-04-20T12:00:00Z',
      packVersion: '',
      schemaVersion: 1,
    );
    expect(
      isOfflinePackUpToDate(
        local: legacyLocal,
        cloud: const OfflinePackCloudState(packVersion: 'sha256:abc'),
      ),
      isFalse,
    );
  });
}
