import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotransit/l10n/app_localizations.dart';

import '../../../core/branding/operator_branding.dart';
import '../../../core/state/transport_settings_provider.dart';
import '../../../core/theme/accent_badge_style.dart';
import '../../../core/theme/app_extra_colors.dart';
import '../../routes/domain/route_models.dart';
import '../../shell/shell_layout.dart';
import '../../shell/state/navigation_provider.dart';
import '../../shell/state/bus_line_open_provider.dart';
import '../state/saved_providers.dart';

part 'bus_stops.dart';
part 'bus_timetable.dart';

const _kBusTabHeaderHeight = 76.0;

class BusTab extends ConsumerStatefulWidget {
  const BusTab({super.key});

  @override
  ConsumerState<BusTab> createState() => _BusTabState();
}

class _BusTabState extends ConsumerState<BusTab> {
  @override
  Widget build(BuildContext context) {
    ref.listen<OpenBusLineRequest?>(pendingOpenBusLineProvider, (prev, next) {
      if (next == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final req = ref.read(pendingOpenBusLineProvider);
        if (req == null) return;
        ref.read(pendingOpenBusLineProvider.notifier).state = null;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _BusStopsScreen(
              routeId: req.line.routeId,
              shortName: req.line.shortName,
              longName: req.line.longName,
            ),
          ),
        );
      });
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ColoredBox(
        color: context.extraColors.tabBackground,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _BusTabOperatorHeader(),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: shellBottomContentPadding(context),
                ),
                child: const _BusLinesView(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusTabOperatorHeader extends ConsumerWidget {
  const _BusTabOperatorHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extra = context.extraColors;
    final cityState = ref.watch(searchMapStateProvider);
    final operatorLogo = operatorHeaderLogoAssetForCity(
      cityId: cityState.cityId,
      cityName: cityState.cityName,
    );

    return SafeArea(
      bottom: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: extra.shellHeader,
          border: Border(
            bottom: BorderSide(color: extra.recentTileBorder, width: 1),
          ),
        ),
        child: SizedBox(
          height: _kBusTabHeaderHeight,
          width: double.infinity,
          child: Center(
            child: operatorBrandMark(
              context: context,
              logoAsset: operatorLogo,
              height: 32,
            ),
          ),
        ),
      ),
    );
  }
}

class _BusLinesView extends ConsumerStatefulWidget {
  const _BusLinesView();

  @override
  ConsumerState<_BusLinesView> createState() => _BusLinesViewState();
}

