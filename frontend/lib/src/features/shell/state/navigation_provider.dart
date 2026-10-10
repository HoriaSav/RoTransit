import 'package:flutter_riverpod/flutter_riverpod.dart';

final selectedTabProvider = StateProvider<int>((ref) => 0);

/// When true, Settings is shown as a full-screen layer (navbar hidden).
final settingsOpenProvider = StateProvider<bool>((ref) => false);

/// Current city context (id + display name) shared by Timetable and Settings.
class SearchMapState {
  const SearchMapState({
    this.cityId = '',
    this.cityName = 'RoTransit',
  });

  final String cityId;
  final String cityName;

  SearchMapState copyWith({
    String? cityId,
    String? cityName,
  }) {
    return SearchMapState(
      cityId: cityId ?? this.cityId,
      cityName: cityName ?? this.cityName,
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
}
