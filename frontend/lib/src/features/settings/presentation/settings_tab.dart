import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rotransit_frontend/l10n/app_localizations.dart';

import '../../../core/branding/operator_branding.dart';
import '../../../core/format/byte_size_format.dart';
import '../../../core/config/api_config.dart';
import '../../../core/theme/app_extra_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../core/ui/app_snackbar.dart';
import '../../../core/state/locale_provider.dart';
import '../../../core/state/transport_settings_provider.dart';
import '../../../core/state/theme_mode_provider.dart';
import '../domain/timetable_download_source.dart';
import '../../routes/data/offline_transit_cache_repository.dart';
import '../../routes/data/offline_transit_sync.dart';
import '../../routes/data/route_api_repository.dart';
import '../../routes/domain/route_models.dart';
import '../../shell/shell_layout.dart';
import '../../shell/state/navigation_provider.dart';

const _placeholderCityId = '00000000-0000-0000-0000-000000000001';

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  bool _notifications = true;
  String _version = '1.0';
  String _offlineTimetablesSubtitle = '—';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = info.version);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshOfflineTimetablesSubtitle();
    });
  }

  Future<void> _refreshOfflineTimetablesSubtitle() async {
    final l10n = AppLocalizations.of(context)!;
    if (!ApiConfig.useBackend) {
      if (mounted) {
        setState(() {
          _offlineTimetablesSubtitle = l10n.offlinePackNotAvailablePreview;
        });
      }
      return;
    }
    final cityId = ref.read(searchMapStateProvider).cityId;
    if (cityId.isEmpty || cityId == _placeholderCityId) {
      if (mounted) {
        setState(() {
          _offlineTimetablesSubtitle = l10n.offlinePackChooseCityFirst;
        });
      }
      ref.read(offlinePackCloudStateProvider.notifier).state =
          const OfflinePackCloudState();
      return;
    }
    final meta = await ref
        .read(offlineTransitCacheRepositoryProvider)
        .getMetaForCity(cityId);
    if (!mounted) return;
    setState(() {
      if (meta == null) {
        _offlineTimetablesSubtitle = l10n.offlinePackNoneYet;
      } else {
        _offlineTimetablesSubtitle =
            l10n.offlineOnDevicePack(offlinePackLocalDisplayVersion(meta));
      }
    });
    unawaited(refreshOfflinePackCloudVersion(ref, cityId));
  }

  String _offlineDownloadStatusText(
    AppLocalizations l10n,
    OfflinePackDownloadProgress progress,
  ) {
    if (progress.phase == OfflinePackDownloadPhase.saving) {
      return l10n.offlineDownloadSaving;
    }

    final fraction = progress.fraction;
    if (fraction != null) {
      final percent = (fraction * 100).round().clamp(0, 100);
      var base = l10n.offlineDownloadProgressPercent(percent);
      final total = progress.totalBytes;
      if (total != null && total > 0) {
        base =
            '$base (${formatByteSize(progress.receivedBytes)} / ${formatByteSize(total)})';
      }
      final eta = progress.etaSeconds;
      if (eta == null) return base;
      final etaLabel = eta >= 60
          ? l10n.offlineDownloadEtaMinutes((eta / 60).ceil())
          : l10n.offlineDownloadEtaSeconds(eta);
      return '$base · $etaLabel';
    }

    if (progress.receivedBytes > 0) {
      final size = formatByteSize(progress.receivedBytes);
      final elapsed = progress.elapsedSeconds;
      if (elapsed != null) {
        return l10n.offlineDownloadReceivedWithElapsed(size, elapsed);
      }
      return l10n.offlineDownloadReceived(size);
    }

    return l10n.offlineUpdatingBackground;
  }

  String _sourceTitle(AppLocalizations l10n, TimetableDownloadSourceId id) {
    return switch (id) {
      TimetableDownloadSourceId.gtfsOfflinePack => l10n.timetableDownloadSourceBus,
    };
  }

  String _sourceStatusLine(
    AppLocalizations l10n, {
    required OfflineTransitMeta? localMeta,
    required OfflinePackCloudState cloudPack,
    required bool downloading,
  }) {
    if (downloading) {
      return l10n.offlineUpdatingBackground;
    }
    final localLine = localMeta == null
        ? l10n.offlinePackNoneYet
        : l10n.offlineOnDevicePack(offlinePackLocalDisplayVersion(localMeta));
    final cloudLine = cloudPack.metaEndpointMissing
        ? l10n.offlineMetaEndpointMissing
        : l10n.offlineServerMeta(cloudPack.packVersion ?? '…');
    return '$localLine\n$cloudLine';
  }

  Future<void> _pickTimetableDownload() async {
    final l10n = AppLocalizations.of(context)!;
    if (!ApiConfig.useBackend) {
      showAppSnackBar(
        context,
        SnackBar(content: Text(l10n.offlinePackNotAvailablePreview)),
      );
      return;
    }

    final cityId = ref.read(searchMapStateProvider).cityId;
    final cityName = ref.read(searchMapStateProvider).cityName.trim();
    if (cityId.isEmpty || cityId == _placeholderCityId) {
      showAppSnackBar(
        context,
        SnackBar(content: Text(l10n.offlinePackChooseCityFirst)),
      );
      return;
    }

    unawaited(refreshOfflinePackCloudVersion(ref, cityId));

    final TimetableDownloadSourceId? picked;
    if (kTimetableDownloadSources.length == 1) {
      picked = kTimetableDownloadSources.first.id;
    } else {
      final localMeta = await ref
          .read(offlineTransitCacheRepositoryProvider)
          .getMetaForCity(cityId);
      if (!mounted) return;

      final cloudPack = ref.read(offlinePackCloudStateProvider);
      final downloading = ref.read(offlinePackSyncInFlightProvider);
      final scheme = Theme.of(context).colorScheme;

      picked = await showModalBottomSheet<TimetableDownloadSourceId>(
        context: context,
        useRootNavigator: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: kTimetableDownloadSources.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final source = kTimetableDownloadSources[index];
              return ListTile(
                leading: const Icon(Icons.directions_bus_outlined),
                title: Text(_sourceTitle(l10n, source.id)),
                subtitle: Text(
                  _sourceStatusLine(
                    l10n,
                    localMeta: localMeta,
                    cloudPack: cloudPack,
                    downloading: downloading,
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pop(source.id),
              );
            },
          ),
        ),
      );
    }
    if (picked == null || !mounted) return;

    final displayCityName =
        cityName.isEmpty ? l10n.city : cityName;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(l10n.timetableDownloadConfirmTitle),
        content: Text(l10n.timetableDownloadConfirmMessage(displayCityName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.timetableDownloadAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await downloadOfflineTransitPackManual(ref, cityId);
      if (!mounted) return;
      await _refreshOfflineTimetablesSubtitle();
      if (!mounted) return;
      showAppSnackBar(
        context,
        SnackBar(content: Text(l10n.timetableDownloadSuccess(displayCityName))),
      );
    } on OfflineTimetableDownloadException catch (e) {
      if (!mounted) return;
      final message = e.message == 'offline'
          ? l10n.timetableDownloadOffline
          : l10n.timetableDownloadFailed;
      showAppSnackBar(
        context,
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        SnackBar(
          content: Text(userFacingMessageForDioFailure(e)),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final teEnabled = ref.watch(teTransportEnabledProvider);
    final locale = ref.watch(localeProvider);
    final cityState = ref.watch(searchMapStateProvider);
    final cityName =
        cityState.cityName.trim().isEmpty ? 'Brasov' : cityState.cityName;
    final cityLogo = operatorLogoAssetForCity(
      cityId: cityState.cityId,
      cityName: cityState.cityName,
    );
    final offlinePackSyncing = ref.watch(offlinePackSyncInFlightProvider);
    final downloadProgress = ref.watch(offlinePackDownloadProgressProvider);

    ref.listen(searchMapStateProvider, (prev, next) {
      if (prev?.cityId != next.cityId) {
        _refreshOfflineTimetablesSubtitle();
      }
    });
    ref.listen(offlinePackDownloadProgressProvider, (prev, next) {
      if (prev != null && next == null) {
        _refreshOfflineTimetablesSubtitle();
      }
    });
    final extra = context.extraColors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ColoredBox(
        color: extra.tabBackground,
        child: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              shellBottomContentPadding(context),
            ),
            children: [
              Text(
                l10n.settingsTitle,
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: cityLogo != null
                          ? Image.asset(
                              cityLogo,
                              width: 40,
                              height: 40,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.location_city_rounded,
                              ),
                            )
                          : const Icon(Icons.location_city_rounded),
                      title: Text(l10n.city),
                      subtitle: Text(cityName),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pickCity,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.cloud_download_outlined),
                      title: Text(l10n.offlineTimetables),
                      subtitle: downloadProgress != null
                          ? _OfflineDownloadProgressSubtitle(
                              progress: downloadProgress,
                              statusText: _offlineDownloadStatusText(
                                l10n,
                                downloadProgress,
                              ),
                            )
                          : Text(_offlineTimetablesSubtitle),
                      isThreeLine: downloadProgress != null,
                      trailing: offlinePackSyncing
                          ? null
                          : const Icon(Icons.chevron_right),
                      onTap: offlinePackSyncing ? null : _pickTimetableDownload,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.language_rounded),
                      title: Text(l10n.language),
                      subtitle: Text(
                        languageLabelForCode(l10n, locale.languageCode),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _pickLanguage(l10n),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: _notifications,
                      title: Text(l10n.notifications),
                      onChanged: (value) =>
                          setState(() => _notifications = value),
                    ),
                    SwitchListTile(
                      value: isDark,
                      title: Text(l10n.darkMode),
                      onChanged: (value) =>
                          ref.read(themeModeProvider.notifier).setDarkMode(value),
                    ),
                    SwitchListTile(
                      value: teEnabled,
                      title: Text(l10n.teTransport),
                      onChanged: (value) => ref
                          .read(teTransportEnabledProvider.notifier)
                          .setEnabled(value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: Text(l10n.version),
                      trailing: Text(_version),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: Text(l10n.privacyPolicy),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: Text(l10n.termsOfUse),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: Text(l10n.help),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: Text(l10n.contactUs),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickLanguage(AppLocalizations l10n) async {
    final scheme = Theme.of(context).colorScheme;
    final current = ref.read(localeProvider).languageCode;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: supportedAppLanguageCodes.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final code = supportedAppLanguageCodes[index];
            final isSelected = code == current;
            return ListTile(
              title: Text(languageLabelForCode(l10n, code)),
              trailing: isSelected
                  ? Icon(Icons.check_circle, color: scheme.primary)
                  : null,
              onTap: () => Navigator.of(context).pop(code),
            );
          },
        ),
      ),
    );
    if (picked == null || picked == current) return;
    await ref.read(localeProvider.notifier).setLanguageCode(picked);
  }

  Future<void> _pickCity() async {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    try {
      final cities = await ref.read(routeApiRepositoryProvider).getCities();
      if (!mounted || cities.isEmpty) return;
      final selectedId = ref.read(searchMapStateProvider).cityId;
      final picked = await showModalBottomSheet<CityItem>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView.separated(
            itemCount: cities.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final city = cities[index];
              final isSelected = city.id == selectedId;
              final available = isCityAvailable(
                cityId: city.id,
                cityName: city.name,
              );
              final logo = operatorLogoAssetForCity(
                cityId: city.id,
                cityName: city.name,
              );
              return ListTile(
                enabled: available,
                leading: logo != null
                    ? Opacity(
                        opacity: available ? 1 : 0.45,
                        child: Image.asset(
                          logo,
                          width: 40,
                          height: 40,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.location_city_rounded,
                            color: scheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    : Icon(
                        Icons.location_city_rounded,
                        color: available
                            ? null
                            : scheme.onSurface.withValues(alpha: 0.38),
                      ),
                title: Text(
                  city.name,
                  style: available
                      ? null
                      : TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.38),
                        ),
                ),
                subtitle: city.country.isEmpty
                    ? null
                    : Text(l10n.countryLabel(city.country)),
                trailing: !available
                    ? Chip(
                        label: Text(
                          l10n.cityUnavailable,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      )
                    : (isSelected
                        ? Icon(Icons.check_circle, color: scheme.primary)
                        : null),
                onTap: available
                    ? () => Navigator.of(context).pop(city)
                    : null,
              );
            },
          ),
        ),
      );
      if (picked == null) return;
      if (!isCityAvailable(cityId: picked.id, cityName: picked.name)) return;
      ref.read(searchMapStateProvider.notifier).setCityContext(
            cityId: picked.id,
            cityName: picked.name,
          );
      if (!mounted) return;
      await _refreshOfflineTimetablesSubtitle();
      if (!mounted) return;
      showAppSnackBar(
        context,
        SnackBar(content: Text(l10n.cityChangedTo(picked.name))),
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        SnackBar(
          content: Text(userFacingMessageForDioFailure(e)),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }
}

class _OfflineDownloadProgressSubtitle extends StatelessWidget {
  const _OfflineDownloadProgressSubtitle({
    required this.progress,
    required this.statusText,
  });

  final OfflinePackDownloadProgress progress;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          statusText,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            minHeight: 5,
            value: progress.fraction,
          ),
        ),
      ],
    );
  }
}
