import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../routes/data/local_saved_routes_repository.dart';
import '../../routes/domain/route_models.dart';

/// Page size for route search (initial fetch and each load-more on the map sheet).
const kRouteSearchPageSize = 5;

final selectedTabProvider = StateProvider<int>((ref) => 0);
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
    state = SearchMapState(
      cityId: state.cityId,
      cityName: state.cityName,
      results: state.results,
      visibleCount: state.visibleCount,
      offset: state.offset,
      limit: state.limit,
      total: state.total,
      hasMore: state.hasMore,
      lastRequest: state.lastRequest,
      selectedOption: null,
      mode: SheetMode.list,
      openedFromSavedFavorite: false,
      pendingDetailsExtent: null,
    );
  }

  /// Opens itinerary details on the map from a locally stored favorite (offline-capable).
  void openFavoriteJourney(SavedJourneyVm journey) {
    final legs = journey.route.legs;
    if (legs.isEmpty) return;
    final first = legs.first;
    final last = legs.last;
    final now = DateTime.now();
    final synthetic = RouteSearchRequest(
      cityId: journey.cityId,
      origin: '${first.fromLat},${first.fromLon}',
      destination: '${last.toLat},${last.toLon}',
      serviceDate: DateTime(now.year, now.month, now.day),
      serviceTime: now,
    );
    final name = state.cityId == journey.cityId && state.cityName.isNotEmpty
        ? state.cityName
        : 'Saved trip';
    state = SearchMapState(
      cityId: journey.cityId,
      cityName: name,
      results: const [],
      visibleCount: 0,
      offset: 0,
      limit: kRouteSearchPageSize,
      total: 0,
      lastRequest: synthetic,
      selectedOption: journey.route,
      mode: SheetMode.details,
      openedFromSavedFavorite: true,
      pendingDetailsExtent: 0.5,
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
