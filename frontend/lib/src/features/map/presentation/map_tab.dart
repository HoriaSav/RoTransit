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

import '../../../core/format/distance_format.dart';
import '../../../core/ui/app_snackbar.dart';
import '../../../core/theme/app_extra_colors.dart';
import '../../../core/location/user_location_helpers.dart';
import '../../../core/location/user_location_provider.dart';
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

/// Non-highlighted legs: full [_legColor] saturation.
const double _kMapRouteStrokeOpacityLeg = 1.0;
/// Highlighted leg: slightly toned down so focus isn’t harsher than the rest.
const double _kMapRouteStrokeOpacityHighlight = 0.85;

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

/// Softer accent for itinerary pills and timeline dots; map polylines stay [_legColor].
Color _itineraryAccentColor(Color base) {
  const neutral = Color(0xFF94A3B8);
  return Color.lerp(base, neutral, 0.32)!;
}

/// Text/icon on top of a solid [routeColor] pill (same RGB as map polylines).
Color _onRouteColorInk(Color routeColor) {
  return routeColor.computeLuminance() > 0.62
      ? const Color(0xFF0F172A)
      : Colors.white;
}

/// Shared geometry and typography for itinerary line pills.
const double _kPillRadius = 6;
const EdgeInsets _kPillPadding =
    EdgeInsets.symmetric(horizontal: 7, vertical: 3);
const double _kPillLineFontSize = 13;

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

class _TransitSummaryItem {
  const _TransitSummaryItem({
    required this.modeLabel,
    required this.lineId,
    required this.modeRaw,
    required this.routeColor,
  });

  final String modeLabel;
  final String lineId;
  /// Raw OTP mode for pill tint (trolleybus vs bus, etc.).
  final String modeRaw;
  /// Same color as the map polyline for this line ([_legColor]).
  final Color routeColor;
}

/// Mode icon for itinerary rows and timeline (trolleybus uses bolt, not walk).
Widget _modeIconForMode(String mode, {double size = 18}) {
  final normalized = mode.toUpperCase();
  final IconData icon = switch (normalized) {
    'WALK' => Icons.directions_walk,
    'BICYCLE' => Icons.directions_bike,
    'BIKE' => Icons.directions_bike,
    'CAR' => Icons.directions_car,
    'BUS' => Icons.directions_bus,
    'TROLLEYBUS' => Icons.electric_bolt,
    'TRAM' => Icons.tram,
    'RAIL' => Icons.train,
    'SUBWAY' => Icons.subway,
    _ => Icons.directions_transit,
  };
  return Icon(icon, size: size);
}

List<_TransitSummaryItem> _buildTransitSummary(List<RouteLeg> transitLegs) {
  if (transitLegs.isEmpty) return const [];
  final items = <_TransitSummaryItem>[];
  for (final leg in transitLegs) {
    final modeLabel = _modeLabel(leg.mode);
    final lineId = _lineIdFromRouteId(leg.routeId);
    if (items.isNotEmpty &&
        items.last.modeLabel == modeLabel &&
        items.last.lineId == lineId) {
      continue;
    }
    items.add(
      _TransitSummaryItem(
        modeLabel: modeLabel,
        lineId: lineId,
        modeRaw: leg.mode,
        routeColor: _legColor(leg),
      ),
    );
  }
  return items;
}

/// Drag handle height (Google-maps-style sheet resize).
const double _kRouteSheetDragHandleHeight = 28;

/// Min fraction of the route sheet slot height (peek: handle + back row).
const double _kRouteSheetMinExtent = 0.13;

/// Middle snap position (half of available slot height).
const double _kRouteSheetSnapMidExtent = 0.5;

/// Details: hide scrollable body below this height (peek mode).
const double _kDetailsSheetBodyMinHeight = 172;

/// Top drag area for resizing the route sheet over the map.
class _RouteSheetDragHandle extends StatelessWidget {
  const _RouteSheetDragHandle({
    required this.onDragDelta,
    this.onDragEnd,
    this.allowDrag = true,
  });

