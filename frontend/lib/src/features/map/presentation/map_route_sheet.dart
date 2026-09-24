part of 'map_tab.dart';

class _RouteOptionCard extends StatefulWidget {
  const _RouteOptionCard({
    required this.onTap,
    required this.child,
  });

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_RouteOptionCard> createState() => _RouteOptionCardState();
}

class _RouteOptionCardState extends State<_RouteOptionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Card(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: widget.child,
        ),
      ),
    );
  }
}

class _RouteListPanel extends StatelessWidget {
  const _RouteListPanel({
    required this.onReturnToSearch,
    required this.onSheetDragDelta,
    this.allowSheetResize = true,
    required this.options,
    required this.canLoadMore,
    required this.remainingToReveal,
    this.remainingOnServer = 0,
    this.isLoadingMore = false,
    required this.onLoadMore,
    required this.onTapOption,
    required this.scrollController,
  });

  final VoidCallback onReturnToSearch;
  final ValueChanged<double> onSheetDragDelta;
  final bool allowSheetResize;
  final List<RouteOption> options;
  final bool canLoadMore;
  /// Itineraries still hidden locally or in the next fetch batch.
  final int remainingToReveal;
  /// Itineraries not yet fetched from the backend (for “N left” copy).
  final int remainingOnServer;
  final bool isLoadingMore;
  final Future<void> Function() onLoadMore;
  final void Function(RouteOption option, int resultIndex) onTapOption;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final itemCount = options.isEmpty
        ? 1
        : options.length + (canLoadMore ? 1 : 0);
    final fastestMinutes = options.isEmpty
        ? 0
        : options
            .map((o) => (o.durationSeconds / 60).round())
            .reduce(math.min);
    final shortestWalk = options.isEmpty
        ? 0
        : options.map((o) => o.walkDistanceMeters).reduce(math.min);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RouteSheetDragHandle(
          onDragDelta: onSheetDragDelta,
          allowDrag: allowSheetResize,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Row(
            children: [
              _mapSheetBackIconButton(
                context: context,
                onPressed: onReturnToSearch,
              ),
              const Spacer(),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            padding: EdgeInsets.zero,
            itemCount: itemCount,
            itemBuilder: (context, index) {
        if (options.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Center(child: Text(l10n.mapSearchRoutesHint)),
          );
        }
        if (canLoadMore && index == options.length) {
          final batch =
              math.min(kRouteSearchPageSize, remainingToReveal);
          final String label;
          if (isLoadingMore) {
            label = l10n.mapLoading;
          } else if (remainingOnServer > 0) {
            label = batch >= kRouteSearchPageSize
                ? l10n.mapLoadMoreTripsWithRemaining(
                    kRouteSearchPageSize,
                    remainingOnServer,
                  )
                : l10n.mapLoadMoreTripsWithRemaining(batch, remainingOnServer);
          } else {
            final tripWord =
                batch == 1 ? l10n.mapTripSingular : l10n.mapTripPlural;
            label = batch >= kRouteSearchPageSize
                ? l10n.mapLoadNextTrips(kRouteSearchPageSize)
                : l10n.mapLoadMoreTrips(batch, tripWord);
          }
          return Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton(
              onPressed: isLoadingMore ? null : () => onLoadMore(),
              child: isLoadingMore
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(label),
            ),
          );
        }
        final item = options[index];
        final start = item.legs.isEmpty
            ? null
            : DateTime.fromMillisecondsSinceEpoch(item.legs.first.startTime);
        final end = item.legs.isEmpty
            ? null
            : DateTime.fromMillisecondsSinceEpoch(item.legs.last.endTime);
        final timeFmt = DateFormat('h:mm a');
        final minutes = (item.durationSeconds / 60).round();
        final isFastest = minutes == fastestMinutes;
        final isShortestWalk = item.walkDistanceMeters == shortestWalk;
        final hasExtraWalk = item.walkDistanceMeters > shortestWalk;
        final scheme = Theme.of(context).colorScheme;
        final extra = context.extraColors;

        return _RouteOptionCard(
          onTap: () => onTapOption(item, index),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            start == null || end == null
                                ? '--'
                                : '${timeFmt.format(start)} - ${timeFmt.format(end)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 21,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 7),
                          _TransitSummaryChipsRow(option: item),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.directions_walk,
                                size: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: _kMetaIconTextGap),
                              Text(
                                formatDistanceForDisplay(
                                  item.walkDistanceMeters.toDouble(),
                                ),
                                style: TextStyle(
                                  color: hasExtraWalk
                                      ? extra.walkExtraColor
                                      : isShortestWalk
                                          ? extra.walkBestColor
                                          : scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w400,
                                  fontSize: 13,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: _kMetaBulletGap,
                                ),
                                child: Text(
                                  '•',
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.42),
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.sync_alt,
                                size: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: _kMetaIconTextGap),
                              Text(
                                l10n.mapTransferLabel(item.transfers),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: extra.durationBadgeBackground,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            child: Text(
                              '($minutes min)',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 11.5,
                                color: isFastest
                                    ? extra.durationBestColor
                                    : scheme.onSurfaceVariant
                                        .withValues(alpha: 0.78),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: _kDurationPriceGap),
                        Text(
                          l10n.mapPriceLei(item.estimatedPriceLei),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
            },
          ),
        ),
      ],
    );
  }
}

class _RouteDetailsPanel extends ConsumerWidget {
  const _RouteDetailsPanel({
    required this.cityId,
    required this.option,
    required this.sheetHeight,
    required this.onSheetDragDelta,
    this.onSheetDragEnd,
    required this.highlightedLegIndex,
    required this.onLegHighlightChanged,
    required this.onBack,
    this.showSaveToFavorites = true,
  });

