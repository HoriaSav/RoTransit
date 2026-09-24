import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rotransit/l10n/app_localizations.dart';

import '../../../core/branding/operator_branding.dart';
import '../../../core/format/byte_size_format.dart';
import '../../../core/theme/accent_badge_style.dart';
import '../../../core/theme/app_extra_colors.dart';
import '../../../core/errors/app_user_message.dart';
import '../../../core/ui/user_feedback.dart';
import '../../../core/state/locale_provider.dart';
import '../../../core/state/transport_settings_provider.dart';
import '../../../core/state/theme_mode_provider.dart';
import '../domain/timetable_download_source.dart';
import '../../routes/data/offline_transit_cache_repository.dart';
import '../../routes/data/offline_transit_sync.dart';
import '../../routes/data/route_api_repository.dart';
import '../../routes/domain/route_models.dart';
import '../../shell/shell_layout.dart';
import '../../map/data/companion_catalog.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shell/state/navigation_provider.dart';

part 'settings_chrome.dart';

String _friendlyOfflinePackSubtitle(
  BuildContext context,
  AppLocalizations l10n,
  OfflineTransitMeta meta,
) {
  final downloaded = DateTime.tryParse(meta.downloadedAtIso);
  final locale = Localizations.localeOf(context).toString();
  final dateLabel = downloaded != null
      ? DateFormat.yMMMd(locale).format(downloaded)
      : null;
  final week = meta.anchorMondayIso.trim();
  if (dateLabel != null && week.isNotEmpty) {
    return l10n.offlinePackDownloadedWithWeek(dateLabel, week);
  }
  if (dateLabel != null) return l10n.offlinePackDownloaded(dateLabel);
  return l10n.offlinePackAvailableOnDevice;
}

String _offlineTimetablesRowSubtitle(AppLocalizations l10n, String status) {
  return '$status\n${l10n.offlinePackWhatItCovers}';
}