  final ValueChanged<double> onDragDelta;
  final VoidCallback? onDragEnd;
  final bool allowDrag;

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.outlineVariant;
    final child = SizedBox(
      height: _kRouteSheetDragHandleHeight,
      width: double.infinity,
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: line.withValues(
              alpha: allowDrag ? 0.85 : 0.45,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
    if (!allowDrag) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => onDragDelta(d.delta.dy),
      onVerticalDragEnd: (_) => onDragEnd?.call(),
      child: child,
    );
  }
}

/// Map route sheet: compact icon-only back (avoids [IconButton] default 48dp min height).
Widget _mapSheetBackIconButton({
  required BuildContext context,
  required VoidCallback onPressed,
}) {
  return Tooltip(
    message: 'Back',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.arrow_back,
            size: 22,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    ),
  );
}

/// Transit line chips with arrows — same pattern as route list and trip details summary.
class _TransitSummaryChipsRow extends StatelessWidget {
  const _TransitSummaryChipsRow({required this.option});

  final RouteOption option;

  @override
  Widget build(BuildContext context) {
    final transitSummary = _buildTransitSummary(_transitLegs(option));
    if (transitSummary.isEmpty) {
      return Text(
        'Walking route',
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: _kRouteStepRunSpacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < transitSummary.length; i++) ...[
          _TransitStepChip(item: transitSummary[i]),
          if (i < transitSummary.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                '→',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Spacing for itinerary cards in [_RouteListPanel].
const double _kRouteStepRunSpacing = 6;

/// Soft elevation for step cards in [_RouteDetailsPanel].
List<BoxShadow> _itineraryStepCardShadow(ColorScheme scheme) => [
      BoxShadow(
        color: scheme.shadow.withValues(alpha: 0.14),
        blurRadius: 10,
        offset: const Offset(0, 3),
      ),
      BoxShadow(
        color: scheme.shadow.withValues(alpha: 0.06),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
    ];
const double _kMetaIconTextGap = 6;
const double _kMetaBulletGap = 8;
const double _kDurationPriceGap = 10;

double _lerpAngleRad(double a, double b, double t) {
  var delta = b - a;
  while (delta > math.pi) {
    delta -= 2 * math.pi;
  }
  while (delta < -math.pi) {
    delta += 2 * math.pi;
  }
  return a + delta * t;
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
    });
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
    final point = LatLng(loc.lat!, loc.lon!);
    setState(() => _userLocation = point);
    // Keep default city framing on Search; move to user only on explicit action.
    if (!_initialUserFocusApplied) _initialUserFocusApplied = true;
  }

  void _centerOnUser() {
    final point = _userLocation;
    if (point == null) {
      unawaited(_initUserLocation(forceFresh: true));
      return;
    }
    _animateCameraTo(center: point, zoom: _userZoom);
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
      showAppSnackBar(
        context,
        const SnackBar(
          content: Text('Could not load route shape. Showing simplified path.'),
        ),
      );
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
      showAppSnackBar(
        context,
        const SnackBar(content: Text('Could not load more routes. Try again.')),
      );
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
  }

  void _onShellMapTap(TapPosition tapPosition, LatLng latLng) {
    final selectionTarget = ref.read(mapSelectionTargetProvider);
    final point =
        '${latLng.latitude.toStringAsFixed(5)},${latLng.longitude.toStringAsFixed(5)}';
    if (selectionTarget != null) {
      ref.read(mapPickedLocationProvider.notifier).state =
          MapPickedLocation(target: selectionTarget, value: point);
      ref.read(mapSelectionTargetProvider.notifier).state = null;
      ref.read(selectedTabProvider.notifier).state = 0;
      final targetLabel = selectionTarget == LocationSelectionTarget.from
          ? 'From'
          : 'To';
      if (!mounted) return;
      showAppSnackBar(
        context,
        SnackBar(
          content: Text('Selected map location for $targetLabel'),
        ),
      );
      return;
    }
    if (!mounted) return;
    showAppSnackBar(
        context,
      SnackBar(content: Text('Selected: $point')),
    );
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
                userAgentPackageName: 'com.example.rotransit_frontend',
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
          Consumer(
            builder: (context, ref, _) {
              final sheet = ref.watch(showMapSheetProvider);
              final tab = ref.watch(selectedTabProvider);
              if (sheet || tab == 0) return const SizedBox.shrink();
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
                      tooltip: 'Rotate map to north',
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
    final extra = context.extraColors;
    return Material(
      color: extra.mapFabBackground,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Theme.of(context).colorScheme.shadow,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: child ??
            Icon(icon, color: Theme.of(context).colorScheme.onPrimary),
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

class _RouteOptionCard extends StatefulWidget {
  const _RouteOptionCard({
    required this.onTap,
    required this.child,
  });

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_RouteOptionCard> createState() => _RouteOptionCardState();
}

class _RouteOptionCardState extends State<_RouteOptionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Card(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: widget.child,
        ),
      ),
    );
  }
}

class _RouteListPanel extends StatelessWidget {
  const _RouteListPanel({
    required this.onReturnToSearch,
    required this.onSheetDragDelta,
    this.allowSheetResize = true,
    required this.options,
    required this.canLoadMore,
    required this.remainingToReveal,
    this.remainingOnServer = 0,
    this.isLoadingMore = false,
    required this.onLoadMore,
    required this.onTapOption,
    required this.scrollController,
  });

  final VoidCallback onReturnToSearch;
  final ValueChanged<double> onSheetDragDelta;
  final bool allowSheetResize;
  final List<RouteOption> options;
  final bool canLoadMore;
  /// Itineraries still hidden locally or in the next fetch batch.
  final int remainingToReveal;
  /// Itineraries not yet fetched from the backend (for “N left” copy).
  final int remainingOnServer;
  final bool isLoadingMore;
  final Future<void> Function() onLoadMore;
  final void Function(RouteOption option, int resultIndex) onTapOption;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final itemCount = options.isEmpty
        ? 1
        : options.length + (canLoadMore ? 1 : 0);
    final fastestMinutes = options.isEmpty
        ? 0
        : options
            .map((o) => (o.durationSeconds / 60).round())
            .reduce(math.min);
    final shortestWalk = options.isEmpty
        ? 0
        : options.map((o) => o.walkDistanceMeters).reduce(math.min);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RouteSheetDragHandle(
          onDragDelta: onSheetDragDelta,
          allowDrag: allowSheetResize,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Row(
            children: [
              _mapSheetBackIconButton(
                context: context,
                onPressed: onReturnToSearch,
              ),
              const Spacer(),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            padding: EdgeInsets.zero,
            itemCount: itemCount,
            itemBuilder: (context, index) {
        if (options.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Center(
              child: Text('Search routes to see options here.'),
            ),
          );
        }
        if (canLoadMore && index == options.length) {
          final batch =
              math.min(kRouteSearchPageSize, remainingToReveal);
          final String label;
          if (isLoadingMore) {
            label = 'Loading…';
          } else if (remainingOnServer > 0) {
            final tripWord = batch == 1 ? 'trip' : 'trips';
            label = batch >= kRouteSearchPageSize
                ? 'Load $kRouteSearchPageSize more ($remainingOnServer left)'
                : 'Load $batch more $tripWord ($remainingOnServer left)';
          } else {
            label = batch >= kRouteSearchPageSize
                ? 'Load next $kRouteSearchPageSize trips'
                : 'Load $batch more ${batch == 1 ? 'trip' : 'trips'}';
          }
          return Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton(
              onPressed: isLoadingMore ? null : () => onLoadMore(),
              child: isLoadingMore
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(label),
            ),
          );
        }
        final item = options[index];
        final start = item.legs.isEmpty
            ? null
            : DateTime.fromMillisecondsSinceEpoch(item.legs.first.startTime);
        final end = item.legs.isEmpty
            ? null
            : DateTime.fromMillisecondsSinceEpoch(item.legs.last.endTime);
        final timeFmt = DateFormat('h:mm a');
        final minutes = (item.durationSeconds / 60).round();
        final isFastest = minutes == fastestMinutes;
        final isShortestWalk = item.walkDistanceMeters == shortestWalk;
        final hasExtraWalk = item.walkDistanceMeters > shortestWalk;
        final scheme = Theme.of(context).colorScheme;
        final extra = context.extraColors;

        return _RouteOptionCard(
          onTap: () => onTapOption(item, index),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            start == null || end == null
                                ? '--'
                                : '${timeFmt.format(start)} - ${timeFmt.format(end)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 21,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 7),
                          _TransitSummaryChipsRow(option: item),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.directions_walk,
                                size: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: _kMetaIconTextGap),
                              Text(
                                formatDistanceForDisplay(
                                  item.walkDistanceMeters.toDouble(),
                                ),
                                style: TextStyle(
                                  color: hasExtraWalk
                                      ? extra.walkExtraColor
                                      : isShortestWalk
                                          ? extra.walkBestColor
                                          : scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w400,
                                  fontSize: 13,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: _kMetaBulletGap,
                                ),
                                child: Text(
                                  '•',
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.42),
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.sync_alt,
                                size: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: _kMetaIconTextGap),
                              Text(
                                '${item.transfers} transfer${item.transfers == 1 ? '' : 's'}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: extra.durationBadgeBackground,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            child: Text(
                              '($minutes min)',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 11.5,
                                color: isFastest
                                    ? extra.durationBestColor
                                    : scheme.onSurfaceVariant
                                        .withValues(alpha: 0.78),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: _kDurationPriceGap),
                        Text(
                          '${item.estimatedPriceLei} lei',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
            },
          ),
        ),
      ],
    );
  }
}

class _RouteDetailsPanel extends ConsumerWidget {
  const _RouteDetailsPanel({
    required this.cityId,
    required this.option,
    required this.sheetHeight,
    required this.onSheetDragDelta,
    this.onSheetDragEnd,
    required this.highlightedLegIndex,
    required this.onLegHighlightChanged,
    required this.onBack,
    this.showSaveToFavorites = true,
  });

