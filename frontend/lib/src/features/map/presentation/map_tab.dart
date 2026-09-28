import 'dart:async' show StreamSubscription, unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:rotransit/l10n/app_localizations.dart';

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

class MapTab extends ConsumerStatefulWidget {
  const MapTab({super.key});

  @override
  ConsumerState<MapTab> createState() => _MapTabState();
}

class _MapTabState extends ConsumerState<MapTab>
    with TickerProviderStateMixin, WidgetsBindingObserver {
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

  /// Live dot updates: on after the first successful "center on me", paused
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
  static const _companionPinsMinZoom = 13.0;

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
      unawaited(_loadCompanionStops());
    });
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

  /// Location is resolved only on the "center on me" tap (no prompt at startup).
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
    final z = camera.zoom;
    if ((z - _mapZoom).abs() >= 0.15) {
      setState(() => _mapZoom = z);
    } else {
      _mapZoom = z;
    }
  }

  void _onShellMapTap(TapPosition tapPosition, LatLng latLng) {
    if (!isUsableLatLon(latLng.latitude, latLng.longitude)) return;
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
              if (_mapZoom >= _companionPinsMinZoom &&
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
