import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branding/operator_branding.dart';
import '../../routes/data/local_saved_routes_repository.dart';
import '../../routes/domain/route_models.dart';

/// Page size for route search (initial fetch and each load-more on the map sheet).
const kRouteSearchPageSize = 5;

final selectedTabProvider = StateProvider<int>((ref) => 0);

/// When true, Settings is shown as a full-screen layer (navbar hidden).
final settingsOpenProvider = StateProvider<bool>((ref) => false);


final showMapSheetProvider = StateProvider<bool>((ref) => false);

/// Incremented when the route sheet should expand to full height (system back / UI back).
final routeSheetExpandFullProvider = StateProvider<int>((ref) => 0);

/// When true, route polylines, stops, origin/destination pins are hidden on the map.
/// Set when leaving Search via the nav bar; cleared on a new search or opening details.
final routeMapOverlaySuppressedProvider = StateProvider<bool>((ref) => false);

enum SheetMode { list, details }

enum LocationSelectionTarget { from, to }

class MapPickedLocation {
  const MapPickedLocation({
    required this.target,
    required this.value,
  });

  final LocationSelectionTarget target;
  final String value;
}

final mapSelectionTargetProvider =
    StateProvider<LocationSelectionTarget?>((ref) => null);

/// Full-screen map overlay: route results sheet and/or picking a location on the map.
final mapShellOverlayVisibleProvider = Provider<bool>((ref) {
  final sheet = ref.watch(showMapSheetProvider);
  final picking = ref.watch(mapSelectionTargetProvider) != null;
  return sheet || picking;
});

final mapPickedLocationProvider = StateProvider<MapPickedLocation?>(
  (ref) => null,
);

class SearchMapState {
  const SearchMapState({
    this.cityId = '',
    this.cityName = 'RoTransit',
    this.results = const [],
    this.visibleCount = 0,
    this.offset = 0,
    this.limit = kRouteSearchPageSize,
    this.total = 0,
    this.hasMore = false,
    this.lastRequest,
    this.selectedOption,
    this.mode = SheetMode.list,
    this.openedFromSavedFavorite = false,
    this.pendingDetailsExtent,
    this.originLabel = '',
    this.destinationLabel = '',
  });

  final String cityId;
  final String cityName;
  final List<RouteOption> results;
  final int visibleCount;
  final int offset;
  final int limit;
  final int total;
  final bool hasMore;
  final RouteSearchRequest? lastRequest;
  final RouteOption? selectedOption;
  final SheetMode mode;
  final bool openedFromSavedFavorite;
  final double? pendingDetailsExtent;
  final String originLabel;
  final String destinationLabel;

  SearchMapState copyWith({
    String? cityId,
    String? cityName,
    List<RouteOption>? results,
    int? visibleCount,
    int? offset,
    int? limit,
    int? total,
    bool? hasMore,
    RouteSearchRequest? lastRequest,
    RouteOption? selectedOption,
    SheetMode? mode,
    bool? openedFromSavedFavorite,
    double? pendingDetailsExtent,
    bool clearPendingDetailsExtent = false,
    String? originLabel,
    String? destinationLabel,
  }) {
    return SearchMapState(
      cityId: cityId ?? this.cityId,
      cityName: cityName ?? this.cityName,
      results: results ?? this.results,
      visibleCount: visibleCount ?? this.visibleCount,
      offset: offset ?? this.offset,
      limit: limit ?? this.limit,
      total: total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
      lastRequest: lastRequest ?? this.lastRequest,
      selectedOption: selectedOption ?? this.selectedOption,
      mode: mode ?? this.mode,
      openedFromSavedFavorite:
          openedFromSavedFavorite ?? this.openedFromSavedFavorite,
      pendingDetailsExtent: clearPendingDetailsExtent
          ? null
          : (pendingDetailsExtent ?? this.pendingDetailsExtent),
      originLabel: originLabel ?? this.originLabel,
      destinationLabel: destinationLabel ?? this.destinationLabel,
    );
  }
}

final searchMapStateProvider =
    StateNotifierProvider<SearchMapController, SearchMapState>(
  (ref) => SearchMapController(),
);

class SearchMapController extends StateNotifier<SearchMapState> {
  SearchMapController() : super(const SearchMapState());

  void setCityContext({
    required String cityId,
    required String cityName,
  }) {
    state = state.copyWith(
      cityId: cityId,
      cityName: cityName,
    );
  }