  final String cityId;
  final RouteOption option;
  final double sheetHeight;
  final ValueChanged<double> onSheetDragDelta;
  final VoidCallback? onSheetDragEnd;
  final int highlightedLegIndex;
  final ValueChanged<int> onLegHighlightChanged;
  final VoidCallback onBack;
  final bool showSaveToFavorites;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeFmt = DateFormat('h:mm a');
    final scheme = Theme.of(context).colorScheme;
    final legs = option.legs;
    final safeHighlight = legs.isEmpty
        ? 0
        : math.min(legs.length - 1, math.max(0, highlightedLegIndex));
    final showItineraryBody = sheetHeight >= _kDetailsSheetBodyMinHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RouteSheetDragHandle(
          onDragDelta: onSheetDragDelta,
          onDragEnd: onSheetDragEnd,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 16, 8),
          child: Row(
            children: [
              _mapSheetBackIconButton(context: context, onPressed: onBack),
            ],
          ),
        ),
        if (showItineraryBody)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${(option.durationSeconds / 60).round()} min',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _TransitSummaryChipsRow(option: option),
                    const SizedBox(height: 8),
                    Text(
                      '${option.transfers} transfer${option.transfers == 1 ? '' : 's'} • ${option.estimatedPriceLei} lei',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.92),
                      ),
                    ),
                    if (option.fareRule.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        option.fareRule,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (showSaveToFavorites) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonal(
                          onPressed: () async {
                            await ref
                                .read(saveRouteControllerProvider)
                                .save(cityId: cityId, option: option);
                            if (context.mounted) {
                              showAppSnackBar(
        context,
                                const SnackBar(
                                  content: Text('Added to favorites'),
                                ),
                              );
                            }
                          },
                          child: const Text('Add to favorites'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Steps',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < legs.length; i++)
                      _RouteTimelineLegRow(
                        leg: legs[i],
                        isHighlighted: i == safeHighlight,
                        timeFmt: timeFmt,
                        onTap: () => onLegHighlightChanged(i),
                      ),
                  ],
                ),
              ),
            )
        else
          const Spacer(),
      ],
    );
  }
}

