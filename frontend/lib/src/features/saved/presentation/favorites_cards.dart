part of 'favorites_tab.dart';

class _FavoriteJourneyCard extends StatelessWidget {
  const _FavoriteJourneyCard({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  final SavedJourneyVm item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final extra = context.extraColors;
    final isDark = scheme.brightness == Brightness.dark;
    final route = item.route;
    final title = savedJourneyTitle(label: item.label, route: route);
    final minutes = (route.durationSeconds / 60).round();
    final transfers = l10n.favoritesTransferLabel(item.route.transfers);
    final times = _journeyTimes(route);
    final timeFmt = DateFormat('h:mm a');
    final dayFmt = DateFormat('EEEE');
    final hasTimes = times.departure != null && times.arrival != null;
    final dayLabel = hasTimes ? dayFmt.format(times.departure!) : null;
    final timeRange = hasTimes
        ? '${timeFmt.format(times.departure!)} – ${timeFmt.format(times.arrival!)}'
        : null;

    return Material(
      color: extra.recentTileBackground,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: extra.recentTileBorder),
            boxShadow: isDark
                ? null
                : const [
                    BoxShadow(
                      color: Color(0x0A0A3E96),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (dayLabel != null && timeRange != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dayLabel,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: accentIconColor(context),
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            timeRange,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              height: 1.15,
                              color: scheme.onSurface,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: extra.durationBadgeBackground,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        child: Text(
                          '$minutes min',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: extra.durationBadgeBackground,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        child: Text(
                          '$minutes min',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              if (dayLabel != null && timeRange != null) ...[
                const SizedBox(height: 10),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    height: 1.25,
                    color: scheme.onSurface,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    route.transfers == 0
                        ? Icons.directions_bus_outlined
                        : Icons.swap_horiz_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    transfers,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.bookmark_rounded,
                    size: 18,
                    color: accentIconColor(context),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: mutedChromeColor(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JourneysList extends ConsumerWidget {
  const _JourneysList();

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    SavedJourneyVm item,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.favoritesDeleteTitle),
        content: Text(l10n.favoritesDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(deleteSavedJourneyControllerProvider).deleteJourney(item);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final journeys = ref.watch(savedJourneysProvider);
    return journeys.when(
      data: (items) {
        if (items.isEmpty) {
          return const Column(
            children: [
              _FavoritesHeader(count: 0),
              Expanded(child: _FavoritesEmptyState()),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FavoritesHeader(count: items.length),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _FavoriteJourneyCard(
                    item: item,
                    onTap: () => openSavedJourneyOnMap(ref, item),
                    onDelete: () => _confirmDelete(context, ref, item),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Text(l10n.favoritesCouldNotLoad),
      ),
    );
  }
}
