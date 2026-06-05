import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../local/local_db.dart';
import '../../routes/domain/route_models.dart';

final recentSearchesRepositoryProvider = Provider<RecentSearchesRepository>(
  (ref) => RecentSearchesRepository(),
);

const double _kRecentJourneyCoordEpsilon = 1e-5;

bool _sameJourneyEndpoints(
  StopSearchItem from,
  StopSearchItem to,
  Map<String, Object?> row,
) {
  bool near(double a, double b) => (a - b).abs() < _kRecentJourneyCoordEpsilon;
  return near(
        from.lat,
        (row['from_lat']! as num).toDouble(),
      ) &&
      near(
        from.lon,
        (row['from_lon']! as num).toDouble(),
      ) &&
      near(
        to.lat,
        (row['to_lat']! as num).toDouble(),
      ) &&
      near(
        to.lon,
        (row['to_lon']! as num).toDouble(),
      );
}

class RecentSearchEntry {
  const RecentSearchEntry({
    required this.id,
    required this.cityId,
    required this.cityName,
    required this.fromStop,
    required this.toStop,
    required this.serviceDate,
    required this.serviceTimeLabel,
    required this.createdAt,
  });

  final int id;
  final String cityId;
  final String cityName;
  final StopSearchItem fromStop;
  final StopSearchItem toStop;
  final DateTime serviceDate;
  final String serviceTimeLabel;
  final DateTime createdAt;
}

class RecentSearchesRepository {
  Future<void> addRecentSearch({
    required String cityId,
    required String cityName,
    required StopSearchItem fromStop,
    required StopSearchItem toStop,
    required DateTime serviceDate,
    required String serviceTimeLabel,
  }) async {
    final db = await LocalDb.instance();
    final sameCityRows = await db.query(
      'recent_searches',
      where: 'city_id = ?',
      whereArgs: [cityId],
    );
    for (final row in sameCityRows) {
      if (_sameJourneyEndpoints(fromStop, toStop, row)) {
        await db.delete(
          'recent_searches',
          where: 'id = ?',
          whereArgs: [row['id'] as int],
        );
      }
    }
    await db.insert('recent_searches', {
      'city_id': cityId,
      'city_name': cityName,
      'from_name': fromStop.name,
      'from_lat': fromStop.lat,
      'from_lon': fromStop.lon,
      'to_name': toStop.name,
      'to_lat': toStop.lat,
      'to_lon': toStop.lon,
      'service_date_iso': serviceDate.toIso8601String(),
      'service_time_hhmm': serviceTimeLabel,
      'created_at': DateTime.now().toIso8601String(),
    });

    final rows = await db.query(
      'recent_searches',
      columns: ['id'],
      orderBy: 'id DESC',
    );
    if (rows.length > 3) {
      final staleIds = rows.skip(3).map((row) => row['id'] as int).toList();
      final placeholders = List.filled(staleIds.length, '?').join(', ');
      await db.delete(
        'recent_searches',
        where: 'id IN ($placeholders)',
        whereArgs: staleIds,
      );
    }
  }

  Future<List<RecentSearchEntry>> listRecentSearches({int limit = 3}) async {
    final db = await LocalDb.instance();
    final rows = await db.query(
      'recent_searches',
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map((row) {
      return RecentSearchEntry(
        id: row['id'] as int,
        cityId: row['city_id'] as String,
        cityName: row['city_name'] as String,
        fromStop: StopSearchItem(
          stopId: 'recent-from:${row['id']}',
          name: row['from_name'] as String,
          lat: (row['from_lat'] as num).toDouble(),
          lon: (row['from_lon'] as num).toDouble(),
        ),
        toStop: StopSearchItem(
          stopId: 'recent-to:${row['id']}',
          name: row['to_name'] as String,
          lat: (row['to_lat'] as num).toDouble(),
          lon: (row['to_lon'] as num).toDouble(),
        ),
        serviceDate: DateTime.parse(row['service_date_iso'] as String),
        serviceTimeLabel: row['service_time_hhmm'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }).toList();
  }
}
