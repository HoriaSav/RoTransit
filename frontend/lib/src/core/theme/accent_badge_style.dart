import 'package:flutter/material.dart';

import 'app_extra_colors.dart';

typedef AccentBadgeColors = ({Color background, Color foreground});

AccentBadgeColors accentBadgeColors(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final extra = context.extraColors;
  if (scheme.brightness == Brightness.dark) {
    return (
      background: scheme.primaryContainer,
      foreground: scheme.onPrimaryContainer,
    );
  }
  return (
    background: extra.floatingNavIndicator,
    foreground: scheme.primary,
  );
}

/// Accent for selected shell nav items and similar chips.
Color selectedShellAccentColor(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return scheme.brightness == Brightness.dark
      ? scheme.onPrimaryContainer
      : scheme.primary;
}

/// Secondary icons on muted pill backgrounds (schedule chips, swap buttons).
Color accentIconColor(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return scheme.brightness == Brightness.dark
      ? scheme.onPrimaryContainer
      : scheme.primary;
}

/// Chevrons and other de-emphasized chrome that should stay readable in dark mode.
Color mutedChromeColor(BuildContext context, {double lightAlpha = 0.7}) {
  final scheme = Theme.of(context).colorScheme;
  if (scheme.brightness == Brightness.dark) {
    return scheme.onSurfaceVariant;
  }
  return scheme.onSurfaceVariant.withValues(alpha: lightAlpha);
}
