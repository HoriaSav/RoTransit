import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotransit_frontend/l10n/app_localizations.dart';

import '../../../core/branding/operator_branding.dart';
import '../../../core/state/transport_settings_provider.dart';
import '../../../core/theme/accent_badge_style.dart';
import '../../../core/theme/app_extra_colors.dart';
import '../../routes/domain/route_models.dart';
import '../../shell/shell_layout.dart';
import '../../shell/state/navigation_provider.dart';
import '../state/saved_providers.dart';

const _kBusTabHeaderHeight = 76.0;

class BusTab extends StatelessWidget {
  const BusTab({super.key});

  @override
  Widget build(BuildContext context) {
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

class _BusLinesView extends ConsumerWidget {
  const _BusLinesView();

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final teEnabled = ref.watch(teTransportEnabledProvider);
    final packInstalled = ref.watch(cityOfflinePackInstalledProvider);
    final buses = ref.watch(busesProvider);

    return packInstalled.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(child: Text(l10n.busTabTimetablesNotDownloadedBody)),
      data: (installed) {
        if (!installed) {
          return _TimetablesNotDownloadedBody(
            title: l10n.busTabTimetablesNotDownloadedTitle,
            body: l10n.busTabTimetablesNotDownloadedBody,
            actionLabel: l10n.busTabOpenSettings,
            onOpenSettings: () =>
                ref.read(selectedTabProvider.notifier).state = 3,
          );
        }
        return buses.when(
          data: (items) {
            if (items.isEmpty) {
              return Center(child: Text(l10n.busNoLinesFound));
            }
            final urban = _sortedByNumber(_filterUrban(items));
            final rural = _sortedByNumber(_filterRural(items));
            final te = _sortedByNumber(_filterTe(items));
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
          labelColor: isDark
              ? selectedShellAccentColor(context)
              : scheme.primary,
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
    final l10n = AppLocalizations.of(context)!;
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
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final extra = context.extraColors;
    final isDark = scheme.brightness == Brightness.dark;
    final badgeLabel = line.shortName.trim().isEmpty ? '—' : line.shortName.trim();
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

class _BusDetailHeader extends StatelessWidget {
  const _BusDetailHeader({
    required this.title,
    this.badgeLabel,
    this.leadingIcon,
    this.trailing,
    this.subtitles = const [],
  });

  final String title;
  final String? badgeLabel;
  final IconData? leadingIcon;
  final Widget? trailing;
  final List<String> subtitles;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final extra = context.extraColors;
    final hasSubtitles = subtitles.isNotEmpty;
    final badge = accentBadgeColors(context);

    return SafeArea(
      bottom: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: extra.shellHeader,
          border: Border(
            bottom: BorderSide(color: extra.recentTileBorder, width: 1),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(0, 4, 8, hasSubtitles ? 10 : 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                tooltip: l10n.busBack,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              if (badgeLabel != null || leadingIcon != null) ...[
                Container(
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: badge.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: leadingIcon != null
                      ? Icon(leadingIcon, size: 18, color: badge.foreground)
                      : Text(
                          badgeLabel!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: badge.foreground,
                            height: 1,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: hasSubtitles ? 17 : 16,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: scheme.onSurface,
                      ),
                    ),
                    ...subtitles.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          line,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.25,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _BusStopsScreen extends ConsumerStatefulWidget {
  const _BusStopsScreen({
    required this.routeId,
    required this.shortName,
    required this.longName,
  });

  final String routeId;
  final String shortName;
  final String longName;

  @override
  ConsumerState<_BusStopsScreen> createState() => _BusStopsScreenState();
}

class _BusStopsScreenState extends ConsumerState<_BusStopsScreen> {
  bool _isReverse = false;

  String get _badgeLabel {
    final short = widget.shortName.trim();
    return short.isEmpty ? '—' : short;
  }

  String _headerTitle(AppLocalizations l10n) {
    final long = widget.longName.trim();
    if (long.isNotEmpty) return long;
    final short = widget.shortName.trim();
    return short.isEmpty ? l10n.busRouteFallback : l10n.busLineFallback(short);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final extra = context.extraColors;
    final scheme = Theme.of(context).colorScheme;
    final directionId = _isReverse ? '1' : '0';
    final stops = ref.watch(
      routeStopsProvider((
        routeId: widget.routeId,
        directionId: directionId,
      )),
    );
    return Scaffold(
      backgroundColor: extra.tabBackground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BusDetailHeader(
            badgeLabel: _badgeLabel,
            title: _headerTitle(l10n),
            trailing: IconButton(
              tooltip: l10n.busReverseDirection,
              onPressed: () => setState(() => _isReverse = !_isReverse),
              style: IconButton.styleFrom(
                backgroundColor: extra.durationBadgeBackground,
              ),
              icon: Icon(
                Icons.swap_horiz_rounded,
                color: accentIconColor(context),
              ),
            ),
          ),
          Expanded(
            child: stops.when(
              data: (items) {
                if (items.isEmpty) {
                  return Center(child: Text(l10n.busNoStopsFound));
                }
                final destination = items.last.name.trim();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (destination.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          _isReverse
                              ? l10n.busFrom(destination)
                              : l10n.busTowards(destination),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final stop = items[index];
                          return _BusStopTile(
                            name: stop.name,
                            sequence: stop.stopSequence,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => _BusTimetableScreen(
                                  routeId: widget.routeId,
                                  shortName: widget.shortName,
                                  longName: widget.longName,
                                  stopId: stop.stopId,
                                  stopName: stop.name,
                                  directionId: directionId,
                                  destinationName: destination,
                                  isReversed: _isReverse,
                                  expectedHeadsign:
                                      destination.isEmpty ? null : destination,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) =>
                  Center(child: Text(l10n.busCouldNotLoadStops)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BusStopTile extends StatelessWidget {
  const _BusStopTile({
    required this.name,
    required this.sequence,
    required this.onTap,
  });

  final String name;
  final int sequence;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extra = context.extraColors;
    final isDark = scheme.brightness == Brightness.dark;
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: badge.background,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$sequence',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: badge.foreground,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: extra.durationBadgeBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.schedule_rounded,
                  size: 20,
                  color: accentIconColor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusTimetableScreen extends ConsumerStatefulWidget {
  const _BusTimetableScreen({
    required this.routeId,
    required this.shortName,
    required this.longName,
    required this.stopId,
    required this.stopName,
    required this.directionId,
    required this.destinationName,
    required this.isReversed,
    required this.expectedHeadsign,
  });

  final String routeId;
  final String shortName;
  final String longName;
  final String stopId;
  final String stopName;
  final String directionId;
  final String destinationName;
  final bool isReversed;
  final String? expectedHeadsign;

  @override
  ConsumerState<_BusTimetableScreen> createState() => _BusTimetableScreenState();
}

class _BusTimetableScreenState extends ConsumerState<_BusTimetableScreen> {
  late final DateTime _mondayDate;
  late final DateTime _saturdayDate;
  late final DateTime _sundayDate;

  @override
  void initState() {
    super.initState();
    final base = DateTime.now();
    final date = DateTime(base.year, base.month, base.day);
    _mondayDate = date.subtract(Duration(days: date.weekday - DateTime.monday));
    _saturdayDate = _mondayDate.add(const Duration(days: 5));
    _sundayDate = _mondayDate.add(const Duration(days: 6));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final monFriTimetable = ref.watch(
      routeTimetableProvider((
        routeId: widget.routeId,
        stopId: widget.stopId,
        serviceDate: _mondayDate,
        directionId: widget.directionId,
      )),
    );
    final saturdayTimetable = ref.watch(
      routeTimetableProvider((
        routeId: widget.routeId,
        stopId: widget.stopId,
        serviceDate: _saturdayDate,
        directionId: widget.directionId,
      )),
    );
    final sundayTimetable = ref.watch(
      routeTimetableProvider((
        routeId: widget.routeId,
        stopId: widget.stopId,
        serviceDate: _sundayDate,
        directionId: widget.directionId,
      )),
    );
    final extra = context.extraColors;
    final short = widget.shortName.trim();
    final long = widget.longName.trim();
    final destination = widget.destinationName.trim();
    final lineLabel = long.isNotEmpty
        ? (short.isEmpty ? long : l10n.busLineTitle(short, long))
        : (short.isEmpty ? l10n.busRouteFallback : l10n.busLineFallback(short));
    final subtitles = <String>[
      lineLabel,
      if (destination.isNotEmpty)
        widget.isReversed
            ? l10n.busFrom(destination)
            : l10n.busTowards(destination),
    ];

    return Scaffold(
      backgroundColor: extra.tabBackground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BusDetailHeader(
            badgeLabel: short.isEmpty ? null : short,
            title: widget.stopName,
            subtitles: subtitles,
          ),
          Expanded(
            child: switch ((monFriTimetable, saturdayTimetable, sundayTimetable)) {
              (
                AsyncData(value: final mon),
                AsyncData(value: final sat),
                AsyncData(value: final sun),
              ) =>
                _WeekTimetableTable(
                  monFri: mon,
                  saturday: sat,
                  sunday: sun,
                  expectedHeadsign: widget.expectedHeadsign,
                ),
              (AsyncError(), _, _) ||
              (_, AsyncError(), _) ||
              (_, _, AsyncError()) =>
                Center(child: Text(l10n.busCouldNotLoadTimetable)),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

class _WeekTimetableTable extends StatelessWidget {
  const _WeekTimetableTable({
    required this.monFri,
    required this.saturday,
    required this.sunday,
    this.expectedHeadsign,
  });

  final StopTimetable monFri;
  final StopTimetable saturday;
  final StopTimetable sunday;
  final String? expectedHeadsign;

  static const _hourColumnWidth = 56.0;
  static const _cellHorizontalPadding = 10.0;
  static const _minDayColumnWidth = 96.0;

  static double _minuteColumnWidth(
    BuildContext context,
    Map<String, List<String>> map,
    List<String> hours,
    TextStyle style,
  ) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    var maxWidth = _minDayColumnWidth;
    for (final hour in hours) {
      final values = map[hour];
      if (values == null || values.isEmpty) continue;
      final line = values.join('   ');
      painter.text = TextSpan(text: line, style: style);
      painter.layout(maxWidth: double.infinity);
      final measured = painter.width + (_cellHorizontalPadding * 2) + 16;
      final estimated = line.length * 11.0 + (_cellHorizontalPadding * 2) + 16;
      maxWidth = math.max(maxWidth, math.max(measured, estimated));
    }
    return maxWidth.ceilToDouble();
  }

  bool _matchesDirection(StopTimetableEntry dep) {
    final target = expectedHeadsign?.trim().toLowerCase();
    if (target == null || target.isEmpty) return true;
    final headsign = dep.headsign.trim().toLowerCase();
    if (headsign.isEmpty) return true;
    return headsign == target || headsign.contains(target) || target.contains(headsign);
  }

  Map<String, List<String>> _groupByHour(List<StopTimetableEntry> departures) {
    final out = <String, List<String>>{};
    for (final dep in departures.where(_matchesDirection)) {
      final parts = dep.departureTime.split(':');
      if (parts.length < 2) continue;
      final hour = parts[0].padLeft(2, '0');
      final minute = parts[1].padLeft(2, '0');
      final minutes = out.putIfAbsent(hour, () => <String>[]);
      if (!minutes.contains(minute)) {
        minutes.add(minute);
      }
    }
    for (final entry in out.entries) {
      entry.value.sort();
    }
    return out;
  }

  List<String> _displayHours() {
    return List<String>.generate(
      21,
      (index) => (index + 3).toString().padLeft(2, '0'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final monMap = _groupByHour(monFri.departures);
    final satMap = _groupByHour(saturday.departures);
    final sunMap = _groupByHour(sunday.departures);

    if (monMap.isEmpty && satMap.isEmpty && sunMap.isEmpty) {
      return Center(child: Text(l10n.busNoDepartures));
    }

    final scheme = Theme.of(context).colorScheme;
    final extra = context.extraColors;
    final isDark = scheme.brightness == Brightness.dark;
    final visibleHours = _displayHours()
        .where(
          (hour) =>
              monMap.containsKey(hour) ||
              satMap.containsKey(hour) ||
              sunMap.containsKey(hour),
        )
        .toList();
    final headerLabels = [
      l10n.timetableHour,
      l10n.timetableWeekdays,
      l10n.timetableSaturday,
      l10n.timetableSunday,
    ];
    final dividerColor = isDark
        ? extra.recentTileBorder
        : scheme.primary.withValues(alpha: 0.28);
    final minuteStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: scheme.onSurface,
      height: 1.35,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final monColumnWidth =
        _minuteColumnWidth(context, monMap, visibleHours, minuteStyle);
    final satColumnWidth =
        _minuteColumnWidth(context, satMap, visibleHours, minuteStyle);
    final sunColumnWidth =
        _minuteColumnWidth(context, sunMap, visibleHours, minuteStyle);
    final dayColumnWidths = [monColumnWidth, satColumnWidth, sunColumnWidth];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: extra.recentTileBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: extra.recentTileBorder, width: 1.5),
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tableWidth = _hourColumnWidth +
                  dayColumnWidths.fold<double>(0, (sum, w) => sum + w) +
                  3;

              Widget buildTableRow({
                required List<Widget> children,
                Color? backgroundColor,
              }) {
                return ColoredBox(
                  color: backgroundColor ?? Colors.transparent,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                );
              }

              final table = SizedBox(
                width: tableWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(color: scheme.primary),
                      child: buildTableRow(
                        children: [
                          _TimetableHourHeaderCell(label: headerLabels[0]),
                          _TimetableColumnDivider(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                          for (var i = 0; i < headerLabels.length - 1; i++) ...[
                            _TimetableDayHeaderCell(
                              label: headerLabels[i + 1],
                              width: dayColumnWidths[i],
                            ),
                            if (i < headerLabels.length - 2)
                              _TimetableColumnDivider(
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                          ],
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: extra.recentTileBorder,
                    ),
                    Expanded(
                      child: ListView.separated(
                        primary: false,
                        padding: EdgeInsets.zero,
                        itemCount: visibleHours.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          thickness: 1,
                          color: extra.recentTileBorder,
                        ),
                        itemBuilder: (context, index) {
                          final hour = visibleHours[index];
                          final stripe = index.isEven
                              ? Colors.transparent
                              : extra.durationBadgeBackground
                                  .withValues(alpha: 0.55);
                          return buildTableRow(
                            backgroundColor: stripe,
                            children: [
                              _TimetableHourCell(hour: hour),
                              _TimetableColumnDivider(color: dividerColor),
                              _TimetableMinutesCell(
                                minutes: monMap[hour],
                                width: monColumnWidth,
                                textStyle: minuteStyle,
                              ),
                              _TimetableColumnDivider(color: dividerColor),
                              _TimetableMinutesCell(
                                minutes: satMap[hour],
                                width: satColumnWidth,
                                textStyle: minuteStyle,
                              ),
                              _TimetableColumnDivider(color: dividerColor),
                              _TimetableMinutesCell(
                                minutes: sunMap[hour],
                                width: sunColumnWidth,
                                textStyle: minuteStyle,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );

              if (tableWidth <= constraints.maxWidth) {
                return table;
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: table,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TimetableColumnDivider extends StatelessWidget {
  const _TimetableColumnDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return VerticalDivider(
      width: 1,
      thickness: 1,
      color: color,
    );
  }
}

class _TimetableHourHeaderCell extends StatelessWidget {
  const _TimetableHourHeaderCell({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _WeekTimetableTable._hourColumnWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: _WeekTimetableTable._cellHorizontalPadding,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimetableDayHeaderCell extends StatelessWidget {
  const _TimetableDayHeaderCell({
    required this.label,
    required this.width,
  });

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: _WeekTimetableTable._cellHorizontalPadding,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimetableHourCell extends StatelessWidget {
  const _TimetableHourCell({required this.hour});

  final String hour;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extra = context.extraColors;
    final isDark = scheme.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? extra.durationBadgeBackground
            : extra.floatingNavIndicator.withValues(alpha: 0.45),
      ),
      child: SizedBox(
        width: _WeekTimetableTable._hourColumnWidth,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 12,
            horizontal: _WeekTimetableTable._cellHorizontalPadding,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              hour,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: isDark ? scheme.onSurface : scheme.primary,
                height: 1.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimetableMinutesCell extends StatelessWidget {
  const _TimetableMinutesCell({
    this.minutes,
    required this.width,
    required this.textStyle,
  });

  final List<String>? minutes;
  final double width;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final values = minutes;

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: _WeekTimetableTable._cellHorizontalPadding,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            values == null || values.isEmpty ? '--' : values.join('   '),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            textAlign: TextAlign.left,
            style: values == null || values.isEmpty
                ? TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: mutedChromeColor(context, lightAlpha: 0.55),
                    height: 1.35,
                  )
                : textStyle,
          ),
        ),
      ),
    );
  }
}
