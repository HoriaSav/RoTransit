import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/state/clock_provider.dart';
import '../../../core/theme/accent_badge_style.dart';
import '../../../core/errors/app_user_message.dart';
import '../../../core/theme/app_extra_colors.dart';
import '../../../core/ui/user_feedback.dart';
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
  const StopBoardSheet({super.key, required this.stop, this.clock});

  final StopSearchItem stop;

  /// Current time; tests pass a fixed clock. Defaults to [clockProvider].
  @visibleForTesting
  final DateTime Function()? clock;

  @override
  ConsumerState<StopBoardSheet> createState() => _StopBoardSheetState();
}

/// Minimum departures the first load tries to show before it stops widening.
const kStopBoardMinDepartures = 5;

/// Wall-clock minutes from [from] until the service day ends (04:00, when
/// the last after-midnight trips are done). Wall-clock like [stopBoard]'s
/// window, so DST nights also stop exactly at 04:00.
int minutesUntilServiceDayEnd(DateTime from) {
  final m = from.hour * 60 + from.minute;
  return (from.hour < 4 ? 4 * 60 : 28 * 60) - m;
}

class _StopBoardSheetState extends ConsumerState<StopBoardSheet>
    with WidgetsBindingObserver {
  static const _windowStep = 30;
  int _windowMinutes = _windowStep;
  late DateTime _from;
  final _scroll = ScrollController();
  List<StopBoardDeparture>? _items;
  Object? _error;
  bool _loading = false;
  DateTime? _feedEnd;
  late Future<bool> _favFuture;
  bool _favBusy = false;

  DateTime _now() {
    final DateTime Function() clock = widget.clock ?? ref.read(clockProvider);
    return clock();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _from = _now();
    _favFuture =
        ref.read(favoriteStopsRepositoryProvider).isStopFavorite(widget.stop.stopId);
    _loadFirst();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  /// Back from the background: start the board at the current time again so
  /// buses that already left drop off.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _loading) return;
    final now = _now();
    if (now.difference(_from).inMinutes < 1) return;
    _from = now;
    _loadFirst();
  }

  Future<List<StopBoardDeparture>> _fetch(int window) {
    return ref.read(companionCatalogProvider).stopBoard(
          stopId: widget.stop.stopId,
          from: _from,
          windowMinutes: window,
        );
  }

  /// First load: one fetch up to the end of the service day, then show the
  /// smallest 30-min window with enough departures (sparse stops widen).
  Future<void> _loadFirst() async {
    final maxWindow = math.max(_windowStep, minutesUntilServiceDayEnd(_from));
    try {
      final all = await _fetch(maxWindow);
      var window = _windowStep;
      List<StopBoardDeparture> inWindow() =>
          [for (final d in all) if (d.minutesAfterStart < window) d];
      var items = inWindow();
      while (items.length < kStopBoardMinDepartures && window < maxWindow) {
        window = math.min(window + _windowStep, maxWindow);
        items = inWindow();
      }
      final feedEnd = items.isEmpty ? await _feedEndIfPast() : null;
      if (!mounted) return;
      setState(() {
        _windowMinutes = window;
        _items = items;
        _feedEnd = feedEnd;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// The pack's last service date when [_from] is after it (the app needs
  /// an update), else null.
  Future<DateTime?> _feedEndIfPast() async {
    try {
      return await feedEndedOn(ref.read(companionCatalogProvider), _from);
    } catch (e) {
      debugPrint('Stop board: feed date range unavailable: $e');
      return null;
    }
  }

  /// "+30 min": same start time, longer window, so the new departures are
  /// appended and the list (and its scroll position) stays in place.
  Future<void> _showMore() async {
    if (_loading) return;
    setState(() => _loading = true);
    final window = _windowMinutes + _windowStep;
    try {
      final items = await _fetch(window);
      if (!mounted) return;
      setState(() {
        _windowMinutes = window;
        _items = items;
      });
    } catch (e) {
      debugPrint('Stop board: +$_windowStep min failed: $e');
      if (mounted) {
        showUserMessage(
          context,
          AppUserMessage.custom(
            AppLocalizations.of(context).stopBoardCouldNotLoad,
            severity: UserMessageSeverity.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFavorite() async {
    if (_favBusy) return;
    _favBusy = true;
    final repo = ref.read(favoriteStopsRepositoryProvider);
    try {
      await repo.toggleStop(widget.stop);
      ref.read(favoriteStopsRevisionProvider.notifier).state++;
    } catch (_) {
      if (mounted) {
        showUserMessage(
          context,
          AppUserMessage.custom(
            AppLocalizations.of(context).favoritesCouldNotSave,
            severity: UserMessageSeverity.error,
          ),
        );
      }
    } finally {
      _favBusy = false;
      if (mounted) {
        setState(() => _favFuture = repo.isStopFavorite(widget.stop.stopId));
      }
    }
  }

  Future<void> _openInMaps() async {
    final lat = widget.stop.lat;
    final lon = widget.stop.lon;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lon',
    );
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
        AppLocalizations.of(context).linkOpenFailed,
        severity: UserMessageSeverity.error,
      ),
    );
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

  /// Both ends of the ride ("Livada Poștei → Independenței"), falling back
  /// to the headsign or line name when the pack has no trip ends.
  String _rideLabel(StopBoardDeparture dep, AppLocalizations l10n) {
    final first = dep.firstStopName.trim();
    final last = dep.lastStopName.trim();
    if (first.isNotEmpty && last.isNotEmpty) return '$first → $last';
    if (dep.headsign.isNotEmpty) return dep.headsign;
    return dep.longName.isEmpty ? l10n.busLineFallback(dep.shortName) : dep.longName;
  }

  /// Long windows read "Until 04:00" instead of "Next 1440 min".
  String? get _windowEnd => _windowMinutes > 120
      ? CompanionCatalog.minutesToHhMm(
          (_from.hour * 60 + _from.minute + _windowMinutes) % (24 * 60))
      : null;

  String _fmtTime(String raw) {
    final mins = CompanionCatalog.timeToMinutes(raw);
    if (mins == null) return raw;
    final dayMins = mins % (24 * 60);
    return CompanionCatalog.minutesToHhMm(dayMins);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                        _windowEnd == null
                            ? l10n.stopBoardWindow(_windowMinutes)
                            : l10n.stopBoardUntil(_windowEnd!),
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
                      tooltip: fav ? l10n.favoriteRemove : l10n.favoriteStopAdd,
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
                  label: Text(l10n.stopOpenInGoogleMaps),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Builder(
              builder: (context) {
                final items = _items;
                if (_error != null && items == null) {
                  return Center(
                    child: Text(
                      l10n.stopBoardCouldNotLoad,
                      style: TextStyle(color: scheme.error),
                    ),
                  );
                }
                if (items == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (items.isEmpty) {
                  final feedEnd = _feedEnd;
                  return Center(
                    child: Text(
                      feedEnd != null
                          ? l10n.stopBoardFeedEnded(
                              CompanionCatalog.isoDate(feedEnd))
                          : _windowEnd != null
                              ? l10n.stopBoardEmptyUntil(_windowEnd!)
                              : l10n.stopBoardEmpty(_windowMinutes),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  );
                }
                return ListView.separated(
                  controller: _scroll,
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
                                      _rideLabel(dep, l10n),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
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
              onPressed: _items == null || _loading ? null : _showMore,
              child: Text(l10n.stopBoardShowMore(_windowStep)),
            ),
          ),
        ],
      ),
    );
  }
}
