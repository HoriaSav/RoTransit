import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:latlong2/latlong.dart' hide Path;

import '../../../core/location/user_location_helpers.dart';
import '../../routes/data/route_api_repository.dart';
import '../../routes/domain/route_models.dart';
import '../../routes/state/save_route_controller.dart';
import '../../shell/shell_layout.dart';
import '../../shell/state/navigation_provider.dart';

/// Graph stop dots (50% of former 20px bus marker).
const double _kGraphStopDotSize = 10;

/// Origin (“from”) marker — previous graph marker size.
const double _kOriginDotSize = 20;

/// User GPS dot (50% of former 36px).
const double _kUserLocationDotSize = 18;

/// Landmark: square marker + [Alignment.center] like graph stop dots (avoids bottomCenter/rotate drift when zooming).
const double _kLandmarkMarkerSize = 32;
const double _kLandmarkIconSize = 28;

const Map<String, Color> _kLineColorOverrides = {};

const List<Color> _kTransitFallbackPalette = [
  Color(0xFF2563EB),
  Color(0xFF7C3AED),
  Color(0xFF0F766E),
  Color(0xFFDC2626),
  Color(0xFFD97706),
  Color(0xFF0EA5E9),
  Color(0xFF4F46E5),
  Color(0xFF047857),
  Color(0xFFBE123C),
  Color(0xFF9333EA),
];

String _normalizeMode(String mode) => mode.trim().toUpperCase();

bool _isTransitLeg(RouteLeg leg) {
  final mode = _normalizeMode(leg.mode);
  return mode != 'WALK' && mode != 'BICYCLE' && mode != 'CAR';
}

String _modeLabel(String mode) {
  return switch (_normalizeMode(mode)) {
    'BUS' => 'Bus',
    'TROLLEYBUS' => 'Trolleybus',
    'TRAM' => 'Tram',
    'RAIL' => 'Train',
    'SUBWAY' => 'Metro',
    'WALK' => 'Walk',
    _ => mode.trim().isEmpty ? 'Transit' : mode.trim(),
  };
}

String _lineIdFromRouteId(String routeId) {
  final raw = routeId.trim();
  if (raw.isEmpty) return '';
  final withoutFeed = raw.contains(':') ? raw.split(':').last : raw;
  return withoutFeed.trim();
}

Color _stableColorForKey(String key) {
  if (key.isEmpty) return const Color(0xFF64748B);
  final idx = key.hashCode.abs() % _kTransitFallbackPalette.length;
  return _kTransitFallbackPalette[idx];
}

Color _legColor(RouteLeg leg) {
  if (!_isTransitLeg(leg)) {
    return const Color(0xFF64748B);
  }
  final lineId = _lineIdFromRouteId(leg.routeId);
  if (_kLineColorOverrides.containsKey(lineId)) {
    return _kLineColorOverrides[lineId]!;
  }
  final normalizedMode = _normalizeMode(leg.mode);
  if (lineId.isNotEmpty) {
    return _stableColorForKey('$normalizedMode:$lineId');
  }
  return _stableColorForKey(normalizedMode);
}

String _legBadgeLabel(RouteLeg leg) {
  final mode = _modeLabel(leg.mode);
  final lineId = _lineIdFromRouteId(leg.routeId);
  if (!_isTransitLeg(leg) || lineId.isEmpty) {
    return mode;
  }
  return '$mode $lineId';
}

List<RouteLeg> _transitLegs(RouteOption option) {
  return option.legs.where(_isTransitLeg).toList();
}

class MapTab extends ConsumerStatefulWidget {
  const MapTab({super.key});

  @override
  ConsumerState<MapTab> createState() => _MapTabState();
}

class _MapTabState extends ConsumerState<MapTab> with TickerProviderStateMixin {
  static const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const _fallbackCenter =
      LatLng(kDefaultSearchRefLat, kDefaultSearchRefLon);
  static const _fallbackZoom = 11.0;
  static const _userZoom = 15.5;
  final _store = const FMTCStore('rotransit_osm_cache');
  final _mapController = MapController();
  bool _cacheReady = false;
  LatLng? _userLocation;
  double _mapRotation = 0;
  bool _initialUserFocusApplied = false;
  int? _lastFittedOptionHash;
  String? _lastFittedListRequestKey;
  final _routeListScrollController = ScrollController();
  bool _detailsCollapsed = false;
  bool _searchViewResetApplied = false;

