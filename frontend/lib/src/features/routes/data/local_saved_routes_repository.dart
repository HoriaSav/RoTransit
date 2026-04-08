import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../local/local_db.dart';
import '../domain/route_models.dart';

final localSavedRoutesRepositoryProvider = Provider<LocalSavedRoutesRepository>(
  (ref) => LocalSavedRoutesRepository(),
);

class LocalSavedRoutesRepository {
  Future<void> save({
    required String deviceUserId,
    required String cityId,
    required String routeMetadata,
    required String label,
  }) async {
    final db = await LocalDb.instance();
    await db.insert('saved_routes', {
      'device_user_id': deviceUserId,
      'city_id': cityId,
      'label': label,
      'route_metadata': routeMetadata,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<SavedJourneyVm>> getJourneys(String deviceUserId) async {
    final db = await LocalDb.instance();
    final rows = await db.query(
      'saved_routes',
      where: 'device_user_id = ?',
      whereArgs: [deviceUserId],
      orderBy: 'id DESC',
    );
    return rows.map((row) {
      final metadata = row['route_metadata'] as String;
      final route = decodeRouteMetadata(metadata);
      return SavedJourneyVm(
        id: (row['id'] as int).toString(),
        label: (row['label'] as String?) ?? 'Saved journey',
        route: route,
        createdAt: DateTime.parse(row['created_at'] as String),
        cityId: row['city_id'] as String,
      );
    }).toList();
  }

  Future<void> enqueueSaveSync(Map<String, dynamic> payload) async {
    final db = await LocalDb.instance();
    await db.insert('sync_queue', {
      'type': 'SAVE_ROUTE',
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> pendingSyncSaves() async {
    final db = await LocalDb.instance();
    return db.query('sync_queue', where: 'type = ?', whereArgs: ['SAVE_ROUTE']);
  }

  Future<void> removeSyncItem(int id) async {
    final db = await LocalDb.instance();
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }
}

class SavedJourneyVm {
  const SavedJourneyVm({
    required this.id,
    required this.label,
    required this.route,
    required this.createdAt,
    required this.cityId,
    this.remoteRouteId,
    this.deviceUserId,
  });

  final String id;
  final String label;
  final RouteOption route;
  final DateTime createdAt;
  final String cityId;
  final String? remoteRouteId;
  final String? deviceUserId;
}
