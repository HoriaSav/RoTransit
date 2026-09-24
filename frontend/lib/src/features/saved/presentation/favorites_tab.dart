import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rotransit/l10n/app_localizations.dart';

import '../../../core/errors/app_user_message_l10n.dart';
import '../../../core/theme/accent_badge_style.dart';
import '../../../core/theme/app_extra_colors.dart';
import '../../routes/data/local_saved_routes_repository.dart';
import '../../routes/domain/route_models.dart';
import '../../shell/shell_layout.dart';
import '../../shell/state/navigation_provider.dart';
import '../state/saved_providers.dart';
import '../../favorites/data/favorite_stops_repository.dart';
import '../../map/presentation/stop_board_sheet.dart';
import '../../shell/state/bus_line_open_provider.dart';

part 'favorites_cards.dart';

({DateTime? departure, DateTime? arrival}) _journeyTimes(RouteOption route) {
  if (route.legs.isEmpty) return (departure: null, arrival: null);
  return (
    departure: DateTime.fromMillisecondsSinceEpoch(route.legs.first.startTime),
    arrival: DateTime.fromMillisecondsSinceEpoch(route.legs.last.endTime),
  );
}

class FavoritesTab extends ConsumerWidget {
  const FavoritesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stops = ref.watch(favoriteStopsProvider);
    final lines = ref.watch(favoriteLinesProvider);
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PinnedSection(
                  title: 'Favorite stops',
                  child: stops.when(
                    data: (items) {
                      if (items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text('Star a stop from the map board.'),
                        );
                      }
                      return Column(
                        children: [
                          for (final s in items)
                            ListTile(
                              leading: const Icon(Icons.place_outlined),
                              title: Text(s.name),
                              onTap: () => showStopBoardSheet(context, stop: s),
                            ),
                        ],
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ),
                _PinnedSection(
                  title: 'Favorite lines',
                  child: lines.when(
                    data: (items) {
                      if (items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text('Favorite a line from a stop board row.'),
                        );
                      }
                      return Column(
                        children: [
                          for (final line in items)
                            ListTile(
                              leading: const Icon(Icons.directions_bus_outlined),
                              title: Text(line.shortName),
                              subtitle: Text(line.longName),
                              onTap: () {
                                ref.read(pendingOpenBusLineProvider.notifier).state =
                                    OpenBusLineRequest(line: line);
                                ref.read(selectedTabProvider.notifier).state = 1;
                              },
                            ),
                        ],
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ),
                const Expanded(child: _JourneysList()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PinnedSection extends StatelessWidget {
  const _PinnedSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _FavoritesHeader extends StatelessWidget {
  const _FavoritesHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
    final l10n = AppLocalizations.of(context);
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