  final String cityId;
  final RouteOption option;
  final double sheetHeight;
  final ValueChanged<double> onSheetDragDelta;
  final VoidCallback? onSheetDragEnd;
  final int highlightedLegIndex;
  final ValueChanged<int> onLegHighlightChanged;
  final VoidCallback onBack;
  final bool showSaveToFavorites;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final timeFmt = DateFormat('h:mm a');
    final scheme = Theme.of(context).colorScheme;
    final legs = option.legs;
    final safeHighlight = legs.isEmpty
        ? 0
        : math.min(legs.length - 1, math.max(0, highlightedLegIndex));
    final showItineraryBody = sheetHeight >= _kDetailsSheetBodyMinHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RouteSheetDragHandle(
          onDragDelta: onSheetDragDelta,
          onDragEnd: onSheetDragEnd,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 16, 8),
          child: Row(
            children: [
              _mapSheetBackIconButton(context: context, onPressed: onBack),
            ],
          ),
        ),
        if (showItineraryBody)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${(option.durationSeconds / 60).round()} min',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _TransitSummaryChipsRow(option: option),
                    const SizedBox(height: 8),
                    Text(
                      l10n.mapTransfersAndPrice(
                        l10n.mapTransferLabel(option.transfers),
                        l10n.mapPriceLei(option.estimatedPriceLei),
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.92),
                      ),
                    ),
                    if (option.fareRule.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        option.fareRule,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (showSaveToFavorites) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonal(
                          onPressed: () async {
                            final mapState = ref.read(searchMapStateProvider);
                            await ref.read(saveRouteControllerProvider).save(
                                  cityId: cityId,
                                  option: option,
                                  originLabel: mapState.originLabel,
                                  destinationLabel: mapState.destinationLabel,
                                );
                            if (context.mounted) {
                              showUserMessage(
                                context,
                                AppUserMessages.addedToFavorites,
                              );
                            }
                          },
                          child: Text(l10n.mapAddToFavorites),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      l10n.mapSteps,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < legs.length; i++)
                      _RouteTimelineLegRow(
                        leg: legs[i],
                        isHighlighted: i == safeHighlight,
                        timeFmt: timeFmt,
                        onTap: () => onLegHighlightChanged(i),
                      ),
                  ],
                ),
              ),
            )
        else
          const Spacer(),
      ],
    );
  }
}

/// Primary title for a step: mode name + line pill using the same [Color] as the map leg.
Widget _transitLineTitleRow(
  RouteLeg leg,
  ColorScheme scheme,
  AppLocalizations l10n,
) {
  final lineId = _lineIdFromRouteId(leg.routeId);
  if (_isTransitLeg(leg) && lineId.isNotEmpty) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        Text(
          _legLabel(leg.mode, l10n),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: scheme.onSurface,
          ),
        ),
        _RouteLineNumberPill(lineId: lineId, routeColor: _legColor(leg)),
      ],
    );
  }
  return Text(
    _legBadgeLabel(leg, l10n),
    style: TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 16,
      color: scheme.onSurface,
    ),
  );
}

class _RouteTimelineLegRow extends StatelessWidget {
  const _RouteTimelineLegRow({
    required this.leg,
    required this.isHighlighted,
    required this.timeFmt,
    required this.onTap,
  });

  final RouteLeg leg;
  final bool isHighlighted;
  final DateFormat timeFmt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final variant = scheme.onSurfaceVariant;
    final start = DateTime.fromMillisecondsSinceEpoch(leg.startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(leg.endTime);
    final meta =
        '${timeFmt.format(start)} – ${timeFmt.format(end)}   •   ${formatDistanceForDisplay(leg.distance)}';
    final cardRadius = BorderRadius.circular(12);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isHighlighted
              ? scheme.primaryContainer.withValues(alpha: 0.32)
              : scheme.surface,
          borderRadius: cardRadius,
          border: isHighlighted
              ? Border.all(
                  color: scheme.primary.withValues(alpha: 0.28),
                  width: 1,
                )
              : null,
          boxShadow: _itineraryStepCardShadow(scheme),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: cardRadius,
          child: InkWell(
            onTap: onTap,
            borderRadius: cardRadius,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '●',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      color: isHighlighted
                          ? scheme.primary
                          : (_isTransitLeg(leg)
                              ? _itineraryAccentColor(_legColor(leg))
                              : variant.withValues(alpha: 0.65)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _modeIconForMode(leg.mode, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _transitLineTitleRow(leg, scheme, l10n),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${leg.fromName} → ${leg.toName}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: variant.withValues(alpha: 0.88),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: variant.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Line number badge: solid [routeColor] matches map polyline for that leg.
class _RouteLineNumberPill extends StatelessWidget {
  const _RouteLineNumberPill({
    required this.lineId,
    required this.routeColor,
  });

  final String lineId;
  final Color routeColor;

  @override
  Widget build(BuildContext context) {
    final c = _itineraryAccentColor(routeColor);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(_kPillRadius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: _kPillPadding,
        child: Text(
          lineId,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: _kPillLineFontSize,
            letterSpacing: 0.2,
            color: _onRouteColorInk(c),
          ),
        ),
      ),
    );
  }
}

class _TransitStepChip extends StatelessWidget {
  const _TransitStepChip({required this.item});

  final _TransitSummaryItem item;

  @override
  Widget build(BuildContext context) {
    final variant = Theme.of(context).colorScheme.onSurfaceVariant;
    final c = item.routeColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.modeLabel,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: variant,
          ),
        ),
        if (item.lineId.isNotEmpty) ...[
          const SizedBox(width: 6),
          _RouteLineNumberPill(lineId: item.lineId, routeColor: c),
        ],
      ],
    );
  }
}
