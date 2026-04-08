import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shell/shell_layout.dart';
import 'saved_trip_details_screen.dart';
import '../state/saved_providers.dart';

class FavoritesTab extends StatelessWidget {
  const FavoritesTab({super.key});

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
                title: Text(item.label),
                subtitle: Text('$minutes min • ${item.route.legs.length} legs'),
                trailing: const Icon(Icons.bookmark),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SavedTripDetailsScreen(journey: item),
                  ),
                ),
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
