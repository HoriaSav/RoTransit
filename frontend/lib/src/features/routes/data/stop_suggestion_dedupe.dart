import 'dart:math' as math;

import '../../../core/format/search_text_normalizer.dart';
import '../domain/route_models.dart';

int _minOf(List<int> idxs) => idxs.reduce((a, b) => a < b ? a : b);

const double _mergeRadiusMeters = 120;
const double _earthRadiusM = 6371000;

String _normalizeStopName(String name) {
  return normalizeSearchText(name);
}

/// Haversine distance in meters (shared for offline pack ranking).
double stopSuggestionDistanceMeters(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  return _distanceMeters(lat1, lon1, lat2, lon2);
}

double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dPhi = (lat2 - lat1) * math.pi / 180;
  final dLambda = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
      math.cos(phi1) *
          math.cos(phi2) *
          math.sin(dLambda / 2) *
          math.sin(dLambda / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(math.max(0, 1 - a)));
  return _earthRadiusM * c;
}

int _find(List<int> parent, int i) {
  if (parent[i] != i) {
    parent[i] = _find(parent, parent[i]);
  }
  return parent[i];
}

void _union(List<int> parent, int a, int b) {
  final ra = _find(parent, a);
  final rb = _find(parent, b);
  if (ra != rb) {
    parent[rb] = ra;
  }
}

List<StopSearchItem> dedupeStopSearchItems(
  List<StopSearchItem> ordered,
  int maxResults, {
  double? refLat,
  double? refLon,
}) {
  if (ordered.isEmpty || maxResults <= 0) return const [];
  final n = ordered.length;
  final parent = List<int>.generate(n, (i) => i);
  for (var i = 0; i < n; i++) {
    final na = _normalizeStopName(ordered[i].name);
    if (na.isEmpty) continue;
    for (var j = i + 1; j < n; j++) {
      if (na != _normalizeStopName(ordered[j].name)) continue;
      final a = ordered[i];
      final b = ordered[j];
      if (_distanceMeters(a.lat, a.lon, b.lat, b.lon) <= _mergeRadiusMeters) {
        _union(parent, i, j);
      }
    }
  }
  final byRoot = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    final r = _find(parent, i);
    byRoot.putIfAbsent(r, () => []).add(i);
  }
  final clusters = byRoot.values.toList()
    ..sort((a, b) => _minOf(a).compareTo(_minOf(b)));
  final out = <StopSearchItem>[];
  for (final idxs in clusters) {
    out.add(_pickSearchRepresentative(ordered, idxs, refLat, refLon));
    if (out.length >= maxResults) break;
  }
  return out;
}

StopSearchItem _pickSearchRepresentative(
  List<StopSearchItem> ordered,
  List<int> idxs,
  double? refLat,
  double? refLon,
) {
  if (refLat != null && refLon != null) {
    var best = idxs.first;
    var bestD = _distanceMeters(
        refLat, refLon, ordered[best].lat, ordered[best].lon);
    for (var k = 1; k < idxs.length; k++) {
      final i = idxs[k];
      final d =
          _distanceMeters(refLat, refLon, ordered[i].lat, ordered[i].lon);
      if (d < bestD - 1e-6) {
        best = i;
        bestD = d;
      } else if ((d - bestD).abs() <= 1e-6 && i < best) {
        best = i;
      }
    }
    return ordered[best];
  }
  return ordered[_minOf(idxs)];
}

List<NearbyStopItem> dedupeNearbyStopItems(
  List<NearbyStopItem> ordered,
  int maxResults, {
  required double refLat,
  required double refLon,
}) {
  if (ordered.isEmpty || maxResults <= 0) return const [];
  final n = ordered.length;
  final parent = List<int>.generate(n, (i) => i);
  for (var i = 0; i < n; i++) {
    final na = _normalizeStopName(ordered[i].name);
    if (na.isEmpty) continue;
    for (var j = i + 1; j < n; j++) {
      if (na != _normalizeStopName(ordered[j].name)) continue;
      final a = ordered[i];
      final b = ordered[j];
      if (_distanceMeters(a.lat, a.lon, b.lat, b.lon) <= _mergeRadiusMeters) {
        _union(parent, i, j);
      }
    }
  }
  final byRoot = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    final r = _find(parent, i);
    byRoot.putIfAbsent(r, () => []).add(i);
  }
  final clusters = byRoot.values.toList()
    ..sort((a, b) => _minOf(a).compareTo(_minOf(b)));
  final out = <NearbyStopItem>[];
  for (final idxs in clusters) {
    out.add(_pickNearbyRepresentative(ordered, idxs, refLat, refLon));
    if (out.length >= maxResults) break;
  }
  return out;
}

NearbyStopItem _pickNearbyRepresentative(
  List<NearbyStopItem> ordered,
  List<int> idxs,
  double refLat,
  double refLon,
) {
  var best = idxs.first;
  var bestD =
      _distanceMeters(refLat, refLon, ordered[best].lat, ordered[best].lon);
  for (var k = 1; k < idxs.length; k++) {
    final i = idxs[k];
    final d = _distanceMeters(refLat, refLon, ordered[i].lat, ordered[i].lon);
    if (d < bestD - 1e-6) {
      best = i;
      bestD = d;
    } else if ((d - bestD).abs() <= 1e-6 && i < best) {
      best = i;
    }
  }
  return ordered[best];
}
