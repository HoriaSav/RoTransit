import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotransit/l10n/app_localizations.dart';

import '../../../core/theme/app_extra_colors.dart';
import '../../shell/shell_layout.dart';
import '../../shell/state/navigation_provider.dart';
import '../../favorites/data/favorite_stops_repository.dart';
import '../../map/presentation/stop_board_sheet.dart';
import '../../shell/state/bus_line_open_provider.dart';

/// Favorite stops (starred on the stop board) and favorite lines (Timetable).
class FavoritesTab extends ConsumerWidget {
  const FavoritesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final stops = ref.watch(favoriteStopsProvider);
    final lines = ref.watch(favoriteLinesProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ColoredBox(
        color: context.extraColors.tabBackground,
        child: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            padding: EdgeInsets.only(
              bottom: shellBottomContentPadding(context),
            ),
            children: [
              _PinnedSection(
                title: l10n.favoritesStopsTitle,
                child: stops.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return _SectionHint(text: l10n.favoritesStopsEmpty);
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
                  error: (_, __) =>
                      _SectionHint(text: l10n.favoritesCouldNotLoad),
                ),
              ),
              _PinnedSection(
                title: l10n.favoritesLinesTitle,
                child: lines.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return _SectionHint(text: l10n.favoritesLinesEmpty);
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
                  error: (_, __) =>
                      _SectionHint(text: l10n.favoritesCouldNotLoad),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHint extends StatelessWidget {
  const _SectionHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          height: 1.4,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
