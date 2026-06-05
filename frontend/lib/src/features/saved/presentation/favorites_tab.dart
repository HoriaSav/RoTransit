import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_extra_colors.dart';
import '../../routes/domain/route_models.dart';
import '../../shell/shell_layout.dart';
import '../../shell/state/navigation_provider.dart';
import '../state/saved_providers.dart';

String _favoritesTransferLabel(int transfers) {
  if (transfers == 0) return 'No transfers';
  return '$transfers transfer${transfers == 1 ? '' : 's'}';
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
            child: const DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  SizedBox(height: 8),
                  TabBar(
                    tabs: [
                      Tab(text: 'Journeys'),
                      Tab(text: 'Stations'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _JourneysList(),
                        _StationsPlaceholder(),
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

class _JourneysList extends ConsumerWidget {
  const _JourneysList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journeys = ref.watch(savedJourneysProvider);
    return journeys.when(
      data: (items) {
        if (items.isEmpty) {
          return const Center(child: Text('No saved journeys yet.'));
        }
            return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final minutes = (item.route.durationSeconds / 60).round();
            return Card(
              child: ListTile(
                title: Text(routeJourneyTitle(item.route)),
                subtitle: Text(
                  '$minutes min • ${_favoritesTransferLabel(item.route.transfers)}',
                ),
                trailing: const Icon(Icons.bookmark),
                onTap: () {
                  ref.read(searchMapStateProvider.notifier).openFavoriteJourney(item);
                  ref.read(showMapSheetProvider.notifier).state = true;
                  ref.read(routeMapOverlaySuppressedProvider.notifier).state =
                      false;
                },
                onLongPress: () async {
                  final box = context.findRenderObject() as RenderBox?;
                  final overlayBox =
                      Overlay.of(context).context.findRenderObject() as RenderBox?;
                  if (box == null || overlayBox == null) return;
                  final selected = await showMenu<String>(
                    context: context,
                    position: RelativeRect.fromRect(
                      Rect.fromPoints(
                        box.localToGlobal(Offset.zero),
                        box.localToGlobal(box.size.bottomRight(Offset.zero)),
                      ),
                      Offset.zero & overlayBox.size,
                    ),
                    items: const [
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete trip'),
                      ),
                    ],
                  );
                  if (!context.mounted || selected != 'delete') return;
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete trip?'),
                      content: const Text('Delete this trip?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    await ref
                        .read(deleteSavedJourneyControllerProvider)
                        .deleteJourney(item);
                  }
                },
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) =>
          const Center(child: Text('Could not load saved journeys')),
    );
  }
}

class _StationsPlaceholder extends StatelessWidget {
  const _StationsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Stations section coming soon.'));
  }
}
