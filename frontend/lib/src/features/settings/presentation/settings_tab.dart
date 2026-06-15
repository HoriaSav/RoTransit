import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rotransit_frontend/l10n/app_localizations.dart';

import '../../../core/branding/operator_branding.dart';
import '../../../core/format/byte_size_format.dart';
import '../../../core/config/api_config.dart';
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
import '../../shell/state/navigation_provider.dart';

const _placeholderCityId = '00000000-0000-0000-0000-000000000001';

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
          _localOfflineMeta = null;
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
    final l10n = AppLocalizations.of(context)!;
    if (!ApiConfig.useBackend) {
      showUserMessage(
        context,
        AppUserMessage.custom(l10n.offlinePackNotAvailablePreview),
      );
      return;
    }

    final cityId = ref.read(searchMapStateProvider).cityId;
    final cityName = ref.read(searchMapStateProvider).cityName.trim();
    if (cityId.isEmpty || cityId == _placeholderCityId) {
      showUserMessage(
        context,
        AppUserMessage.custom(
          l10n.offlinePackChooseCityFirst,
          severity: UserMessageSeverity.warning,
        ),
      );
      return;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final teEnabled = ref.watch(teTransportEnabledProvider);
    final locale = ref.watch(localeProvider);
    final cityState = ref.watch(searchMapStateProvider);
    final cityName =
        cityState.cityName.trim().isEmpty ? 'Brasov' : cityState.cityName;
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
                        : _offlineTimetablesSubtitle,
                    subtitleWidget: downloadProgress != null
                        ? _OfflineDownloadProgressSubtitle(
                            progress: downloadProgress,
                            statusText: _offlineDownloadStatusText(
                              l10n,
                              downloadProgress,
                            ),
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

class _SettingsPageHeader extends StatelessWidget {
  const _SettingsPageHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(
          Icons.settings_rounded,
          size: 22,
          color: scheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final extra = context.extraColors;
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;

    return Material(
      color: extra.recentTileBackground,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: extra.recentTileBorder),
          boxShadow: isDark
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x0A0A3E96),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 58,
      endIndent: 14,
      color: context.extraColors.recentTileBorder,
    );
  }
}

class _SettingsIconBadge extends StatelessWidget {
  const _SettingsIconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final badge = accentBadgeColors(context);

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: badge.background,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: 20,
        color: badge.foreground,
      ),
    );
  }
}

class _SettingsNavRow extends StatelessWidget {
  const _SettingsNavRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingsIconBadge(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? scheme.onSurface
                            : scheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                    if (subtitleWidget != null) ...[
                      const SizedBox(height: 6),
                      subtitleWidget!,
                    ] else if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: enabled
                        ? mutedChromeColor(context)
                        : scheme.onSurfaceVariant.withValues(alpha: 0.35),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsToggleRow extends StatelessWidget {
  const _SettingsToggleRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsIconBadge(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SettingsInfoRow extends StatelessWidget {
  const _SettingsInfoRow({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extra = context.extraColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          _SettingsIconBadge(icon: Icons.info_outline_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: extra.durationBadgeBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
