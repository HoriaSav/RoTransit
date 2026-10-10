import 'dart:async' show StreamSubscription, unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:rotransit/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/map/tile_cache_backend.dart';
import '../../../core/errors/app_user_message.dart';
import '../../../core/ui/user_feedback.dart';
import '../../../core/theme/app_extra_colors.dart';
import '../../../core/location/live_position_source.dart';
import '../../../core/location/user_location_helpers.dart';
import '../../../core/location/user_location_provider.dart';
import '../../routes/domain/route_models.dart';
import '../../shell/shell_layout.dart';
import '../../shell/state/navigation_provider.dart';
import '../data/companion_catalog.dart';
import 'map_companion_tab.dart';
import 'stop_board_sheet.dart';

part 'map_controls.dart';

/// User GPS dot.
const double _kUserLocationDotSize = 18;

/// Stop pins show from this zoom. Brașov has 811 stops (median 58 m apart):
/// at 14 a phone screen holds ~140 overlapping 32 px pins, at 15 at most ~50.
const double kStopPinsMinZoom = 15;

/// Area whose stops get pins: the visible bounds plus a quarter of their
/// size on each side, so small pans don't rebuild the pin layer.
@visibleForTesting
LatLngBounds stopPinBounds(LatLngBounds visible) {
  final dLat = (visible.north - visible.south) / 4;
  final dLon = (visible.east - visible.west) / 4;
  return LatLngBounds(
    LatLng(math.max(-90, visible.south - dLat),
        math.max(-180, visible.west - dLon)),
    LatLng(
        math.min(90, visible.north + dLat), math.min(180, visible.east + dLon)),
  );
}

/// Pinch zoom moves this share of the fingers' zoom (log2 of the spread
/// ratio since the zoom started), so pinches feel gentler.
const double kPinchZoomDamping = 0.7;

class MapTab extends ConsumerStatefulWidget {
  const MapTab({super.key});

  @override
  ConsumerState<MapTab> createState() => _MapTabState();
}

