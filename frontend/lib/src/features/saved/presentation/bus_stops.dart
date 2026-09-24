part of 'bus_tab.dart';

class _BusDetailHeader extends StatelessWidget {
  const _BusDetailHeader({
    required this.title,
    this.badgeLabel,
    this.trailing,
    this.subtitles = const [],
  });

  final String title;
  final String? badgeLabel;
  final Widget? trailing;
  final List<String> subtitles;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
    final l10n = AppLocalizations.of(context);
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