/// Primary title for a step: mode name + line pill using the same [Color] as the map leg.
Widget _transitLineTitleRow(RouteLeg leg, ColorScheme scheme) {
  final lineId = _lineIdFromRouteId(leg.routeId);
  if (_isTransitLeg(leg) && lineId.isNotEmpty) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        Text(
          _modeLabel(leg.mode),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: scheme.onSurface,
          ),
        ),
        _RouteLineNumberPill(lineId: lineId, routeColor: _legColor(leg)),
      ],
    );
  }
  return Text(
    _legBadgeLabel(leg),
    style: TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 16,
      color: scheme.onSurface,
    ),
  );
}

class _RouteTimelineLegRow extends StatelessWidget {
  const _RouteTimelineLegRow({
    required this.leg,
    required this.isHighlighted,
    required this.timeFmt,
    required this.onTap,
  });

  final RouteLeg leg;
  final bool isHighlighted;
  final DateFormat timeFmt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final variant = scheme.onSurfaceVariant;
    final start = DateTime.fromMillisecondsSinceEpoch(leg.startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(leg.endTime);
    final meta =
        '${timeFmt.format(start)} – ${timeFmt.format(end)}   •   ${formatDistanceForDisplay(leg.distance)}';
    final cardRadius = BorderRadius.circular(12);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isHighlighted
              ? scheme.primaryContainer.withValues(alpha: 0.32)
              : scheme.surface,
          borderRadius: cardRadius,
          border: isHighlighted
              ? Border.all(
                  color: scheme.primary.withValues(alpha: 0.28),
                  width: 1,
                )
              : null,
          boxShadow: _itineraryStepCardShadow(scheme),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: cardRadius,
          child: InkWell(
            onTap: onTap,
            borderRadius: cardRadius,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '●',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      color: isHighlighted
                          ? scheme.primary
                          : (_isTransitLeg(leg)
                              ? _itineraryAccentColor(_legColor(leg))
                              : variant.withValues(alpha: 0.65)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _modeIconForMode(leg.mode, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _transitLineTitleRow(leg, scheme),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${leg.fromName} → ${leg.toName}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: variant.withValues(alpha: 0.88),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: variant.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Line number badge: solid [routeColor] matches map polyline for that leg.
class _RouteLineNumberPill extends StatelessWidget {
  const _RouteLineNumberPill({
    required this.lineId,
    required this.routeColor,
  });

  final String lineId;
  final Color routeColor;

  @override
  Widget build(BuildContext context) {
    final c = _itineraryAccentColor(routeColor);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(_kPillRadius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: _kPillPadding,
        child: Text(
          lineId,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: _kPillLineFontSize,
            letterSpacing: 0.2,
            color: _onRouteColorInk(c),
          ),
        ),
      ),
    );
  }
}

class _TransitStepChip extends StatelessWidget {
  const _TransitStepChip({required this.item});

  final _TransitSummaryItem item;

  @override
  Widget build(BuildContext context) {
    final variant = Theme.of(context).colorScheme.onSurfaceVariant;
    final c = item.routeColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.modeLabel,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: variant,
          ),
        ),
        if (item.lineId.isNotEmpty) ...[
          const SizedBox(width: 6),
          _RouteLineNumberPill(lineId: item.lineId, routeColor: c),
        ],
      ],
    );
  }
}
