import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

// Drives the REAL location code (UserLocationNotifier, tryGetCurrentUserLatLon,
// GeolocatorPositionSource) against a fake Geolocator platform channel, so
// permission prompts and stream settings are checked end to end.
const _methods = MethodChannel('flutter.baseflow.com/geolocator');
const _updates = EventChannel('flutter.baseflow.com/geolocator_updates');

// LocationPermission indexes on the wire.
const _denied = 0;
const _whileInUse = 2;

Map<String, dynamic> fakePosition(double lat, double lon) => {
      'latitude': lat,
      'longitude': lon,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'accuracy': 8.0,
      'altitude': 600.0,
      'altitude_accuracy': 3.0,
      'heading': 0.0,
      'heading_accuracy': 1.0,
      'speed': 0.0,
      'speed_accuracy': 0.5,
      'is_mocked': false,
    };

class FakeGeolocator {
  FakeGeolocator({required this.grantOnRequest});

  final bool grantOnRequest;
  int permission = _denied;

  /// When set, getCurrentPosition waits for it (a slow first fix).
  Completer<void>? holdPosition;

  /// isLocationServiceEnabled answer (device location switch).
  bool serviceEnabled = true;
  final calls = <String>[];
  final listenArgs = <Object?>[];
  int cancels = 0;
  MockStreamHandlerEventSink? sink;

  void install(WidgetTester tester) {
    final m = tester.binding.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_methods, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'isLocationServiceEnabled':
          return serviceEnabled;
        case 'checkPermission':
          return permission;
        case 'requestPermission':
          if (grantOnRequest) permission = _whileInUse;
          return permission;
        case 'getLastKnownPosition':
          return null;
        case 'getCurrentPosition':
          final hold = holdPosition;
          if (hold != null) await hold.future;
          return fakePosition(45.6427, 25.5887);
      }
      return null;
    });
    m.setMockStreamHandler(
      _updates,
      MockStreamHandler.inline(
        onListen: (args, events) {
          listenArgs.add(args);
          sink = events;
        },
        onCancel: (_) {
          cancels++;
          sink = null;
        },
      ),
    );
    addTearDown(() {
      m.setMockMethodCallHandler(_methods, null);
      m.setMockStreamHandler(_updates, null);
    });
  }
}

Future<void> settleLocation(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

LatLng? userDot(WidgetTester tester) {
  for (final layer
      in tester.widgetList<MarkerLayer>(find.byType(MarkerLayer))) {
    for (final m in layer.markers) {
      if (m.width == 18 && m.height == 18) return m.point;
    }
  }
  return null;
}
