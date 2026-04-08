import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/transport_settings_provider.dart';
import '../../routes/domain/route_models.dart';
import '../../shell/shell_layout.dart';
import '../state/saved_providers.dart';

class BusTab extends StatelessWidget {
  const BusTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ColoredBox(
        color: const Color(0xFFF2F2F2),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: shellBottomContentPadding(context),
            ),
            child: const _BusLinesView(),
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
    final teEnabled = ref.watch(teTransportEnabledProvider);
    final buses = ref.watch(busesProvider);
    return buses.when(
      data: (items) {
        if (items.isEmpty) {
          return const Center(child: Text('No bus lines found.'));
        }
        final urban = _sortedByNumber(_filterUrban(items));
        final rural = _sortedByNumber(_filterRural(items));
        final te = _sortedByNumber(_filterTe(items));
        final tabs = <Tab>[
          const Tab(text: 'Urban'),
          const Tab(text: 'Rural'),
          if (teEnabled) const Tab(text: 'TE'),
        ];
        final views = <Widget>[
          _BusListBody(items: urban),
          _BusListBody(items: rural),
          if (teEnabled) _BusListBody(items: te),
        ];
        return DefaultTabController(
          length: tabs.length,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                child: TabBar(
                  tabs: tabs,
                ),
              ),
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
      error: (_, __) => const Center(child: Text('Could not load bus lines')),
    );
  }
}

class _BusListBody extends StatelessWidget {
  const _BusListBody({required this.items});

  final List<BusLine> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('No lines in this group.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          child: ListTile(
            title: Text(item.shortName.isEmpty ? item.longName : 'Bus ${item.shortName}'),
            subtitle: Text(item.longName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _BusStopsScreen(
                  routeId: item.routeId,
                  title: item.shortName.isEmpty ? item.longName : 'Bus ${item.shortName}',
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BusStopsScreen extends ConsumerStatefulWidget {
  const _BusStopsScreen({
    required this.routeId,
    required this.title,
  });

  final String routeId;
  final String title;

  @override
  ConsumerState<_BusStopsScreen> createState() => _BusStopsScreenState();
}

class _BusStopsScreenState extends ConsumerState<_BusStopsScreen> {
  bool _isReverse = false;

  @override
  Widget build(BuildContext context) {
    final directionId = _isReverse ? '1' : '0';
    final stops = ref.watch(
      routeStopsProvider((
        routeId: widget.routeId,
        directionId: directionId,
      )),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Reverse direction',
            onPressed: () => setState(() => _isReverse = !_isReverse),
            icon: const Icon(Icons.swap_horiz),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: stops.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('No stops found.'));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final stop = items[index];
              return ListTile(
                title: Text(stop.name),
                subtitle: Text('Stop ${stop.stopSequence}'),
                trailing: const Icon(Icons.schedule),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _BusTimetableScreen(
                      routeId: widget.routeId,
                      stopId: stop.stopId,
                      stopName: stop.name,
                      directionId: directionId,
                      expectedHeadsign: items.isNotEmpty ? items.last.name : null,
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('Could not load route stops')),
      ),
    );
  }
}

class _BusTimetableScreen extends ConsumerStatefulWidget {
  const _BusTimetableScreen({
    required this.routeId,
    required this.stopId,
    required this.stopName,
    required this.directionId,
    required this.expectedHeadsign,
  });

  final String routeId;
  final String stopId;
  final String stopName;
  final String directionId;
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.stopName)),
      body: switch ((monFriTimetable, saturdayTimetable, sundayTimetable)) {
        (AsyncData(value: final mon), AsyncData(value: final sat), AsyncData(value: final sun)) =>
          _WeekTimetableTable(
            monFri: mon,
            saturday: sat,
            sunday: sun,
            expectedHeadsign: widget.expectedHeadsign,
          ),
        (AsyncError(), _, _) || (_, AsyncError(), _) || (_, _, AsyncError()) =>
          const Center(child: Text('Could not load timetable')),
        _ => const Center(child: CircularProgressIndicator()),
      },
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

  List<String> _displayHours(
    Map<String, List<String>> monMap,
    Map<String, List<String>> satMap,
    Map<String, List<String>> sunMap,
  ) {
    return List<String>.generate(
      21,
      (index) => (index + 3).toString().padLeft(2, '0'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monMap = _groupByHour(monFri.departures);
    final satMap = _groupByHour(saturday.departures);
    final sunMap = _groupByHour(sunday.departures);

    final allHours = _displayHours(monMap, satMap, sunMap);

    if (allHours.isEmpty) {
      return const Center(child: Text('No departures for this stop.'));
    }

    const brandBlue = Color(0xFF0A3E96);
    const headerStyle = TextStyle(
      fontWeight: FontWeight.bold,
      color: Colors.white,
    );
    const cellStyle = TextStyle(height: 1.2);

    Widget cellText(String value, {TextStyle? style}) {
      return Text(
        value,
        softWrap: false,
        style: style,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Table(
                    defaultColumnWidth: const IntrinsicColumnWidth(),
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    border: TableBorder.all(
                      color: const Color(0xFF0A3E96),
                      width: 1,
                    ),
                    children: [
                      const TableRow(
                        decoration: BoxDecoration(color: brandBlue),
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                            child: Text('Hour', style: headerStyle),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                            child: Text('Mon-Fri', style: headerStyle),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                            child: Text('Sat', style: headerStyle),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                            child: Text('Sun', style: headerStyle),
                          ),
                        ],
                      ),
                      ...allHours.map(
                        (hour) => TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 6,
                              ),
                              child: cellText(hour, style: cellStyle),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 6,
                              ),
                              child: cellText(
                                monMap[hour]?.join('  ') ?? '--',
                                style: cellStyle,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 6,
                              ),
                              child: cellText(
                                satMap[hour]?.join('  ') ?? '--',
                                style: cellStyle,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 6,
                              ),
                              child: cellText(
                                sunMap[hour]?.join('  ') ?? '--',
                                style: cellStyle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