String _truncatePackId(String value, {int max = 10}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '…';
  if (trimmed.length <= max) return trimmed;
  return '${trimmed.substring(0, max)}…';
}

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  String _version = '1.0';
  String _offlineTimetablesSubtitle = '—';
  OfflineTransitMeta? _localOfflineMeta;

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
    final l10n = AppLocalizations.of(context);
    final cityId = resolvedCityId(ref.read(searchMapStateProvider).cityId);
    if (isUnresolvedCityId(ref.read(searchMapStateProvider).cityId)) {
      final name = ref.read(searchMapStateProvider).cityName.trim();
      ref.read(searchMapStateProvider.notifier).setCityContext(
            cityId: cityId,
            cityName: name.isEmpty ? kBrasovCityName : name,
          );
    }
    final meta = await ref
        .read(offlineTransitCacheRepositoryProvider)
        .getMetaForCity(cityId);
    if (!mounted) return;
    setState(() {
      _localOfflineMeta = meta;
      _offlineTimetablesSubtitle = meta == null
          ? l10n.offlinePackNoneYet
          : _friendlyOfflinePackSubtitle(context, l10n, meta);
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
        : _friendlyOfflinePackSubtitle(context, l10n, localMeta);
    final cloudLine = cloudPack.metaEndpointMissing
        ? l10n.offlineMetaEndpointMissing
        : l10n.offlineServerMeta(
            _truncatePackId(cloudPack.packVersion ?? '…'),
          );
    return '$localLine\n$cloudLine';
  }

  Future<void> _pickTimetableDownload() async {
    final l10n = AppLocalizations.of(context);

    var cityId = ref.read(searchMapStateProvider).cityId;
    var cityName = ref.read(searchMapStateProvider).cityName.trim();
    if (isUnresolvedCityId(cityId)) {
      cityId = kBrasovCityId;
      cityName = cityName.isEmpty ? kBrasovCityName : cityName;
      ref.read(searchMapStateProvider.notifier).setCityContext(
            cityId: cityId,
            cityName: cityName,
          );
    }

    unawaited(refreshOfflinePackCloudVersion(ref, cityId));

    final localMeta = await ref
        .read(offlineTransitCacheRepositoryProvider)
        .getMetaForCity(cityId);
    if (!mounted) return;
    final cloudPack = ref.read(offlinePackCloudStateProvider);
    if (isOfflinePackUpToDate(local: localMeta, cloud: cloudPack)) {
      showUserMessage(
        context,
        AppUserMessage.custom(
          l10n.timetableDownloadAlreadyUpToDate,
          severity: UserMessageSeverity.info,
        ),
      );
      return;
    }

    final TimetableDownloadSourceId? picked;
    if (kTimetableDownloadSources.length == 1) {
      picked = kTimetableDownloadSources.first.id;
    } else {
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
      showUserMessage(
        context,
        AppUserMessage.custom(
          l10n.timetableDownloadSuccess(displayCityName),
          severity: UserMessageSeverity.success,
        ),
      );
    } on OfflineTimetableDownloadException catch (e) {
      if (!mounted) return;
      final message = e.message == 'offline'
          ? l10n.timetableDownloadOffline
          : l10n.timetableDownloadFailed;
      showUserMessage(
        context,
        AppUserMessage.custom(message, severity: UserMessageSeverity.error),
      );
    } catch (e) {
      if (!mounted) return;
      showUserError(context, e);
    }
  }


  Future<void> _showFareCheatSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RATBV fares (static guide)',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Urban (inside Brașov): about 5 RON per ride on the standard '
                  'ticket (confirm on ratbv.ro — prices change).\n\n'
                  'Metropolitan / zone tickets: higher fares for trips into nearby '
                  'communes (roughly 7–12 RON depending on zone in the GTFS fare table).\n\n'
                  'Buy tickets: 24pay app, RATBV ticket machines/kiosks, and other '
                  'channels listed on the operator site. This app does not sell tickets.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () {
                        launchUrl(
                          Uri.parse('https://www.ratbv.ro/'),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      child: const Text('ratbv.ro'),
                    ),
                    FilledButton.tonal(
                      onPressed: () {
                        launchUrl(
                          Uri.parse('https://24pay.ro/'),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      child: const Text('24pay'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final teEnabled = ref.watch(teTransportEnabledProvider);
    final locale = ref.watch(localeProvider);
    final cityState = ref.watch(searchMapStateProvider);
    final cityName = cityState.cityName.trim().isEmpty
        ? kBrasovCityName
        : cityState.cityName;
    final offlinePackSyncing = ref.watch(offlinePackSyncInFlightProvider);
    final downloadProgress = ref.watch(offlinePackDownloadProgressProvider);
    final cloudPack = ref.watch(offlinePackCloudStateProvider);
    final offlinePackUpToDate = isOfflinePackUpToDate(
      local: _localOfflineMeta,
      cloud: cloudPack,
    );
    final canPickTimetableDownload =
        !offlinePackSyncing && !offlinePackUpToDate;

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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ColoredBox(
        color: context.extraColors.tabBackground,
        child: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              shellBottomContentPadding(context),
            ),
            children: [
              _SettingsPageHeader(title: l10n.settingsTitle),
              const SizedBox(height: 18),
              FutureBuilder(
                future: CompanionCatalog.instance.meta(),
                builder: (context, snap) {
                  final meta = snap.data;
                  final asOf = meta?.dataAsOf ?? '—';
                  return _SettingsGroup(
                    children: [
                      _SettingsNavRow(
                        icon: Icons.calendar_month_outlined,
                        title: 'Brașov data as of',
                        subtitle: asOf,
                        onTap: null,
                      ),
                      _SettingsDivider(),
                      _SettingsNavRow(
                        icon: Icons.payments_outlined,
                        title: 'Fares & tickets (cheat sheet)',
                        subtitle: 'Urban vs metropolitan · where to buy',
                        onTap: () => _showFareCheatSheet(context),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              _SettingsGroup(
                children: [
                  _SettingsNavRow(
                    icon: Icons.location_city_rounded,
                    title: l10n.city,
                    subtitle: cityName,
                    onTap: _pickCity,
                  ),
                  _SettingsDivider(),
                  _SettingsNavRow(
                    icon: Icons.cloud_download_outlined,
                    title: l10n.offlineTimetables,
                    subtitle: downloadProgress != null
                        ? null
                        : _offlineTimetablesRowSubtitle(
                            l10n,
                            _offlineTimetablesSubtitle,
                          ),
                    subtitleWidget: downloadProgress != null
                        ? _OfflineDownloadProgressSubtitle(
                            progress: downloadProgress,
                            statusText: _offlineDownloadStatusText(
                              l10n,
                              downloadProgress,
                            ),
                            coverageHint: l10n.offlinePackWhatItCovers,
                          )
                        : null,
                    trailing: offlinePackSyncing
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary,
                            ),
                          )
                        : offlinePackUpToDate
                            ? Icon(
                                Icons.check_circle_rounded,
                                size: 22,
                                color: scheme.primary,
                              )
                            : null,
                    onTap: canPickTimetableDownload
                        ? _pickTimetableDownload
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SettingsGroup(
                children: [
                  _SettingsNavRow(
                    icon: Icons.language_rounded,
                    title: l10n.language,
                    subtitle: languageDisplayLabel(l10n, locale.languageCode),
                    onTap: () => _pickLanguage(l10n),
                  ),
                  _SettingsDivider(),
                  _SettingsToggleRow(
                    icon: Icons.dark_mode_outlined,
                    title: l10n.darkMode,
                    value: isDark,
                    onChanged: (value) =>
                        ref.read(themeModeProvider.notifier).setDarkMode(value),
                  ),
                  _SettingsDivider(),
                  _SettingsToggleRow(
                    icon: Icons.train_outlined,
                    title: l10n.teTransport,
                    subtitle: l10n.teTransportSubtitle,
                    value: teEnabled,
                    onChanged: (value) => ref
                        .read(teTransportEnabledProvider.notifier)
                        .setEnabled(value),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SettingsGroup(
                children: [
                  _SettingsInfoRow(
                    title: l10n.version,
                    value: _version,
                  ),
                ],
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
              leading: Text(
                languageFlagEmojiForCode(code),
                style: const TextStyle(fontSize: 24, height: 1.1),
              ),
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
    final l10n = AppLocalizations.of(context);
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
      showUserMessage(
        context,
        AppUserMessage.custom(
          l10n.cityChangedTo(picked.name),
          severity: UserMessageSeverity.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showUserError(context, e);
    }
  }
}

