import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_config.dart';
import '../../../core/network/connectivity_status.dart';
import '../../../core/time/week_anchor.dart';
import '../../saved/state/saved_providers.dart';
import 'offline_transit_cache_repository.dart';
import 'route_api_repository.dart';

const _previewPlaceholderCityId = '00000000-0000-0000-0000-000000000001';

/// Cloud pack fingerprint + whether the lightweight meta endpoint exists on this API.
class OfflinePackCloudState {
  const OfflinePackCloudState({
    this.packVersion,
    this.metaEndpointMissing = false,
  });

  final String? packVersion;
  final bool metaEndpointMissing;
}

/// Last cloud meta (or “endpoint missing”) for Settings / sync.
final offlinePackCloudStateProvider =
    StateProvider<OfflinePackCloudState>((ref) => const OfflinePackCloudState());

enum OfflinePackDownloadPhase { network, saving }

/// Network download progress for the offline pack (null when idle).
class OfflinePackDownloadProgress {
  const OfflinePackDownloadProgress({
    this.phase = OfflinePackDownloadPhase.network,
    this.fraction,
    this.etaSeconds,
    this.receivedBytes = 0,
    this.totalBytes,
    this.elapsedSeconds,
  });

  final OfflinePackDownloadPhase phase;

  /// 0.0–1.0 when Content-Length is known; null = indeterminate.
  final double? fraction;
  final int? etaSeconds;
  final int receivedBytes;
  final int? totalBytes;
  final int? elapsedSeconds;
}

final offlinePackDownloadProgressProvider =
    StateProvider<OfflinePackDownloadProgress?>((ref) => null);

/// True while a full-pack download is in progress for the current city.
final offlinePackSyncInFlightProvider = Provider<bool>((ref) {
  return ref.watch(offlinePackDownloadProgressProvider) != null;
});

/// True when [local] is installed and matches the server pack (or server meta is unavailable).
bool isOfflinePackUpToDate({
  required OfflineTransitMeta? local,
  required OfflinePackCloudState cloud,
}) {
  if (local == null) return false;
  if (cloud.metaEndpointMissing) return true;
  final cloudVersion = cloud.packVersion?.trim() ?? '';
  if (cloudVersion.isEmpty) return true;
  final localVersion = local.packVersion.trim();
  if (localVersion.isEmpty) return false;
  return cloudVersion == localVersion;
}

class _DownloadByteProgress {
  DateTime? _startedAt;

  OfflinePackDownloadProgress update(int received, int total) {
    _startedAt ??= DateTime.now();

    double? fraction;
    if (total > 0) {
      fraction = (received / total).clamp(0.0, 1.0);
    }

    int? etaSeconds;
    if (total > 0 && received > 0 && received < total && _startedAt != null) {
      final elapsedMs = DateTime.now().difference(_startedAt!).inMilliseconds;
      if (elapsedMs >= 800) {
        final rate = received / elapsedMs;
        if (rate > 0) {
          final remaining = total - received;
          if (remaining > 0) {
            etaSeconds =
                (remaining / rate / 1000).ceil().clamp(1, 99 * 60);
          }
        }
      }
    }

    final elapsed = DateTime.now().difference(_startedAt!).inSeconds;

    return OfflinePackDownloadProgress(
      fraction: fraction,
      etaSeconds: etaSeconds,
      receivedBytes: received,
      totalBytes: total > 0 ? total : null,
      elapsedSeconds: elapsed > 0 ? elapsed : null,
    );
  }
}

class OfflineTimetableDownloadException implements Exception {
  const OfflineTimetableDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Downloads (or re-downloads) the offline transit pack for [cityId] after user confirmation.
Future<void> downloadOfflineTransitPackManual(
  WidgetRef ref,
  String cityId,
) async {
  if (!ApiConfig.useBackend ||
      cityId.isEmpty ||
      cityId == _previewPlaceholderCityId) {
    return;
  }
  if (!await isDeviceOnline()) {
    throw const OfflineTimetableDownloadException('offline');
  }

  final progressNotifier =
      ref.read(offlinePackDownloadProgressProvider.notifier);
  final byteProgress = _DownloadByteProgress();
  progressNotifier.state = const OfflinePackDownloadProgress();
  try {
    final anchor = mondayOfWeekContaining(DateTime.now());
    await ref.read(routeApiRepositoryProvider).downloadOfflineTransitPack(
          cityId: cityId,
          anchorMonday: anchor,
          onProgress: (received, total) {
            progressNotifier.state = byteProgress.update(received, total);
          },
          onSavingStarted: () {
            final last = progressNotifier.state;
            progressNotifier.state = OfflinePackDownloadProgress(
              phase: OfflinePackDownloadPhase.saving,
              fraction: 1,
              receivedBytes: last?.receivedBytes ?? 0,
              totalBytes: last?.totalBytes,
            );
          },
        );
    ref.read(offlinePackRevisionProvider.notifier).state++;
    unawaited(refreshOfflinePackCloudVersion(ref, cityId));
    if (kDebugMode) {
      debugPrint('Offline pack: manual download applied for $cityId');
    }
  } finally {
    progressNotifier.state = null;
  }
}

/// Fetches meta only (updates [offlinePackCloudStateProvider]) for Settings display.
Future<void> refreshOfflinePackCloudVersion(WidgetRef ref, String cityId) async {
  if (!ApiConfig.useBackend ||
      cityId.isEmpty ||
      cityId == _previewPlaceholderCityId) {
    ref.read(offlinePackCloudStateProvider.notifier).state =
        const OfflinePackCloudState();
    return;
  }
  if (!await isDeviceOnline()) {
    return;
  }
  try {
    final meta = await ref.read(routeApiRepositoryProvider).fetchOfflinePackMeta(
          cityId: cityId,
          anchorMonday: mondayOfWeekContaining(DateTime.now()),
        );
    if (meta.endpointMissing) {
      ref.read(offlinePackCloudStateProvider.notifier).state =
          const OfflinePackCloudState(metaEndpointMissing: true);
      return;
    }
    final v = meta.packVersion.trim();
    ref.read(offlinePackCloudStateProvider.notifier).state = OfflinePackCloudState(
      packVersion: v.isEmpty ? null : v,
      metaEndpointMissing: false,
    );
  } catch (_) {
    // keep previous cloud state
  }
}
