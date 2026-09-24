import 'dart:async' show StreamSubscription, unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:latlong2/latlong.dart' hide Path;
import 'package:rotransit/l10n/app_localizations.dart';

import '../../../core/format/distance_format.dart';
import '../../../core/errors/app_user_message.dart';
import '../../../core/errors/app_user_message_l10n.dart';
import '../../../core/ui/user_feedback.dart';
import '../../../core/theme/app_extra_colors.dart';
import '../../../core/location/user_location_helpers.dart';
import '../../../core/location/user_location_provider.dart';
import '../../routes/data/route_api_repository.dart';
import '../../routes/domain/route_models.dart';
import '../../routes/state/save_route_controller.dart';
import '../../search/domain/search_query.dart';
import '../../shell/shell_layout.dart';
import '../../shell/state/navigation_provider.dart';
import '../data/companion_catalog.dart';
import 'map_companion_tab.dart';
import 'stop_board_sheet.dart';

part 'map_route_style.dart';
part 'map_controls.dart';
part 'map_route_sheet.dart';

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
  /// Stable instance — do not allocate a new [NetworkTileProvider] each build.
  final _networkTileProvider = NetworkTileProvider();
  /// Created once when FMTC store is ready; avoids tile pipeline reset on rebuild.
  FMTCTileProvider? _fmtcTileProvider;
  final _mapController = MapController();
  LatLng? _userLocation;
  double _mapRotation = 0;
  bool _initialUserFocusApplied = false;
  int? _lastFittedOptionHash;
  final _routeListScrollController = ScrollController();
  /// Fraction of the route sheet slot height — [ValueNotifier] avoids rebuilding [FlutterMap] on drag.
  late final ValueNotifier<double> _routeMapSheetExtentNotifier;
  AnimationController? _routeSheetSnapController;
  /// Leg index in [RouteOption.legs] highlighted on the map and in the timeline.
  int _detailsHighlightedLegIndex = 0;
  bool _routeListLoadingMore = false;

  StreamSubscription<CompassEvent>? _itineraryCompassSub;
  bool _itineraryCompassFollowing = false;
  double _itineraryCompassSmoothedRad = 0;
  DateTime? _lastItineraryCompassApply;

  /// Single instance so [FlutterMap.didUpdateWidget] does not treat options as
  /// changed on every parent rebuild (new closures break [MapOptions] equality).
  late final MapOptions _shellMapOptions;
  List<StopSearchItem> _companionStops = const [];
  String? _selectedCompanionStopId;
  double _mapZoom = _fallbackZoom;
  static const _companionPinsMinZoom = 13.0;

  @override
  void initState() {
    super.initState();
    _routeMapSheetExtentNotifier = ValueNotifier<double>(1.0);
    _shellMapOptions = MapOptions(
      initialCenter: _fallbackCenter,
      initialZoom: _fallbackZoom,
      keepAlive: true,
      onPositionChanged: _onShellMapPositionChanged,
      onTap: _onShellMapTap,
    );
    _initCacheStore();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initUserLocation();
      _resyncItineraryCompassFromProviders();
      unawaited(_loadCompanionStops());
    });
  }

  Future<void> _loadCompanionStops() async {
    try {
      final stops = await CompanionCatalog.instance.allStops();
      if (!mounted) return;
      setState(() => _companionStops = stops);
    } catch (_) {}
  }


  Future<void> _openCompanionStopBoard(
    BuildContext context,
    StopSearchItem stop,
  ) async {
    setState(() => _selectedCompanionStopId = stop.stopId);
    try {
      await showStopBoardSheet(context, stop: stop);
    } finally {
      if (mounted) {
        setState(() => _selectedCompanionStopId = null);
      }
    }
  }


  @override
  void dispose() {
    _itineraryCompassSub?.cancel();
    _routeSheetSnapController?.dispose();
    _routeMapSheetExtentNotifier.dispose();
    _routeListScrollController.dispose();
    super.dispose();
  }

  Future<void> _initCacheStore() async {
    try {
      await _store.manage.create();
      if (!mounted) return;
      setState(() {
        _fmtcTileProvider ??= FMTCTileProvider(
          stores: {
            _store.storeName: BrowseStoreStrategy.readUpdateCreate,
          },
        );
      });
    } catch (_) {
      // FMTC unavailable — keep network tiles.
    }
  }

  Future<void> _initUserLocation({bool forceFresh = false}) async {
    final loc = await ref
        .read(userLocationProvider.notifier)
        .resolve(forceFresh: forceFresh);
    if (!mounted || !loc.hasFix) return;
    if (!isUsableLatLon(loc.lat!, loc.lon!)) return;
    final point = LatLng(loc.lat!, loc.lon!);
    setState(() => _userLocation = point);
    // Keep default city framing on Search; move to user only on explicit action.
    if (!_initialUserFocusApplied) _initialUserFocusApplied = true;
  }

  Future<void> _centerOnUser() async {
    if (_userLocation == null) {
      await _initUserLocation();
    }
    if (!mounted) return;
    final point = _userLocation;
    if (point == null || !isUsableLatLon(point.latitude, point.longitude)) {
      final l10n = AppLocalizations.of(context);
      final failure = await localizedUserLocationFailure(l10n);
      if (!mounted) return;
      showUserMessage(
        context,
        AppUserMessage.custom(
          failure.message,
          severity: UserMessageSeverity.warning,
          actionLabel: failure.showSettingsAction ? l10n.openSettings : null,
        ),
        onAction: failure.showSettingsAction ? openUserLocationSettings : null,
      );
      return;
    }
    await _animateCameraTo(center: point, zoom: _userZoom);
  }

  void _resetNorth() {
    _animateCameraTo(rotation: 0);
  }

  void _resyncItineraryCompassFromProviders() {
    if (!mounted) return;
    // Keep map heading under explicit user control in Search details.
    // Auto-following device compass forces repeated moveAndRotate calls that
    // override gesture rotation and cause snap-back behavior.
    const wantCompass = false;
    _syncItineraryCompassMode(wantCompass);
  }

  /// Heading-aligned map rotation while viewing step-by-step itinerary details only.
  void _syncItineraryCompassMode(bool wantCompass) {
    if (wantCompass == _itineraryCompassFollowing) return;
    _itineraryCompassFollowing = wantCompass;
    if (!wantCompass) {
      _itineraryCompassSub?.cancel();
      _itineraryCompassSub = null;
      _itineraryCompassSmoothedRad = 0;
      _lastItineraryCompassApply = null;
      unawaited(_animateCameraTo(rotation: 0));
      return;
    }
    _itineraryCompassSub?.cancel();
    final stream = FlutterCompass.events;
    if (stream == null) return;
    _itineraryCompassSmoothedRad = _mapController.camera.rotation;
    _itineraryCompassSub = stream.listen(
      (event) {
        final heading = event.heading;
        if (heading == null || !mounted || !_itineraryCompassFollowing) {
          return;
        }
        final now = DateTime.now();
        final last = _lastItineraryCompassApply;
        if (last != null && now.difference(last).inMilliseconds < 120) {
          return;
        }
        _lastItineraryCompassApply = now;
        final targetRad = heading * math.pi / 180.0;
        _itineraryCompassSmoothedRad = _lerpAngleRad(
          _itineraryCompassSmoothedRad,
          targetRad,
          0.25,
        );
        if (!mounted || !_itineraryCompassFollowing) return;
        final cam = _mapController.camera;
        _mapController.moveAndRotate(
          cam.center,
          cam.zoom,
          _itineraryCompassSmoothedRad,
        );
        _syncMapRotation(_itineraryCompassSmoothedRad);
      },
      onError: (_) {},
    );
  }

  void _applyRouteSheetDrag(double deltaY, double maxSheetH, double minSheetH) {
    if (!mounted || maxSheetH <= 0) return;
    _routeSheetSnapController?.stop();
    final currentH =
        (_routeMapSheetExtentNotifier.value * maxSheetH).clamp(minSheetH, maxSheetH);
    final newH = (currentH - deltaY).clamp(minSheetH, maxSheetH);
    _routeMapSheetExtentNotifier.value = newH / maxSheetH;
  }

  Future<void> _snapRouteSheetExtent(double maxSheetH, double minSheetH) async {
    if (!mounted || maxSheetH <= 0) return;
    final minE = (minSheetH / maxSheetH).clamp(0.01, 1.0);
    final anchors = <double>{minE, _kRouteSheetSnapMidExtent, 1.0}.toList()
      ..sort();
    final e = _routeMapSheetExtentNotifier.value;
    var target = anchors.first;
    var bestDist = (e - target).abs();
    for (final a in anchors) {
      final d = (e - a).abs();
      if (d < bestDist) {
        bestDist = d;
        target = a;
      }
    }
    final start = _routeMapSheetExtentNotifier.value;
    if ((start - target).abs() < 0.003) return;

    _routeSheetSnapController?.dispose();
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _routeSheetSnapController = ctrl;
    final curved = CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic);
    final animation =
        Tween<double>(begin: start, end: target).animate(curved);

    void tick() {
      if (!mounted) return;
      _routeMapSheetExtentNotifier.value = animation.value;
    }

    ctrl.addListener(tick);
    try {
      await ctrl.forward();
    } finally {
      if (_routeSheetSnapController == ctrl) {
        _routeSheetSnapController = null;
      }
      ctrl.removeListener(tick);
      curved.dispose();
      ctrl.dispose();
    }
  }

  void _exitRouteSheetToSearch() {
    if (!mounted) return;
    _routeMapSheetExtentNotifier.value = 1.0;
    ref.read(showMapSheetProvider.notifier).state = false;
    ref.read(routeMapOverlaySuppressedProvider.notifier).state = true;
    ref.read(searchMapStateProvider.notifier).clearRouteSheetSelection();
  }

  bool _routeNeedsGeometry(RouteOption option) {
    for (final leg in option.legs) {
      if (leg.geometry.length >= 2) continue;
      final hasEndpoints = (leg.fromLat != 0 || leg.fromLon != 0) &&
          (leg.toLat != 0 || leg.toLon != 0);
      if (hasEndpoints) return true;
    }
    return false;
  }

  Future<RouteOption> _routeOptionWithGeometry(
    SearchMapState state,
    RouteOption option,
    int resultIndex,
  ) async {
    if (!_routeNeedsGeometry(option) || state.lastRequest == null) {
      return option;
    }
    final base = state.lastRequest!;
    final response = await ref.read(routeApiRepositoryProvider).search(
          RouteSearchRequest(
            cityId: base.cityId,
            origin: base.origin,
            destination: base.destination,
            serviceDate: base.serviceDate,
            serviceTime: base.serviceTime,
            passengerCount: base.passengerCount,
            offset: resultIndex,
            limit: 1,
            includeGeometry: true,
          ),
        );
    if (response.routes.isEmpty) return option;
    final detailed = response.routes.first;
    ref.read(searchMapStateProvider.notifier).replaceResultAt(
          resultIndex,
          detailed,
        );
    return detailed;
  }

  Future<void> _openRouteDetails(
    SearchMapState state,
    RouteOption option,
    int resultIndex,
  ) async {
    _routeMapSheetExtentNotifier.value = _kRouteSheetSnapMidExtent;
    setState(() => _detailsHighlightedLegIndex = 0);
    ref.read(routeMapOverlaySuppressedProvider.notifier).state = false;
    final ctrl = ref.read(searchMapStateProvider.notifier);
    try {
      final detailed = await _routeOptionWithGeometry(state, option, resultIndex);
      if (!mounted) return;
      ctrl.openDetails(detailed);
    } catch (_) {
      if (!mounted) return;
      ctrl.openDetails(option);
      showUserMessage(context, AppUserMessages.routeShapeSimplified);
    }
  }

  Future<void> _loadMoreRouteResults(SearchMapState state) async {
    if (_routeListLoadingMore) return;
    final ctrl = ref.read(searchMapStateProvider.notifier);
    if (state.visibleCount < state.results.length) {
      ctrl.revealMoreResults();
      return;
    }
    if (!state.hasMore && state.results.length >= state.total) {
      return;
    }
    if (state.lastRequest == null) {
      return;
    }
    setState(() => _routeListLoadingMore = true);
    try {
      final base = state.lastRequest!;
      final pageRequest = RouteSearchRequest(
        cityId: base.cityId,
        origin: base.origin,
        destination: base.destination,
        serviceDate: base.serviceDate,
        serviceTime: base.serviceTime,
        passengerCount: base.passengerCount,
        offset: state.results.length,
        limit: kRouteSearchPageSize,
        includeGeometry: base.includeGeometry,
      );
      final response =
          await ref.read(routeApiRepositoryProvider).search(pageRequest);
      if (!mounted) return;
      ctrl.appendResults(
        options: response.routes,
        offset: response.offset,
        limit: response.limit,
        total: response.total,
        hasMore: response.hasMore,
      );
    } catch (_) {
      if (!mounted) return;
      showUserMessage(context, AppUserMessages.loadMoreRoutesFailed);
    } finally {
      if (mounted) setState(() => _routeListLoadingMore = false);
    }
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
    if (!isUsableLatLon(targetCenter.latitude, targetCenter.longitude)) {
      return;
    }

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

  void _onShellMapPositionChanged(MapCamera camera, bool hasGesture) {
    _syncMapRotation(camera.rotation);
    final z = camera.zoom;
    if ((z - _mapZoom).abs() >= 0.15) {
      setState(() => _mapZoom = z);
    } else {
      _mapZoom = z;
    }
  }

  void _onShellMapTap(TapPosition tapPosition, LatLng latLng) {
    if (!isUsableLatLon(latLng.latitude, latLng.longitude)) return;
    final selectionTarget = ref.read(mapSelectionTargetProvider);
    final point = latLonPoint(latLng.latitude, latLng.longitude);
    if (selectionTarget != null) {
      ref.read(mapPickedLocationProvider.notifier).state =
          MapPickedLocation(target: selectionTarget, value: point);
      ref.read(mapSelectionTargetProvider.notifier).state = null;
      ref.read(selectedTabProvider.notifier).state = 0;
      final targetLabel = selectionTarget == LocationSelectionTarget.from
          ? 'From'
          : 'To';
      showUserMessage(
        context,
        AppUserMessages.mapLocationPicked(targetLabel),
      );
      return;
    }

    // Companion: tap near a stop opens the schedule board.
    final routeOverlaySuppressed = ref.read(routeMapOverlaySuppressedProvider);
    final showSheet = ref.read(showMapSheetProvider);
    if (!showSheet || routeOverlaySuppressed) {
      final nearest = _nearestCompanionStop(latLng, maxMeters: 70);
      if (nearest != null) {
        unawaited(_openCompanionStopBoard(context, nearest));
        return;
      }
    }
  }

  StopSearchItem? _nearestCompanionStop(LatLng latLng, {required double maxMeters}) {
    if (_companionStops.isEmpty) return null;
    const dist = Distance();
    StopSearchItem? best;
    var bestM = maxMeters;
    for (final s in _companionStops) {
      final m = dist.as(
        LengthUnit.Meter,
        latLng,
        LatLng(s.lat, s.lon),
      );
      if (m <= bestM) {
        bestM = m;
        best = s;
      }
    }
    return best;
  }

  Future<void> _openCompanionStop(StopSearchItem stop) async {
    await _animateCameraTo(
      center: LatLng(stop.lat, stop.lon),
      zoom: math.max(_mapZoom, 15.5),
    );
    if (!mounted) return;
    await _openCompanionStopBoard(context, stop);
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

  List<Polyline> _buildDetailPolylines(
    RouteOption selectedOption,
    int highlightedIndex, {
    LatLng? fallbackOrigin,
    LatLng? fallbackDestination,
  }) {
    final polylines = <Polyline>[];
    final legs = selectedOption.legs;
    for (var i = 0; i < legs.length; i++) {
      final points = _legPoints(legs[i]);
      if (points.length < 2) continue;
      final base = _legColor(legs[i]);
      final isActive = i == highlightedIndex;
      final strokeOpacity = isActive
          ? _kMapRouteStrokeOpacityHighlight
          : _kMapRouteStrokeOpacityLeg;
      polylines.add(
        Polyline(
          points: points,
          strokeWidth: isActive ? 7.0 : 5.5,
          color: base.withValues(alpha: strokeOpacity),
          borderStrokeWidth: isActive ? 1.6 : 1.35,
          borderColor: Colors.white.withValues(alpha: isActive ? 0.82 : 0.75),
        ),
      );
    }
    if (polylines.isEmpty &&
        fallbackOrigin != null &&
        fallbackDestination != null) {
      polylines.add(
        Polyline(
          points: [fallbackOrigin, fallbackDestination],
          strokeWidth: 6.0,
          color: const Color(0xFF64748B)
              .withValues(alpha: _kMapRouteStrokeOpacityLeg),
          borderStrokeWidth: 1.35,
          borderColor: Colors.white.withValues(alpha: 0.75),
        ),
      );
    }
    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen<UserLocationState>(userLocationProvider, (previous, next) {
      if (!next.hasFix || next.lat == null || next.lon == null) return;
      if (!isUsableLatLon(next.lat!, next.lon!)) return;
      final point = LatLng(next.lat!, next.lon!);
      if (_userLocation?.latitude == point.latitude &&
          _userLocation?.longitude == point.longitude) {
        return;
      }
      setState(() => _userLocation = point);
    });

    ref.listen<bool>(showMapSheetProvider, (previous, next) {
      if (previous != true || next != false) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(selectedTabProvider) != 0) return;
        unawaited(
          _animateCameraTo(
            center: _fallbackCenter,
            zoom: _fallbackZoom,
            rotation: 0,
            duration: const Duration(milliseconds: 520),
          ),
        );
      });
    });

    ref.listen<int>(routeSheetExpandFullProvider, (previous, next) {
      if (previous == next) return;
      _routeMapSheetExtentNotifier.value = 1.0;
    });

    ref.listen<SearchMapState>(searchMapStateProvider, (previous, next) {
      final pending = next.pendingDetailsExtent;
      if (pending != null &&
          next.mode == SheetMode.details &&
          next.selectedOption != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _routeMapSheetExtentNotifier.value = pending;
          ref.read(searchMapStateProvider.notifier).clearPendingDetailsExtent();
        });
      }
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _resyncItineraryCompassFromProviders());
    });
    ref.listen<bool>(routeMapOverlaySuppressedProvider, (_, __) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _resyncItineraryCompassFromProviders());
    });

    ref.listen<StopSearchItem?>(companionFocusStopProvider, (prev, next) {
      if (next == null || identical(prev, next)) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_openCompanionStop(next));
        ref.read(companionFocusStopProvider.notifier).state = null;
      });
    });

    final state = ref.watch(searchMapStateProvider);
    final ctrl = ref.read(searchMapStateProvider.notifier);
    final showSheet = ref.watch(showMapSheetProvider);
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
    final detailMapPolylines = effectiveDetails
        ? _buildDetailPolylines(
            selectedOption,
            _detailsHighlightedLegIndex,
            fallbackOrigin: _parseLatLon(state.lastRequest?.origin ?? ''),
            fallbackDestination:
                _parseLatLon(state.lastRequest?.destination ?? ''),
          )
        : <Polyline>[];
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

    return SafeArea(
      top: false,
      bottom: false,
      child: LayoutBuilder(
        builder: (context, mapConstraints) {
          const routeSheetTopGap = kShellFloatingNavBottomMargin;
          final routeSheetBottomGap = routeSheetBottomInset;
          final fabStackBottom = routeSheetBottomGap + 20;
          final routeSlotHeight = math.max(
            120.0,
            mapConstraints.maxHeight - routeSheetTopGap - routeSheetBottomGap,
          );
          final minSheetH = math.max(
            84.0,
            routeSlotHeight * _kRouteSheetMinExtent,
          );
          final maxSheetH = routeSlotHeight;

          return Stack(
            children: [
          FlutterMap(
            mapController: _mapController,
            options: _shellMapOptions,
            children: [
              TileLayer(
                key: const ValueKey<Object>('rotransit_osm_tiles'),
                urlTemplate: _tileUrl,
                userAgentPackageName: 'com.rotransit.app',
                tileProvider: _fmtcTileProvider ?? _networkTileProvider,
              ),
              if (detailMapPolylines.isNotEmpty)
                PolylineLayer(
                  polylines: detailMapPolylines,
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
              if (!effectiveDetails &&
                  _mapZoom >= _companionPinsMinZoom &&
                  _companionStops.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (final stop in _companionStops)
                      Marker(
                        point: LatLng(stop.lat, stop.lon),
                        width: stop.stopId == _selectedCompanionStopId ? 40 : 32,
                        height: stop.stopId == _selectedCompanionStopId ? 40 : 32,
                        alignment: Alignment.center,
                        child: GestureDetector(
                          onTap: () => unawaited(
                            _openCompanionStopBoard(context, stop),
                          ),
                          child: _CompanionStopMarker(
                            selected: stop.stopId == _selectedCompanionStopId,
                          ),
                        ),
                      ),
                  ],
                ),
              if (_userLocation != null &&
                  isUsableLatLon(
                    _userLocation!.latitude,
                    _userLocation!.longitude,
                  ))
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
          Consumer(
            builder: (context, ref, _) {
              final sheet = ref.watch(showMapSheetProvider);
              final tab = ref.watch(selectedTabProvider);
              // Hide only when a route sheet covers the map.
              if (sheet) return const SizedBox.shrink();
              if (tab != 0 && tab != 1) {
                // still show on map-ish tabs; hide on favorites/settings dense UIs
              }
              if (tab == 2 || tab == 3) return const SizedBox.shrink();
              return Positioned(
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
                      tooltip: l10n.mapRotateNorth,
                      child: _CompassFabFace(mapRotationDeg: _mapRotation),
                    ),
                  ],
                ),
              );
            },
          ),
          if (showSheet)
            if (state.mode == SheetMode.details &&
                state.selectedOption != null)
              ValueListenableBuilder<double>(
                valueListenable: _routeMapSheetExtentNotifier,
                builder: (context, extent, _) {
                  final routeSheetH =
                      (extent * maxSheetH).clamp(minSheetH, maxSheetH);
                  void onRouteSheetDrag(double dy) =>
                      _applyRouteSheetDrag(dy, maxSheetH, minSheetH);
                  void onRouteSheetDragEnd() => unawaited(
                        _snapRouteSheetExtent(maxSheetH, minSheetH),
                      );
                  return Positioned(
                    left: kShellFloatingNavHorizontalMargin,
                    right: kShellFloatingNavHorizontalMargin,
                    bottom: routeSheetBottomGap,
                    height: routeSheetH,
                    child: Material(
                      elevation: 4,
                      shadowColor: Theme.of(context).colorScheme.shadow,
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius:
                          BorderRadius.circular(kMapRouteSheetCornerRadius),
                      clipBehavior: Clip.antiAlias,
                      child: _RouteDetailsPanel(
                        cityId: state.cityId,
                        option: state.selectedOption!,
                        sheetHeight: routeSheetH,
                        onSheetDragDelta: onRouteSheetDrag,
                        onSheetDragEnd: onRouteSheetDragEnd,
                        highlightedLegIndex: _detailsHighlightedLegIndex,
                        onLegHighlightChanged: (index) {
                          setState(() => _detailsHighlightedLegIndex = index);
                        },
                        showSaveToFavorites: !state.openedFromSavedFavorite,
                        onBack: () {
                          if (state.openedFromSavedFavorite) {
                            _routeMapSheetExtentNotifier.value = 1.0;
                            ref.read(showMapSheetProvider.notifier).state =
                                false;
                            ctrl.closeFavoriteMapPreview();
                            ref.read(selectedTabProvider.notifier).state = 2;
                          } else {
                            _routeMapSheetExtentNotifier.value = 1.0;
                            ctrl.backToList();
                          }
                        },
                      ),
                    ),
                  );
                },
              )
            else
              Positioned(
                left: kShellFloatingNavHorizontalMargin,
                right: kShellFloatingNavHorizontalMargin,
                bottom: routeSheetBottomGap,
                height: maxSheetH,
                child: Material(
                  elevation: 4,
                  shadowColor: Theme.of(context).colorScheme.shadow,
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius:
                      BorderRadius.circular(kMapRouteSheetCornerRadius),
                  clipBehavior: Clip.antiAlias,
                  child: _RouteListPanel(
                    onReturnToSearch: _exitRouteSheetToSearch,
                    onSheetDragDelta: (_) {},
                    allowSheetResize: false,
                    options: state.results
                        .take(state.visibleCount)
                        .toList(),
                    canLoadMore: state.hasMore ||
                        state.visibleCount < state.results.length,
                    remainingToReveal: () {
                      final local =
                          state.results.length - state.visibleCount;
                      if (local > 0) return local;
                      if (state.hasMore) {
                        return kRouteSearchPageSize;
                      }
                      return state.total - state.results.length;
                    }(),
                    remainingOnServer: state.hasMore &&
                            state.total <= state.results.length
                        ? 0
                        : state.total - state.results.length,
                    isLoadingMore: _routeListLoadingMore,
                    onLoadMore: () => _loadMoreRouteResults(state),
                    onTapOption: (option, resultIndex) {
                      unawaited(_openRouteDetails(state, option, resultIndex));
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


class _CompanionStopMarker extends StatelessWidget {
  const _CompanionStopMarker({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final size = selected ? 36.0 : 28.0;
    final iconSize = selected ? 20.0 : 16.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF0A3E96) : const Color(0xFF1565C0),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: selected ? 2.5 : 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.directions_bus_rounded,
        size: iconSize,
        color: Colors.white,
      ),
    );
  }
}