  @override
  void initState() {
    super.initState();
    _initCacheStore();
    _initUserLocation();
  }

  @override
  void dispose() {
    _routeListScrollController.dispose();
    super.dispose();
  }

  Future<void> _initCacheStore() async {
    try {
      await _store.manage.create();
      if (!mounted) return;
      setState(() => _cacheReady = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _cacheReady = false);
    }
  }

  Future<void> _initUserLocation() async {
    final pos = await tryGetCurrentUserLatLon();
    if (!mounted || pos == null) return;
    final point = LatLng(pos.lat, pos.lon);
    setState(() => _userLocation = point);
    // Keep default city framing on Search; move to user only on explicit action.
    if (!_initialUserFocusApplied) _initialUserFocusApplied = true;
  }

  void _centerOnUser() {
    final point = _userLocation;
    if (point == null) {
      _initUserLocation();
      return;
    }
    _animateCameraTo(center: point, zoom: _userZoom);
  }

  void _resetNorth() {
    _animateCameraTo(rotation: 0);
  }

  void _exitRouteSheetToSearch() {
    if (!mounted) return;
    setState(() => _detailsCollapsed = false);
    ref.read(showMapSheetProvider.notifier).state = false;
    ref.read(routeMapOverlaySuppressedProvider.notifier).state = true;
    ref.read(searchMapStateProvider.notifier).clearRouteSheetSelection();
  }

  Future<void> _animateCameraTo({
    LatLng? center,
    double? zoom,
    double? rotation,
    Duration duration = const Duration(milliseconds: 420),
  }) async {
    if (!mounted) return;
    final camera = _mapController.camera;
    final startCenter = camera.center;
    final startZoom = camera.zoom;
    final startRotation = camera.rotation;

    final targetCenter = center ?? startCenter;
    final targetZoom = zoom ?? startZoom;
    final targetRotation = rotation ?? startRotation;

    final noChange = targetCenter == startCenter &&
        (targetZoom - startZoom).abs() < 0.001 &&
        (targetRotation - startRotation).abs() < 0.001;
    if (noChange) return;

    final ctrl = AnimationController(vsync: this, duration: duration);
    final curved = CurvedAnimation(parent: ctrl, curve: Curves.easeInOutCubic);
    final zoomTween = Tween<double>(begin: startZoom, end: targetZoom);
    final rotationTween = Tween<double>(
      begin: startRotation,
      end: targetRotation,
    );

    void tick() {
      final t = curved.value;
      final nextCenter = LatLng(
        startCenter.latitude +
            (targetCenter.latitude - startCenter.latitude) * t,
        startCenter.longitude +
            (targetCenter.longitude - startCenter.longitude) * t,
      );
      final nextZoom = zoomTween.transform(t);
      final nextRotation = rotationTween.transform(t);
      _mapController.moveAndRotate(nextCenter, nextZoom, nextRotation);
      _syncMapRotation(nextRotation);
    }

    ctrl.addListener(tick);
    try {
      await ctrl.forward();
    } finally {
      ctrl.removeListener(tick);
      ctrl.dispose();
    }
  }

