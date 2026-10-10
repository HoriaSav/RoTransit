part of 'bus_tab.dart';

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

  static const _hourColumnWidth = 48.0;
  static const _maxHourColumnWidth = 72.0;
  static const _cellHorizontalPadding = 8.0;
  static const _hourHeaderStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    height: 1.2,
  );

  /// Wide enough for the localized "Hour" header on one line ("Stunde"),
  /// at least 48 px, at most 72 px (the header shrinks beyond that).
  static double _hourColumnWidthFor(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: DefaultTextStyle.of(context).style.merge(_hourHeaderStyle),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width + 2 * _cellHorizontalPadding;
    painter.dispose();
    return width.ceilToDouble().clamp(_hourColumnWidth, _maxHourColumnWidth);
  }

  /// Pinch-to-zoom limit; the default (scale 1) already fits the width.
  static const maxZoom = 2.5;

  bool _matchesDirection(StopTimetableEntry dep) {
    final target = expectedHeadsign?.trim().toLowerCase();
    if (target == null || target.isEmpty) return true;
    final headsign = dep.headsign.trim().toLowerCase();
    if (headsign.isEmpty) return true;
    return headsign == target ||
        headsign.contains(target) ||
        target.contains(headsign);
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
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: scheme.onSurface,
      height: 1.35,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

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
              // Fixed layout: the whole table fits the screen width; the
              // three day columns share what is left after the hour column
              // and minutes wrap inside their cell. Pinch to zoom in.
              final tableWidth = constraints.maxWidth;
              final hourWidth = _hourColumnWidthFor(context, headerLabels[0]);
              final dayWidth = ((tableWidth - hourWidth - 3) / 3)
                  .clamp(0.0, double.infinity);
              final monColumnWidth = dayWidth;
              final satColumnWidth = dayWidth;
              final sunColumnWidth = dayWidth;
              final dayColumnWidths = [dayWidth, dayWidth, dayWidth];

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
                          _TimetableHourHeaderCell(
                            label: headerLabels[0],
                            width: hourWidth,
                          ),
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
                    for (var index = 0;
                        index < visibleHours.length;
                        index++) ...[
                      if (index > 0)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: extra.recentTileBorder,
                        ),
                      buildTableRow(
                        backgroundColor: index.isEven
                            ? Colors.transparent
                            : extra.durationBadgeBackground
                                .withValues(alpha: 0.55),
                        children: [
                          _TimetableHourCell(
                            hour: visibleHours[index],
                            width: hourWidth,
                          ),
                          _TimetableColumnDivider(color: dividerColor),
                          _TimetableMinutesCell(
                            minutes: monMap[visibleHours[index]],
                            width: monColumnWidth,
                            textStyle: minuteStyle,
                          ),
                          _TimetableColumnDivider(color: dividerColor),
                          _TimetableMinutesCell(
                            minutes: satMap[visibleHours[index]],
                            width: satColumnWidth,
                            textStyle: minuteStyle,
                          ),
                          _TimetableColumnDivider(color: dividerColor),
                          _TimetableMinutesCell(
                            minutes: sunMap[visibleHours[index]],
                            width: sunColumnWidth,
                            textStyle: minuteStyle,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );

              // One-finger drag pans (scrolls through the hours), two
              // fingers zoom. The table is laid out at its full height.
              return InteractiveViewer(
                key: const ValueKey('week-timetable-zoom'),
                constrained: false,
                minScale: 1,
                maxScale: maxZoom,
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
  const _TimetableHourHeaderCell({required this.label, required this.width});

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
        // One line in every locale ("Stunde"): shrink to fit, never wrap.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: _WeekTimetableTable._hourHeaderStyle,
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
  const _TimetableHourCell({required this.hour, required this.width});

  final String hour;
  final double width;

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
        width: width,
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
            values == null || values.isEmpty ? '--' : values.join('  '),
            softWrap: true,
            textAlign: TextAlign.left,
            style: values == null || values.isEmpty
                ? TextStyle(
                    fontSize: 15,
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
