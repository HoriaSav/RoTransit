import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../routes/data/local_saved_routes_repository.dart';
import '../../saved/state/saved_providers.dart';
import '../data/recent_searches_repository.dart';

final recentSearchesProvider = FutureProvider<List<RecentSearchEntry>>((ref) {
  return ref.read(recentSearchesRepositoryProvider).listRecentSearches(limit: 3);
});

final favoriteJourneyPreviewProvider = Provider<List<SavedJourneyVm>>((ref) {
  final saved = ref.watch(savedJourneysProvider);
  return saved.maybeWhen(
    data: (items) => items.take(2).toList(),
    orElse: () => const [],
  );
});
