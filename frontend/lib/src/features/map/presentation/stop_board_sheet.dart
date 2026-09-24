import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/accent_badge_style.dart';
import '../../../core/theme/app_extra_colors.dart';
import '../../favorites/data/favorite_stops_repository.dart';
import '../../routes/domain/route_models.dart';
import '../../shell/state/bus_line_open_provider.dart';
import '../../shell/state/navigation_provider.dart';
import '../data/companion_catalog.dart';

Future<void> showStopBoardSheet(
  BuildContext context, {
  required StopSearchItem stop,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => StopBoardSheet(stop: stop),
  );
}

class StopBoardSheet extends ConsumerStatefulWidget {
  const StopBoardSheet({super.key, required this.stop});

  final StopSearchItem stop;

  @override
  ConsumerState<StopBoardSheet> createState() => _StopBoardSheetState();
}

class _StopBoardSheetState extends ConsumerState<StopBoardSheet> {
  static const _windowStep = 30;
  int _windowMinutes = _windowStep;
  late Future<List<StopBoardDeparture>> _future;
  late Future<bool> _favFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final from = DateTime.now();
    _future = ref.read(companionCatalogProvider).stopBoard(
          stopId: widget.stop.stopId,
          from: from,
          windowMinutes: _windowMinutes,
        );
    _favFuture =
        ref.read(favoriteStopsRepositoryProvider).isStopFavorite(widget.stop.stopId);
  }

  Future<void> _toggleFavorite() async {
    await ref.read(favoriteStopsRepositoryProvider).toggleStop(widget.stop);
    ref.read(favoriteStopsRevisionProvider.notifier).state++;
    setState(() {
      _favFuture = ref
          .read(favoriteStopsRepositoryProvider)
          .isStopFavorite(widget.stop.stopId);
    });
  }

  Future<void> _openInMaps() async {
    final lat = widget.stop.lat;
    final lon = widget.stop.lon;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lon',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openLine(StopBoardDeparture dep) {
    final line = BusLine(
      routeId: dep.routeId,
      shortName: dep.shortName,
      longName: dep.longName,
      mode: 'BUS',
    );
    ref.read(pendingOpenBusLineProvider.notifier).state = OpenBusLineRequest(
      line: line,
      stopId: widget.stop.stopId,
      directionId: dep.directionId,
    );
    ref.read(selectedTabProvider.notifier).state = 1;
    Navigator.of(context).maybePop();
  }

  String _fmtTime(String raw) {
    final mins = CompanionCatalog.timeToMinutes(raw);
    if (mins == null) return raw;
    final dayMins = mins % (24 * 60);
    return CompanionCatalog.minutesToHhMm(dayMins);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extra = context.extraColors;
    final badge = accentBadgeColors(context);
    final height = MediaQuery.sizeOf(context).height * 0.72;

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.stop.name,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Scheduled · next $_windowMinutes min',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FutureBuilder<bool>(
                  future: _favFuture,
                  builder: (context, snap) {
                    final fav = snap.data == true;
                    return IconButton(
                      tooltip: fav ? 'Remove favorite' : 'Favorite stop',
                      onPressed: _toggleFavorite,
                      icon: Icon(
                        fav ? Icons.star_rounded : Icons.star_border_rounded,
                        color: fav ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _openInMaps,
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Open in Google Maps'),
                ),
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.directions_outlined, size: 18),
                  label: const Text('Directions (soon)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<StopBoardDeparture>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Could not load schedule',
                      style: TextStyle(color: scheme.error),
                    ),
                  );
                }
                final items = snap.data ?? const <StopBoardDeparture>[];
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      'No scheduled departures in the next $_windowMinutes minutes',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final dep = items[i];
                    return Material(
                      color: extra.recentTileBackground,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _openLine(dep),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Container(
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 34,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: badge.background,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  dep.shortName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: badge.foreground,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      dep.headsign.isEmpty
                                          ? (dep.longName.isEmpty
                                              ? 'Line ${dep.shortName}'
                                              : dep.longName)
                                          : dep.headsign,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      'Schedule',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _fmtTime(dep.departureTime),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FilledButton.tonal(
              onPressed: () {
                setState(() {
                  _windowMinutes += _windowStep;
                  _reload();
                });
              },
              child: Text('Show next $_windowStep minutes'),
            ),
          ),
        ],
      ),
    );
  }
}
