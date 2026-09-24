part of 'map_tab.dart';

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

String _legLabel(String mode, AppLocalizations l10n) {
  return l10n.transitModeLabel(mode);
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

String _legBadgeLabel(RouteLeg leg, AppLocalizations l10n) {
  final mode = _legLabel(leg.mode, l10n);
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

List<_TransitSummaryItem> _buildTransitSummary(
  List<RouteLeg> transitLegs,
  AppLocalizations l10n,
) {
  if (transitLegs.isEmpty) return const [];
  final items = <_TransitSummaryItem>[];
  for (final leg in transitLegs) {
    final modeLabel = _legLabel(leg.mode, l10n);
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
  final l10n = AppLocalizations.of(context);
  return Tooltip(
    message: l10n.commonBack,
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
    final l10n = AppLocalizations.of(context);
    final transitSummary = _buildTransitSummary(_transitLegs(option), l10n);
    if (transitSummary.isEmpty) {
      return Text(
        l10n.mapWalkingRoute,
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

