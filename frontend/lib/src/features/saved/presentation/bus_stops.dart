part of 'bus_tab.dart';

class _BusDetailHeader extends StatelessWidget {
  const _BusDetailHeader({
    required this.title,
    this.badgeLabel,
    this.trailing,
  });

  final String title;
  final String? badgeLabel;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final extra = context.extraColors;
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
          padding: const EdgeInsets.fromLTRB(0, 4, 8, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                tooltip: l10n.busBack,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              if (badgeLabel != null) ...[
                Container(
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: badge.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
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
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: scheme.onSurface,
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
    this.initialStopId,
    this.initialDirectionId,
  });

  final String routeId;
  final String shortName;
  final String longName;

  /// Preselected stop and direction when opened from a stop board departure.
  final String? initialStopId;
  final String? initialDirectionId;

  @override
  ConsumerState<_BusStopsScreen> createState() => _BusStopsScreenState();
}

class _BusStopsScreenState extends ConsumerState<_BusStopsScreen> {
  late bool _isReverse = widget.initialDirectionId == '1';
  late String? _selectedStopId = widget.initialStopId;

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
    final l10n = AppLocalizations.of(context);
    final extra = context.extraColors;
    final scheme = Theme.of(context).colorScheme;
    final directionId = _isReverse ? '1' : '0';
    final stopsAsync = ref.watch(
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LineFavoriteButton(
                  line: BusLine(
                    routeId: widget.routeId,
                    shortName: widget.shortName,
                    longName: widget.longName,
                    mode: 'BUS',
                  ),
                ),
                IconButton(
                  tooltip: l10n.busReverseDirection,
                  onPressed: () => setState(() {
                    _isReverse = !_isReverse;
                    _selectedStopId = null;
                  }),
                  style: IconButton.styleFrom(
                    backgroundColor: extra.durationBadgeBackground,
                  ),
                  icon: Icon(
                    Icons.swap_horiz_rounded,
                    color: accentIconColor(context),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: stopsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) =>
                  Center(child: Text(l10n.busCouldNotLoadStops)),
              data: (items) {
                if (items.isEmpty) {
                  return Center(child: Text(l10n.busNoStopsFound));
                }
                final selectedId = _selectedStopId ?? items.first.stopId;
                final selected = items.firstWhere(
                  (s) => s.stopId == selectedId,
                  orElse: () => items.first,
                );
                // Each direction's stop list is in travel order, so the last
                // stop is where this direction goes.
                final destination = items.last.name.trim();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (destination.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          l10n.busTowards(destination),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.centerLeft,
                        ),
                        onPressed: () async {
                          final id = await Navigator.of(context).push<String>(
                            MaterialPageRoute(
                              builder: (_) => TimetableStopPickerPage(
                                stops: items,
                                selectedStopId: selected.stopId,
                              ),
                            ),
                          );
                          if (!mounted || id == null) return;
                          setState(() => _selectedStopId = id);
                        },
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.searchSelectStop,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${selected.stopSequence}. ${selected.name}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.unfold_more_rounded,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _EmbeddedLineTimetable(
                        routeId: widget.routeId,
                        shortName: widget.shortName,
                        longName: widget.longName,
                        stopId: selected.stopId,
                        stopName: selected.name,
                        directionId: directionId,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Week board for the selected stop on a line (Mon–Fri / Sat / Sun).
class _EmbeddedLineTimetable extends ConsumerStatefulWidget {
  const _EmbeddedLineTimetable({
    required this.routeId,
    required this.shortName,
    required this.longName,
    required this.stopId,
    required this.stopName,
    required this.directionId,
  });

  final String routeId;
  final String shortName;
  final String longName;
  final String stopId;
  final String stopName;
  final String directionId;

  @override
  ConsumerState<_EmbeddedLineTimetable> createState() =>
      _EmbeddedLineTimetableState();
}

class _EmbeddedLineTimetableState extends ConsumerState<_EmbeddedLineTimetable> {
  late final DateTime _mondayDate;
  late final DateTime _saturdayDate;
  late final DateTime _sundayDate;

  @override
  void initState() {
    super.initState();
    // Only the weekday matters: the tabs show the regular Mon–Fri / Sat /
    // Sun pattern, not this week's holidays.
    final now = DateTime.now();
    final monday = now.day - (now.weekday - DateTime.monday);
    _mondayDate = DateTime(now.year, now.month, monday);
    _saturdayDate = DateTime(now.year, now.month, monday + 5);
    _sundayDate = DateTime(now.year, now.month, monday + 6);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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

    return switch ((monFriTimetable, saturdayTimetable, sundayTimetable)) {
      (
        AsyncData(value: final mon),
        AsyncData(value: final sat),
        AsyncData(value: final sun),
      ) =>
        _WeekTimetableTable(
          monFri: mon,
          saturday: sat,
          sunday: sun,
          // Direction already scoped by directionId in the companion pack.
          expectedHeadsign: null,
        ),
      (AsyncError(), _, _) || (_, AsyncError(), _) || (_, _, AsyncError()) =>
        Center(child: Text(l10n.busCouldNotLoadTimetable)),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}
