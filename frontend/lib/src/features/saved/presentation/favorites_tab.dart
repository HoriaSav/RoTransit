import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rotransit_frontend/l10n/app_localizations.dart';

import '../../../core/errors/app_user_message_l10n.dart';
import '../../../core/theme/accent_badge_style.dart';
import '../../../core/theme/app_extra_colors.dart';
import '../../routes/data/local_saved_routes_repository.dart';
import '../../routes/domain/route_models.dart';
import '../../shell/shell_layout.dart';
import '../../shell/state/navigation_provider.dart';
import '../state/saved_providers.dart';

({DateTime? departure, DateTime? arrival}) _journeyTimes(RouteOption route) {
  if (route.legs.isEmpty) return (departure: null, arrival: null);
  return (
    departure: DateTime.fromMillisecondsSinceEpoch(route.legs.first.startTime),
    arrival: DateTime.fromMillisecondsSinceEpoch(route.legs.last.endTime),
  );
}

class FavoritesTab extends StatelessWidget {
  const FavoritesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ColoredBox(
        color: context.extraColors.tabBackground,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: shellBottomContentPadding(context),
            ),
            child: const _JourneysList(),
          ),
        ),
      ),
    );
  }
}

class _FavoritesHeader extends StatelessWidget {
  const _FavoritesHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final badge = accentBadgeColors(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          Icon(
            Icons.favorite_rounded,
            size: 20,
            color: accentIconColor(context),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.favoritesSavedJourneys,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          if (count > 0)
            DecoratedBox(
              decoration: BoxDecoration(
                color: badge.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: badge.foreground,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FavoritesEmptyState extends StatelessWidget {
  const _FavoritesEmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final badge = accentBadgeColors(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: badge.background,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Icon(
                  Icons.bookmark_border_rounded,
                  size: 36,
                  color: badge.foreground,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l10n.favoritesEmptyTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.favoritesEmptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: scheme.onSurfaceVariant.withValues(
                  alpha: isDark ? 0.9 : 0.85,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    final l10n = AppLocalizations.of(context)!;
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
    final l10n = AppLocalizations.of(context)!;
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
    final l10n = AppLocalizations.of(context)!;
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
                    onTap: () {
                      ref
                          .read(searchMapStateProvider.notifier)
                          .openFavoriteJourney(item);
                      ref.read(showMapSheetProvider.notifier).state = true;
                      ref.read(routeMapOverlaySuppressedProvider.notifier).state =
                          false;
                    },
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