  void _syncMapRotation(double rotation) {
    if (!mounted || (_mapRotation - rotation).abs() < 0.01) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.transientCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || (_mapRotation - rotation).abs() < 0.01) return;
        setState(() => _mapRotation = rotation);
      });
      return;
    }
    setState(() => _mapRotation = rotation);
  }

  LatLng? _parseLatLon(String value) {
    final parts = value.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lon = double.tryParse(parts[1].trim());
    if (lat == null || lon == null) return null;
    return LatLng(lat, lon);
  }

  static bool _isWalkLikeLegMode(String mode) {
    switch (mode.toUpperCase()) {
      case 'WALK':
      case 'BICYCLE':
      case 'BIKE':
      case 'CAR':
        return true;
      default:
        return false;
    }
  }

  /// OTP often alights at a different platform than the geocoded stop from search
  /// suggestions; the last transit leg's [to] matches the drawn route.
  static LatLng? _lastTransitLegAlightPoint(List<RouteLeg> legs) {
    for (var i = legs.length - 1; i >= 0; i--) {
      if (_isWalkLikeLegMode(legs[i].mode)) continue;
      final leg = legs[i];
      if (leg.toLat != 0 || leg.toLon != 0) {
        return LatLng(leg.toLat, leg.toLon);
      }
    }
    return null;
  }

  LatLng? _routeLandmarkPoint({
    required RouteOption? selectedOption,
    required String? requestDestination,
    required bool effectiveDetails,
    required List<RouteLegStop> detailStops,
  }) {
    if (selectedOption != null && selectedOption.legs.isNotEmpty) {
      final alight = _lastTransitLegAlightPoint(selectedOption.legs);
      if (alight != null) return alight;
      final last = selectedOption.legs.last;
      if (last.toLat != 0 || last.toLon != 0) {
        return LatLng(last.toLat, last.toLon);
      }
    }
    if (effectiveDetails && detailStops.isNotEmpty) {
      final last = detailStops.last;
      return LatLng(last.lat, last.lon);
    }
    return _parseLatLon(requestDestination ?? '');
  }

  List<LatLng> _legPoints(RouteLeg leg) {
    if (leg.geometry.isNotEmpty) {
      return leg.geometry.map((e) => LatLng(e.lat, e.lon)).toList();
    }
    final fallback = <LatLng>[];
    if (leg.fromLat != 0 || leg.fromLon != 0) {
      fallback.add(LatLng(leg.fromLat, leg.fromLon));
    }
    if (leg.toLat != 0 || leg.toLon != 0) {
      fallback.add(LatLng(leg.toLat, leg.toLon));
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchMapStateProvider);
    final ctrl = ref.read(searchMapStateProvider.notifier);
    final showSheet = ref.watch(showMapSheetProvider);
    final selectedTab = ref.watch(selectedTabProvider);
    final routeOverlaySuppressed = ref.watch(routeMapOverlaySuppressedProvider);
    final showRouteMapOverlay = !routeOverlaySuppressed;
    final originPoint = _parseLatLon(state.lastRequest?.origin ?? '');
    final selectedOption = state.selectedOption;
    final isDetailsMode = state.mode == SheetMode.details && selectedOption != null;
    final effectiveDetails = isDetailsMode && showRouteMapOverlay;
    final List<({RouteLeg leg, List<LatLng> points})> detailLegPolylines =
        effectiveDetails
            ? selectedOption.legs
                .map((leg) => (
                      leg: leg,
                      points: _legPoints(leg),
                    ))
                .where((entry) => entry.points.length >= 2)
                .toList()
            : <({RouteLeg leg, List<LatLng> points})>[];
    if (effectiveDetails && detailLegPolylines.isEmpty) {
      final fromPoint = _parseLatLon(state.lastRequest?.origin ?? '');
      final toPoint = _parseLatLon(state.lastRequest?.destination ?? '');
      if (fromPoint != null && toPoint != null) {
        detailLegPolylines.add((
          leg: const RouteLeg(
            mode: 'ROUTE',
            routeId: '',
            fromName: '',
            fromLat: 0,
            fromLon: 0,
            toName: '',
            toLat: 0,
            toLon: 0,
            startTime: 0,
            endTime: 0,
            distance: 0,
          ),
          points: [fromPoint, toPoint],
        ));
      }
    }
    final List<RouteLegStop> detailStops = effectiveDetails
        ? selectedOption.legs
            .expand((leg) => leg.stops)
            .where((stop) => stop.lat != 0 || stop.lon != 0)
            .toList()
        : const <RouteLegStop>[];
    final List<LatLng> detailStopPoints = effectiveDetails
        ? (() {
            final out = <LatLng>[];
            final seen = <String>{};
            void addPoint(double lat, double lon) {
              if (lat == 0 && lon == 0) return;
              final key = '${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)}';
              if (!seen.add(key)) return;
              out.add(LatLng(lat, lon));
            }

            // Keep explicit stop markers from backend leg stop lists.
            for (final stop in detailStops) {
              addPoint(stop.lat, stop.lon);
            }
            // Add transit leg endpoints so transfer/alight nodes always get a marker.
            for (final leg in selectedOption.legs.where(_isTransitLeg)) {
              addPoint(leg.fromLat, leg.fromLon);
              addPoint(leg.toLat, leg.toLon);
            }
            return out;
          })()
        : const <LatLng>[];
    final LatLng? landmarkPoint = effectiveDetails
        ? _routeLandmarkPoint(
            selectedOption: selectedOption,
            requestDestination: state.lastRequest?.destination,
            effectiveDetails: effectiveDetails,
            detailStops: detailStops,
          )
        : null;
    if (!isDetailsMode) {
      _lastFittedOptionHash = null;
    }
    if (effectiveDetails && detailLegPolylines.isNotEmpty) {
      final optionHash = Object.hashAll(
        detailLegPolylines.expand((entry) => entry.points),
      );
      if (_lastFittedOptionHash != optionHash) {
        _lastFittedOptionHash = optionHash;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final all = detailLegPolylines.expand((entry) => entry.points).toList();
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(all),
              padding: const EdgeInsets.fromLTRB(48, 40, 48, 48),
            ),
          );
        });
      }
    }
    final routeSheetBottomInset = mapSheetStackBottomInset(context);

    // Keep list mode map stable: no auto-fit/zoom while browsing route options.
    if (!isDetailsMode) {
      _lastFittedListRequestKey = null;
    }

    // Returning to Search should always restore city-level framing.
    if (selectedTab == 0 && !showSheet) {
      if (!_searchViewResetApplied) {
        _searchViewResetApplied = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _mapController.move(_fallbackCenter, _fallbackZoom);
          _mapController.rotate(0);
        });
      }
    } else {
      _searchViewResetApplied = false;
    }
    return SafeArea(
      top: false,
      bottom: false,
      child: LayoutBuilder(
        builder: (context, mapConstraints) {
          const routeSheetTopGap = kShellFloatingNavBottomMargin;
          final routeSheetBottomGap = routeSheetBottomInset;
          final fabStackBottom = routeSheetBottomGap + 20;

          return Stack(
            children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _fallbackCenter,
              initialZoom: _fallbackZoom,
              onPositionChanged: (camera, hasGesture) {
                _syncMapRotation(camera.rotation);
              },
              onTap: (_, latLng) {
                final selectionTarget = ref.read(mapSelectionTargetProvider);
                final point =
                    '${latLng.latitude.toStringAsFixed(5)},${latLng.longitude.toStringAsFixed(5)}';
                if (selectionTarget != null) {
                  ref.read(mapPickedLocationProvider.notifier).state =
                      MapPickedLocation(target: selectionTarget, value: point);
                  ref.read(mapSelectionTargetProvider.notifier).state = null;
                  ref.read(selectedTabProvider.notifier).state = 0;
                  final targetLabel =
                      selectionTarget == LocationSelectionTarget.from
                          ? 'From'
                          : 'To';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Selected map location for $targetLabel'),
                    ),
                  );
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Selected: $point')),
                );
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _tileUrl,
                userAgentPackageName: 'com.example.rotransit_frontend',
                tileProvider: _cacheReady
                    ? FMTCTileProvider(
                        stores: {
                          _store.storeName:
                              BrowseStoreStrategy.readUpdateCreate,
                        },
                      )
                    : NetworkTileProvider(),
              ),
              if (effectiveDetails && detailLegPolylines.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    for (final leg in detailLegPolylines)
                      Polyline(
                        points: leg.points,
                        strokeWidth: 6,
                        color: _legColor(leg.leg),
                        borderStrokeWidth: 1.5,
                        borderColor: Colors.white.withValues(alpha: 0.8),
                      ),
                  ],
                ),
              if (effectiveDetails && detailStopPoints.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (final point in detailStopPoints)
                      Marker(
                        point: point,
                        width: _kGraphStopDotSize,
                        height: _kGraphStopDotSize,
                        alignment: Alignment.center,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.35),
                              width: 1,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x28000000),
                                blurRadius: 1.5,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              if (effectiveDetails &&
                  originPoint != null &&
                  state.lastRequest != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: originPoint,
                      width: _kOriginDotSize,
                      height: _kOriginDotSize,
                      alignment: Alignment.center,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF9CA3AF),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x30000000),
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              if (landmarkPoint != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: landmarkPoint,
                      width: _kLandmarkMarkerSize,
                      height: _kLandmarkMarkerSize,
                      alignment: Alignment.center,
                      child: const Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: (_kLandmarkMarkerSize - _kLandmarkIconSize) /
                                2,
                            top: (_kLandmarkMarkerSize / 2) -
                                _kLandmarkIconSize,
                            width: _kLandmarkIconSize,
                            height: _kLandmarkIconSize,
                            child: Icon(
                              Icons.place_rounded,
                              size: _kLandmarkIconSize,
                              color: Color(0xFFD92D20),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              if (_userLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _userLocation!,
                      width: _kUserLocationDotSize,
                      height: _kUserLocationDotSize,
                      alignment: Alignment.center,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          color: const Color(0xFF005FEA),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x44005FEA),
                              blurRadius: 6,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (!showSheet && selectedTab != 0)
            Positioned(
              right: 14,
              bottom: fabStackBottom,
              child: Column(
                children: [
                  _MapControlButton(
                    icon: Icons.my_location_rounded,
                    onPressed: _centerOnUser,
                  ),
                  const SizedBox(height: 10),
                  _MapControlButton(
                    onPressed: _resetNorth,
                    tooltip: 'Rotate map to north',
                    child: _CompassFabFace(mapRotationDeg: _mapRotation),
                  ),
                ],
              ),
            ),
          if (showSheet)
            if (state.mode == SheetMode.details && state.selectedOption != null)
              Positioned(
                left: kShellFloatingNavHorizontalMargin,
                right: kShellFloatingNavHorizontalMargin,
                top: routeSheetTopGap,
                bottom: _detailsCollapsed ? null : routeSheetBottomGap,
                child: Material(
                  elevation: 4,
                  shadowColor: Colors.black26,
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius:
                      BorderRadius.circular(kMapRouteSheetCornerRadius),
                  clipBehavior: Clip.antiAlias,
                  child: _RouteDetailsPanel(
                    cityId: state.cityId,
                    option: state.selectedOption!,
                    isCollapsed: _detailsCollapsed,
                    onToggleCollapsed: () {
                      setState(() => _detailsCollapsed = !_detailsCollapsed);
                    },
                    onBack: () {
                      setState(() => _detailsCollapsed = false);
                      ctrl.backToList();
                    },
                  ),
                ),
              )
            else
              Positioned(
                left: kShellFloatingNavHorizontalMargin,
                right: kShellFloatingNavHorizontalMargin,
                top: routeSheetTopGap,
                bottom: routeSheetBottomGap,
                child: Material(
                  elevation: 4,
                  shadowColor: Colors.black26,
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius:
                      BorderRadius.circular(kMapRouteSheetCornerRadius),
                  clipBehavior: Clip.antiAlias,
                  child: _RouteListPanel(
                    onReturnToSearch: _exitRouteSheetToSearch,
                    options: state.results
                        .take(state.visibleCount)
                        .toList(),
                    canLoadMore: state.results.length < state.total,
                    onLoadMore: () async {
                      final request = state.lastRequest;
                      if (request == null) return;
                      final response = await ref
                          .read(routeApiRepositoryProvider)
                          .search(
                            RouteSearchRequest(
                              cityId: request.cityId,
                              origin: request.origin,
                              destination: request.destination,
                              serviceDate: request.serviceDate,
                              serviceTime: request.serviceTime,
                              passengerCount: request.passengerCount,
                              offset: state.results.length,
                              limit: request.limit,
                            ),
                          );
                      ctrl.appendResults(
                        options: response.routes,
                        offset: response.offset,
                        limit: response.limit,
                        total: response.total,
                      );
                    },
                    onTapOption: (option) {
                      setState(() => _detailsCollapsed = false);
                      ref
                          .read(routeMapOverlaySuppressedProvider.notifier)
                          .state = false;
                      ctrl.openDetails(option);
                    },
                    scrollController: _routeListScrollController,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    this.icon,
    this.child,
    this.tooltip,
    required this.onPressed,
  }) : assert(icon != null || child != null);

  final IconData? icon;
  final Widget? child;
  final String? tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0058D8),
      shape: const CircleBorder(),
      elevation: 4,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: child ?? Icon(icon, color: Colors.white),
      ),
    );
  }
}