class _MapTabState extends ConsumerState<MapTab>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  /// No-location view: Livada Poștei in the centre (middle of its 7 stops),
  /// at the zoom where stop pins show.
  static const _fallbackCenter = LatLng(45.6457, 25.5884);
  static const _fallbackZoom = kStopPinsMinZoom;
  static const _userZoom = 15.5;
  static const _launchZoom = 16.0;
  static const _launchPromptedKey = 'map_launch_location_prompted';
  final _store = const FMTCStore('rotransit_osm_cache');
  /// Stable instance — do not allocate a new [NetworkTileProvider] each build.
  final _networkTileProvider = NetworkTileProvider();
  /// Created once when FMTC store is ready; avoids tile pipeline reset on rebuild.
  FMTCTileProvider? _fmtcTileProvider;
  final _mapController = MapController();
  LatLng? _userLocation;
  double _mapRotation = 0;

  /// Live dot updates: on after the first fix (launch or center-on-me), paused
  /// while the app is in the background or the map is not the visible screen
  /// (another tab or Settings on top; the map stays mounted underneath).
  bool _followingUser = false;
  bool _inBackground = false;
  StreamSubscription<LivePosition>? _positionSub;

  /// Single instance so [FlutterMap.didUpdateWidget] does not treat options as
  /// changed on every parent rebuild (new closures break [MapOptions] equality).
  late final MapOptions _shellMapOptions;
  List<StopSearchItem> _companionStops = const [];
  String? _selectedCompanionStopId;
  double _mapZoom = _fallbackZoom;

  /// Stops inside these bounds get pins; null below [kStopPinsMinZoom].
  LatLngBounds? _pinBounds;

  /// Set once the rider (gesture, center-on-me) or the app (opening a stop)
  /// chose a view; a slow launch fix then leaves the camera alone.
  bool _userMovedMap = false;

  /// Pointers on the map, for the pinch focal point and spread.
  final _pointers = <int, Offset>{};
  double? _pinchStartZoom;
  double? _pinchStartSpread;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(selectedTabProvider, (_, __) => _onVisibilityChanged());
    ref.listenManual(settingsOpenProvider, (_, __) => _onVisibilityChanged());
    _shellMapOptions = MapOptions(
      initialCenter: _fallbackCenter,
      initialZoom: _fallbackZoom,
      keepAlive: true,
      onPositionChanged: _onShellMapPositionChanged,
      onMapEvent: _onShellMapEvent,
      onTap: _onShellMapTap,
      // flutter_map race checks pinchZoom BEFORE rotate. pinchZoomThreshold 1.0
      // made zoom feel delayed; ~0.35 made every pinch win before rotate.
      // Mid bar (~0.65 zoom / ~18° rotate): snappy pinch, intentional twist.
      interactionOptions: const InteractionOptions(
        enableMultiFingerGestureRace: true,
        rotationThreshold: 18,
        pinchZoomThreshold: 0.65,
        rotationWinGestures: MultiFingerGesture.rotate,
        pinchZoomWinGestures:
            MultiFingerGesture.pinchZoom | MultiFingerGesture.pinchMove,
      ),
    );
    _initCacheStore();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updatePinBounds(_mapController.camera); // the default view has pins
      unawaited(_loadCompanionStops());
      unawaited(_locateOnLaunch());
    });
  }

  /// Launch: center on the rider when location is allowed. The permission
  /// prompt is shown at most once at launch (while still undecided); a
  /// refusal keeps the default Brașov view silently, and center-on-me keeps
  /// working as before. The prompt is only used up once it really showed
  /// (not while location services are off). Android can't tell "undecided"
  /// from "refused once", so a rider who refused before gets this one prompt.
  Future<void> _locateOnLaunch() async {
    var prompting = false;
    try {
      if (!await ref.read(livePositionSourceProvider).canFollow()) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool(_launchPromptedKey) ?? false) return;
        if (!await canPromptForLocation()) return;
        prompting = true;
      }
    } catch (e) {
      debugPrint('Launch location skipped: $e');
      return;
    }
    if (!mounted) return;
    final loc = await ref.read(userLocationProvider.notifier).resolve();
    if (prompting) {
      // resolve() has asked for permission by now.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_launchPromptedKey, true);
    }
    if (!mounted || !loc.hasFix) return;
    final point = LatLng(loc.lat!, loc.lon!);
    setState(() => _userLocation = point);
    unawaited(_startFollowingUser());
    // A slow fix must not yank the map away from where the rider panned.
    if (!_userMovedMap) {
      await _animateCameraTo(center: point, zoom: _launchZoom);
    }
  }

  Future<void> _loadCompanionStops() async {
    try {
      final stops = await CompanionCatalog.instance.allStops();
      if (!mounted) return;
      setState(() => _companionStops = stops);
    } catch (e) {
      debugPrint('Could not load Brașov stop pins: $e');
    }
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

  Future<void> _initCacheStore() async {
    try {
      // Backend starts after the first frame; network tiles until then.
      if (!await tileCacheReady) return;
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPositionUpdates();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _inBackground = false;
        _listenPositionUpdates();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _inBackground = true;
        _stopPositionUpdates();
      case AppLifecycleState.inactive:
        break;
    }
  }

  bool get _mapVisible =>
      ref.read(selectedTabProvider) == 0 && !ref.read(settingsOpenProvider);

  void _onVisibilityChanged() {
    if (_mapVisible) {
      _listenPositionUpdates();
    } else {
      _stopPositionUpdates();
    }
  }

  /// "Center on me" tap: resolves location (may prompt) and starts following.
  Future<void> _initUserLocation() async {
    final loc = await ref.read(userLocationProvider.notifier).resolve();
    if (!mounted || !loc.hasFix) return;
    if (!isUsableLatLon(loc.lat!, loc.lon!)) return;
    setState(() => _userLocation = LatLng(loc.lat!, loc.lon!));
    unawaited(_startFollowingUser());
  }

  /// After permission was granted on the first tap, keep the dot moving.
  Future<void> _startFollowingUser() async {
    if (_followingUser) return;
    try {
      if (!await ref.read(livePositionSourceProvider).canFollow()) return;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    _followingUser = true;
    _listenPositionUpdates();
  }

  void _listenPositionUpdates() {
    if (!_followingUser || _inBackground || _positionSub != null) return;
    if (!_mapVisible) return;
    _positionSub = ref.read(livePositionSourceProvider).positions().listen(
      (p) {
        if (!mounted || !isUsableLatLon(p.lat, p.lon)) return;
        setState(() => _userLocation = LatLng(p.lat, p.lon));
      },
      onError: _onPositionError,
    );
  }

  /// Permission revoked or location turned off: drop the stale dot and say
  /// why. The next "center on me" tap asks again.
  void _onPositionError(Object error) {
    debugPrint('Live location stopped: $error');
    _stopPositionUpdates();
    _followingUser = false;
    if (!mounted) return;
    setState(() => _userLocation = null);
    unawaited(_showLocationFailure().catchError(
      (Object e) => debugPrint('Location hint unavailable: $e'),
    ));
  }

  void _stopPositionUpdates() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  Future<void> _centerOnUser() async {
    _userMovedMap = true;
    if (_userLocation == null) {
      await _initUserLocation();
    }
    if (!mounted) return;
    final point = _userLocation;
    if (point == null || !isUsableLatLon(point.latitude, point.longitude)) {
      await _showLocationFailure();
      return;
    }
    await _animateCameraTo(center: point, zoom: _userZoom);
  }

  Future<void> _showLocationFailure() async {
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
  }

  void _resetNorth() {
    _animateCameraTo(rotation: 0);
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
    _mapZoom = camera.zoom;
    if (hasGesture) _userMovedMap = true;
    _updatePinBounds(camera);
  }

  void _updatePinBounds(MapCamera camera) {
    final LatLngBounds? next;
    if (camera.zoom < kStopPinsMinZoom) {
      next = null;
    } else if (_pinBounds?.containsBounds(camera.visibleBounds) ?? false) {
      return;
    } else {
      next = stopPinBounds(camera.visibleBounds);
    }
    if (next != _pinBounds) setState(() => _pinBounds = next);
  }

  /// Damps pinch zoom by finger spread: from the moment the zoom starts, the
  /// map zooms [kPinchZoomDamping] x log2(spread / spread at start), around
  /// the fingers' focal point, so spreading x3 and pinching to a third zoom by
  /// the same amount. (flutter_map's own zoom is lopsided: after its gesture
  /// race it continues from the winning spread additively, not by ratio.)
  /// Rotation (no zoom change) and one-finger drags pass through untouched.
  void _onShellMapEvent(MapEvent event) {
    if (event is MapEventMoveStart &&
        event.source == MapEventSource.multiFingerGestureStart) {
      _pinchStartZoom = event.camera.zoom;
      _pinchStartSpread = _pointerSpread();
      return;
    }
    if (event is MapEventMoveEnd) {
      _pinchStartZoom = _pinchStartSpread = null;
      return;
    }
    final startZoom = _pinchStartZoom;
    final startSpread = _pinchStartSpread;
    final spread = _pointerSpread();
    if (event is! MapEventMove ||
        event.source != MapEventSource.onMultiFinger ||
        event.camera.zoom == event.oldCamera.zoom ||
        startZoom == null ||
        startSpread == null ||
        spread == null) {
      return;
    }
    final zoom = event.camera.clampZoom(startZoom +
        kPinchZoomDamping * math.log(spread / startSpread) / math.ln2);
    if ((zoom - event.camera.zoom).abs() < 1e-3) return;
    final focal = _pointers.values.reduce((a, b) => a + b) / 2;
    _mapController.move(event.camera.focusedZoomCenter(focal, zoom), zoom);
  }

  /// Distance between the two fingers, or null without exactly two.
  double? _pointerSpread() {
    if (_pointers.length != 2) return null;
    final d = (_pointers.values.first - _pointers.values.last).distance;
    return d > 0 ? d : null;
  }

  void _onShellMapTap(TapPosition tapPosition, LatLng latLng) {
    if (!isUsableLatLon(latLng.latitude, latLng.longitude)) return;
    if (_pinBounds == null) return; // pins hidden: nothing to tap
    // Companion: tap near a stop opens the schedule board.
    final nearest = _nearestCompanionStop(latLng, maxMeters: 70);
    if (nearest != null) {
      unawaited(_openCompanionStopBoard(context, nearest));
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
    _userMovedMap = true;
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

    ref.listen<StopSearchItem?>(companionFocusStopProvider, (prev, next) {
      if (next == null || identical(prev, next)) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_openCompanionStop(next));
        ref.read(companionFocusStopProvider.notifier).state = null;
      });
    });

    final fabStackBottom = mapSheetStackBottomInset(context) + 20;

    return SafeArea(
      top: false,
      bottom: false,
      child: Stack(
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
              if (_pinBounds case final pins?)
                MarkerLayer(
                  markers: [
                    for (final stop in _companionStops
                        .where((s) => pins.contains(LatLng(s.lat, s.lon))))
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
              // Tracks fingers for the pinch damping; translucent, so taps
              // and gestures still reach the pins and the map.
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (e) => _pointers[e.pointer] = e.localPosition,
                  onPointerMove: (e) => _pointers[e.pointer] = e.localPosition,
                  onPointerUp: (e) => _pointers.remove(e.pointer),
                  onPointerCancel: (e) => _pointers.remove(e.pointer),
                ),
              ),
            ],
          ),
          Consumer(
            builder: (context, ref, _) {
              if (ref.watch(selectedTabProvider) != 0) {
                return const SizedBox.shrink();
              }
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
        ],
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
