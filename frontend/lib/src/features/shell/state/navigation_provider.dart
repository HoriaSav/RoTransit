import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../routes/domain/route_models.dart';

final selectedTabProvider = StateProvider<int>((ref) => 0);
final showMapSheetProvider = StateProvider<bool>((ref) => false);

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
    this.limit = 10,
    this.total = 0,
    this.lastRequest,
    this.selectedOption,
    this.mode = SheetMode.list,
  });

  final String cityId;
  final String cityName;
  final List<RouteOption> results;
  final int visibleCount;
  final int offset;
  final int limit;
  final int total;
  final RouteSearchRequest? lastRequest;
  final RouteOption? selectedOption;
  final SheetMode mode;

  SearchMapState copyWith({
    String? cityId,
    String? cityName,
    List<RouteOption>? results,
    int? visibleCount,
    int? offset,
    int? limit,
    int? total,
    RouteSearchRequest? lastRequest,
    RouteOption? selectedOption,
    SheetMode? mode,
  }) {
    return SearchMapState(
      cityId: cityId ?? this.cityId,
      cityName: cityName ?? this.cityName,
      results: results ?? this.results,
      visibleCount: visibleCount ?? this.visibleCount,
      offset: offset ?? this.offset,
      limit: limit ?? this.limit,
      total: total ?? this.total,
      lastRequest: lastRequest ?? this.lastRequest,
      selectedOption: selectedOption ?? this.selectedOption,
      mode: mode ?? this.mode,
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
    required RouteSearchRequest request,
  }) {
    state = SearchMapState(
      cityId: cityId,
      cityName: cityName,
      results: options,
      visibleCount: options.length,
      offset: offset,
      limit: limit,
      total: total,
      lastRequest: request,
      mode: SheetMode.list,
    );
  }

  void appendResults({
    required List<RouteOption> options,
    required int offset,
    required int limit,
    required int total,
  }) {
    state = state.copyWith(
      results: [...state.results, ...options],
      visibleCount: state.results.length + options.length,
      offset: offset,
      limit: limit,
      total: total,
      mode: SheetMode.list,
    );
  }

  bool get hasMore => state.results.length < state.total;

  void openDetails(RouteOption option) {
    state = state.copyWith(selectedOption: option, mode: SheetMode.details);
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
      lastRequest: state.lastRequest,
      selectedOption: null,
      mode: SheetMode.list,
    );
  }
}
