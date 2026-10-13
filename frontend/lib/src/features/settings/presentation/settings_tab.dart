import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rotransit/l10n/app_localizations.dart';

import '../../../core/branding/operator_branding.dart';
import '../../../core/theme/accent_badge_style.dart';
import '../../../core/theme/app_extra_colors.dart';
import '../../../core/errors/app_user_message.dart';
import '../../../core/ui/user_feedback.dart';
import '../../../core/state/clock_provider.dart';
import '../../../core/state/locale_provider.dart';
import '../../../core/state/transport_settings_provider.dart';
import '../../../core/state/theme_mode_provider.dart';
import '../../routes/data/route_api_repository.dart';
import '../../routes/domain/route_models.dart';
import '../../shell/shell_layout.dart';
import '../../map/data/companion_catalog.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shell/state/navigation_provider.dart';

part 'settings_chrome.dart';

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key, this.showBackButton = false});

  /// When true (pushed Settings overlay), show a back control that closes Settings.
  final bool showBackButton;

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  String _version = '1.0';
  // Cached so rebuilds (locale, city) don't re-query the pack. The date is
  // set when the pack's timetables have already ended (app needs an update).
  late final Future<(String, DateTime?)> _dataAsOf = _loadDataAsOf();

  Future<(String, DateTime?)> _loadDataAsOf() async {
    final catalog = ref.read(companionCatalogProvider);
    try {
      final meta = await catalog.meta();
      final ended = await feedEndedOn(catalog, ref.read(clockProvider)());
      return (meta.dataAsOf, ended);
    } catch (e) {
      debugPrint('Settings: bundled pack meta failed: $e');
      return ('—', null);
    }
  }

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = info.version);
      }
    });
  }

  Future<void> _openExternal(Uri uri) async {
    final l10n = AppLocalizations.of(context);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened || !mounted) return;
    showUserMessage(
      context,
      AppUserMessage.custom(
        l10n.linkOpenFailed,
        severity: UserMessageSeverity.error,
      ),
    );
  }

  Future<void> _showFareCheatSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
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
                  l10n.faresSheetTitle,
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                Text(l10n.faresSheetBody),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () =>
                          _openExternal(Uri.parse('https://www.ratbv.ro/')),
                      child: const Text('ratbv.ro'),
                    ),
                    FilledButton.tonal(
                      onPressed: () =>
                          _openExternal(Uri.parse('https://24pay.ro/')),
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ColoredBox(
        color: context.extraColors.tabBackground,
        child: SafeArea(
          top: widget.showBackButton,
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              shellBottomContentPadding(context),
            ),
            children: [
              _SettingsPageHeader(
                title: l10n.settingsTitle,
                onBack: widget.showBackButton
                    ? () =>
                        ref.read(settingsOpenProvider.notifier).state = false
                    : null,
              ),
              const SizedBox(height: 18),
              // Timetables ship inside the app (no download): show the
              // bundled pack's data date.
              FutureBuilder<(String, DateTime?)>(
                future: _dataAsOf,
                builder: (context, snap) {
                  final (asOf, ended) = snap.data ?? ('…', null);
                  return _SettingsGroup(
                    children: [
                      _SettingsNavRow(
                        icon: Icons.calendar_month_outlined,
                        title: l10n.settingsDataAsOf,
                        subtitle: asOf,
                        onTap: null,
                      ),
                      const _SettingsDivider(),
                      if (ended != null) ...[
                        _SettingsNavRow(
                          icon: Icons.warning_amber_rounded,
                          title: l10n.stopBoardFeedEnded(
                            CompanionCatalog.isoDate(ended),
                          ),
                        ),
                        const _SettingsDivider(),
                      ],
                      _SettingsNavRow(
                        icon: Icons.payments_outlined,
                        title: l10n.settingsFaresTitle,
                        subtitle: l10n.settingsFaresSubtitle,
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
                  const _SettingsDivider(),
                  _SettingsToggleRow(
                    icon: Icons.dark_mode_outlined,
                    title: l10n.darkMode,
                    value: isDark,
                    onChanged: (value) =>
                        ref.read(themeModeProvider.notifier).setDarkMode(value),
                  ),
                  const _SettingsDivider(),
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
                onTap: available ? () => Navigator.of(context).pop(city) : null,
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
