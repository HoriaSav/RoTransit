part of 'bus_tab.dart';

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
    var matched = departures.where(_matchesDirection).toList();
    // If headsign filter would empty the board, show all scheduled times.
    if (matched.isEmpty && departures.isNotEmpty) {
      matched = departures;
    }
    for (final dep in matched) {
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
    final l10n = AppLocalizations.of(context);
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