/// Compass FAB: asset shows red arrow + “N” for geographic north; rotates with [mapRotationDeg]
/// so it stays aligned with how the map is turned (same direction as [MapCamera.rotation]).
class _CompassFabFace extends StatelessWidget {
  const _CompassFabFace({required this.mapRotationDeg});

  final double mapRotationDeg;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: mapRotationDeg * (math.pi / 180.0),
      child: SizedBox(
        width: 22,
        height: 22,
        child: Image.asset(
          'assets/icons/cardinal-point.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

class _RouteListPanel extends StatelessWidget {
  const _RouteListPanel({
    required this.onReturnToSearch,
    required this.options,
    required this.canLoadMore,
    required this.onLoadMore,
    required this.onTapOption,
    required this.scrollController,
  });

  final VoidCallback onReturnToSearch;
  final List<RouteOption> options;
  final bool canLoadMore;
  final Future<void> Function() onLoadMore;
  final void Function(RouteOption option) onTapOption;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final itemCount = options.isEmpty ? 2 : options.length + 2;

    return ListView.builder(
      controller: scrollController,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 8, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onReturnToSearch,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Return to search'),
              ),
            ),
          );
        }
        if (options.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Center(
              child: Text('Search routes to see options here.'),
            ),
          );
        }
        if (index == options.length + 1) {
          if (!canLoadMore) return const SizedBox(height: 12);
          return Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton(
              onPressed: () => onLoadMore(),
              child: const Text('Load next 10 options'),
            ),
          );
        }
        final item = options[index - 1];
        final start = item.legs.isEmpty
            ? null
            : DateTime.fromMillisecondsSinceEpoch(item.legs.first.startTime);
        final end = item.legs.isEmpty
            ? null
            : DateTime.fromMillisecondsSinceEpoch(item.legs.last.endTime);
        final timeFmt = DateFormat('h:mm a');
        final minutes = (item.durationSeconds / 60).round();
        final transitLegs = _transitLegs(item);

        return Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onTapOption(item),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        start == null || end == null
                            ? '--'
                            : '${timeFmt.format(start)} - ${timeFmt.format(end)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$minutes min',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (transitLegs.isEmpty)
                    Text(
                      'Walking route',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        for (final leg in transitLegs.take(4))
                          _LegBadge(leg: leg),
                        if (transitLegs.length > 4)
                          Text(
                            '+${transitLegs.length - 4} more',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.directions_walk,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${item.walkDistanceMeters} m',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Icon(
                        Icons.sync_alt,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${item.transfers} transfers',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${item.estimatedPriceLei} lei',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RouteDetailsPanel extends ConsumerWidget {
  const _RouteDetailsPanel({
    required this.cityId,
    required this.option,
    required this.isCollapsed,
    required this.onToggleCollapsed,
    required this.onBack,
  });

  final String cityId;
  final RouteOption option;
  final bool isCollapsed;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeFmt = DateFormat('h:mm a');
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
              const Expanded(
                child: Text(
                  'Trip details',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                onPressed: onToggleCollapsed,
                icon: Icon(
                  isCollapsed
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                ),
                label: Text(isCollapsed ? 'Show list' : 'Hide list'),
              ),
            ],
          ),
          if (!isCollapsed)
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(
                      '${(option.durationSeconds / 60).round()} min • ${option.transfers} transfers',
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (_transitLegs(option).isNotEmpty) ...[
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          for (final leg in _transitLegs(option))
                            _LegBadge(leg: leg),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '${option.estimatedPriceLei} lei',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (option.fareRule.isNotEmpty)
                      Text(
                        option.fareRule,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Text('Steps', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    for (final leg in option.legs) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _modeIcon(leg.mode),
                                const SizedBox(width: 8),
                                Text(
                                  _legBadgeLabel(leg),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${timeFmt.format(DateTime.fromMillisecondsSinceEpoch(leg.startTime))} - ${timeFmt.format(DateTime.fromMillisecondsSinceEpoch(leg.endTime))}',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              leg.fromName,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                'to ${leg.toName}',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                            Text(
                              '${leg.distance.toStringAsFixed(0)} m',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          await ref
                              .read(saveRouteControllerProvider)
                              .save(cityId: cityId, option: option);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Added to favorites')),
                            );
                          }
                        },
                        child: const Text('ADD TO FAVORITES'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _modeIcon(String mode) {
    final normalized = mode.toUpperCase();
    final icon = switch (normalized) {
      'BUS' => Icons.directions_bus,
      'TRAM' => Icons.tram,
      'RAIL' => Icons.train,
      'SUBWAY' => Icons.subway,
      _ => Icons.directions_walk,
    };
    return Icon(icon, size: 18);
  }
}

class _LegBadge extends StatelessWidget {
  const _LegBadge({required this.leg});

  final RouteLeg leg;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: _legColor(leg),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          _legBadgeLabel(leg),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