  void setResults({
    required String cityId,
    required String cityName,
    required List<RouteOption> options,
    required int offset,
    required int limit,
    required int total,
    required bool hasMore,
    required RouteSearchRequest request,
  }) {
    state = SearchMapState(
      cityId: cityId,
      cityName: cityName,
      results: options,
      visibleCount: math.min(kRouteSearchPageSize, options.length),
      offset: offset,
      limit: limit,
      total: total,
      hasMore: hasMore,
      lastRequest: request,
      mode: SheetMode.list,
      openedFromSavedFavorite: false,
      pendingDetailsExtent: null,
      originLabel: '',
      destinationLabel: '',
    );
  }

  void setJourneyLabels({
    required String originLabel,
    required String destinationLabel,
  }) {
    state = state.copyWith(
      originLabel: originLabel,
      destinationLabel: destinationLabel,
    );
  }

  void revealMoreResults() {
    final next = math.min(
      state.visibleCount + kRouteSearchPageSize,
      state.results.length,
    );
    if (next == state.visibleCount) return;
    state = state.copyWith(visibleCount: next);
  }

  void appendResults({
    required List<RouteOption> options,
    required int offset,
    required int limit,
    required int total,
    required bool hasMore,
  }) {
    final mergedLength = state.results.length + options.length;
    state = state.copyWith(
      results: [...state.results, ...options],
      visibleCount: math.min(
        state.visibleCount + kRouteSearchPageSize,
        mergedLength,
      ),
      offset: offset,
      limit: limit,
      total: total,
      hasMore: hasMore,
      mode: SheetMode.list,
      openedFromSavedFavorite: false,
      clearPendingDetailsExtent: true,
    );
  }

  bool get canLoadMore =>
      state.hasMore || state.visibleCount < state.results.length;

  void openDetails(RouteOption option) {
    state = state.copyWith(selectedOption: option, mode: SheetMode.details);
  }

  void replaceResultAt(int index, RouteOption option) {
    if (index < 0 || index >= state.results.length) return;
    final next = [...state.results];
    next[index] = option;
    state = state.copyWith(results: next);
  }

  void backToList() {
    state = state.copyWith(mode: SheetMode.list);
  }

  /// Leave trip details so reopening the route sheet shows the list, not details.
  void clearRouteSheetSelection() {
    state = state.copyWith(
      selectedOption: null,
      mode: SheetMode.list,
      openedFromSavedFavorite: false,
      clearPendingDetailsExtent: true,
    );
  }

  /// Opens itinerary details on the map from a locally stored favorite (offline-capable).
  void openFavoriteJourney(SavedJourneyVm journey) {
    final legs = journey.route.legs;
    if (legs.isEmpty) return;
    final first = legs.first;
    final last = legs.last;
    final now = DateTime.now();
    final cityId = resolvedCityId(journey.cityId);
    final names = journeyEndpointNames(journey.route);
    final cityName = !isUnresolvedCityId(state.cityId) &&
            state.cityId == cityId &&
            state.cityName.isNotEmpty
        ? state.cityName
        : kBrasovCityName;
    final synthetic = RouteSearchRequest(
      cityId: cityId,
      origin: '${first.fromLat},${first.fromLon}',
      destination: '${last.toLat},${last.toLon}',
      serviceDate: DateTime(now.year, now.month, now.day),
      serviceTime: now,
    );
    state = SearchMapState(
      cityId: cityId,
      cityName: cityName,
      results: [journey.route],
      visibleCount: 1,
      offset: 0,
      limit: kRouteSearchPageSize,
      total: 1,
      lastRequest: synthetic,
      selectedOption: journey.route,
      mode: SheetMode.details,
      openedFromSavedFavorite: true,
      pendingDetailsExtent: 0.5,
      originLabel: names.from,
      destinationLabel: names.to,
    );
  }

  void clearPendingDetailsExtent() {
    state = state.copyWith(clearPendingDetailsExtent: true);
  }

  void closeFavoriteMapPreview() {
    state = SearchMapState(
      cityId: state.cityId,
      cityName: state.cityName,
      results: state.results,
      visibleCount: state.visibleCount,
      offset: state.offset,
      limit: state.limit,
      total: state.total,
      hasMore: state.hasMore,
      lastRequest: null,
      selectedOption: null,
      mode: SheetMode.list,
      openedFromSavedFavorite: false,
      pendingDetailsExtent: null,
    );
  }
}

/// Search tab + map sheet for a saved journey. Does not go through nav-bar
/// handlers, which would close the sheet when leaving Favorites.
void openSavedJourneyOnMap(WidgetRef ref, SavedJourneyVm journey) {
  ref.read(searchMapStateProvider.notifier).openFavoriteJourney(journey);
  if (!ref.read(searchMapStateProvider).openedFromSavedFavorite) return;
  ref.read(routeMapOverlaySuppressedProvider.notifier).state = false;
  ref.read(showMapSheetProvider.notifier).state = true;
  ref.read(selectedTabProvider.notifier).state = 0;
}