class _BusLinesViewState extends ConsumerState<_BusLinesView> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isTeLine(BusLine line) {
    final short = line.shortName.trim().toUpperCase();
    final routeId = line.routeId.trim().toUpperCase();
    return short.startsWith('TE') || routeId.startsWith('TE');
  }

  int? _routeNumberOf(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  int? _busNumber(BusLine line) {
    final fromShort = _routeNumberOf(line.shortName);
    if (fromShort != null) return fromShort;
    return _routeNumberOf(line.routeId);
  }

  List<BusLine> _sortedByNumber(List<BusLine> lines) {
    final copy = [...lines];
    copy.sort((a, b) {
      final aNum = _busNumber(a);
      final bNum = _busNumber(b);
      if (aNum != null && bNum != null) return aNum.compareTo(bNum);
      if (aNum != null) return -1;
      if (bNum != null) return 1;
      return a.shortName.compareTo(b.shortName);
    });
    return copy;
  }

  List<BusLine> _filterUrban(List<BusLine> lines) => lines.where((line) {
        if (_isTeLine(line)) return false;
        final n = _busNumber(line);
        return n != null && n >= 1 && n <= 99;
      }).toList();

  List<BusLine> _filterRural(List<BusLine> lines) => lines.where((line) {
        if (_isTeLine(line)) return false;
        final n = _busNumber(line);
        return n != null && n >= 100;
      }).toList();

  List<BusLine> _filterTe(List<BusLine> lines) =>
      lines.where(_isTeLine).toList();

  List<BusLine> _applySearch(List<BusLine> lines) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return lines;
    return lines.where((line) {
      final short = line.shortName.toLowerCase();
      final long = line.longName.toLowerCase();
      final id = line.routeId.toLowerCase();
      return short.contains(q) || long.contains(q) || id.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final teEnabled = ref.watch(teTransportEnabledProvider);
    final packInstalled = ref.watch(cityOfflinePackInstalledProvider);
    final buses = ref.watch(busesProvider);
    final scheme = Theme.of(context).colorScheme;

    return packInstalled.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      // Pack open/meta failure — surface clearly (not a silent empty list).
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '${l10n.busCouldNotLoadLines}\n$err',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (installed) {
        if (!installed) {
          return _TimetablesNotDownloadedBody(
            title: l10n.busTabTimetablesNotDownloadedTitle,
            body: l10n.busTabTimetablesNotDownloadedBody,
            actionLabel: l10n.busTabOpenSettings,
            onOpenSettings: () {
              ref.read(settingsOpenProvider.notifier).state = true;
            },
          );
        }
        return buses.when(
          data: (items) {
            if (items.isEmpty) {
              return Center(child: Text(l10n.busNoLinesFound));
            }
            final filtered = _applySearch(items);
            final urban = _sortedByNumber(_filterUrban(filtered));
            final rural = _sortedByNumber(_filterRural(filtered));
            final te = _sortedByNumber(_filterTe(filtered));
            final tabs = <Tab>[
              Tab(text: l10n.busTabUrban),
              Tab(text: l10n.busTabRural),
              if (teEnabled) Tab(text: l10n.busTabTe),
            ];
            final views = <Widget>[
              _BusListBody(items: urban),
              _BusListBody(items: rural),
              if (teEnabled) _BusListBody(items: te),
            ];
            return DefaultTabController(
              length: tabs.length,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: l10n.busSearchLineHint,
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: MaterialLocalizations.of(context)
                                    .deleteButtonTooltip,
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.clear_rounded),
                              ),
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.45),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  _BusCategoryTabBar(tabs: tabs),
                  Expanded(
                    child: TabBarView(
                      children: views,
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(child: Text(l10n.busCouldNotLoadLines)),
        );
      },
    );
  }
}

class _BusCategoryTabBar extends StatelessWidget {
  const _BusCategoryTabBar({required this.tabs});

  final List<Tab> tabs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extra = context.extraColors;
    final isDark = scheme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: extra.durationBadgeBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: extra.recentTileBorder),
        ),
        child: TabBar(
          indicatorSize: TabBarIndicatorSize.tab,
          dividerHeight: 0,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          labelColor:
              isDark ? selectedShellAccentColor(context) : scheme.primary,
          unselectedLabelColor: scheme.onSurfaceVariant,
          labelStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
          indicator: BoxDecoration(
            color: extra.floatingNavIndicator,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(4),
          tabs: tabs,
        ),
      ),
    );
  }
}

class _TimetablesNotDownloadedBody extends StatelessWidget {
  const _TimetablesNotDownloadedBody({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onOpenSettings,
  });

  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_download_outlined,
              size: 56,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onOpenSettings,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusListBody extends StatelessWidget {
  const _BusListBody({required this.items});

  final List<BusLine> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (items.isEmpty) {
      return Center(child: Text(l10n.busNoLinesInGroup));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        return _BusLineTile(
          line: item,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _BusStopsScreen(
                routeId: item.routeId,
                shortName: item.shortName,
                longName: item.longName,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BusLineTile extends StatelessWidget {
  const _BusLineTile({
    required this.line,
    required this.onTap,
  });

  final BusLine line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final extra = context.extraColors;
    final isDark = scheme.brightness == Brightness.dark;
    final badgeLabel =
        line.shortName.trim().isEmpty ? '—' : line.shortName.trim();
    final badge = accentBadgeColors(context);

    return Material(
      color: extra.recentTileBackground,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: extra.recentTileBorder),
            boxShadow: isDark
                ? null
                : const [
                    BoxShadow(
                      color: Color(0x0A0A3E96),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 44),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: badge.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: badge.foreground,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  line.longName.trim().isEmpty
                      ? l10n.busLineFallback(badgeLabel)
                      : line.longName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: mutedChromeColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
