import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../routes/domain/route_models.dart';

/// Request to open a line board on the Timetable (Bus) tab.
class OpenBusLineRequest {
  const OpenBusLineRequest({
    required this.line,
    this.stopId,
    this.directionId,
  });

  final BusLine line;
  final String? stopId;
  final String? directionId;
}

final pendingOpenBusLineProvider =
    StateProvider<OpenBusLineRequest?>((ref) => null);
