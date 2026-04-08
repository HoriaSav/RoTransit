import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final teTransportEnabledProvider =
    StateNotifierProvider<TeTransportController, bool>(
  (ref) => TeTransportController()..load(),
);

class TeTransportController extends StateNotifier<bool> {
  TeTransportController() : super(true);

  static const _key = 'te_transport_enabled';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}

