part of 'map_tab.dart';

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

