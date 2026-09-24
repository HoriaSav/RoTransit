import '../../routes/domain/route_models.dart';
import '../../shell/state/navigation_provider.dart';

String latLonPoint(double lat, double lon) =>
    '${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)}';

String coordinateStopId({
  required String kind,
  required double lat,
  required double lon,
}) =>
    '$kind:${latLonPoint(lat, lon)}';

bool isCoordinatePickedStop(StopSearchItem stop) {
  return stop.stopId.startsWith('map:') || stop.stopId.startsWith('gps:');
}

RouteSearchRequest buildRouteSearchRequest({
  required String cityId,
  required String origin,
  required String destination,
  required DateTime serviceDateTime,
  int offset = 0,
  int limit = kRouteSearchPageSize,
  bool includeGeometry = false,
}) {
  return RouteSearchRequest(
    cityId: cityId,
    origin: origin,
    destination: destination,
    serviceDate: serviceDateTime,
    serviceTime: serviceDateTime,
    offset: offset,
    limit: limit,
    includeGeometry: includeGeometry,
  );
}
