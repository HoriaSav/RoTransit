import 'package:flutter/material.dart';

/// Height of the shell branding bar below the status bar.
const double kShellHeaderBarHeight = 58;

/// Height of the custom floating nav pill in [ShellFloatingNavBar] (~120% of prior 48dp).
const double kShellFloatingNavHeight = 58;

/// Gap between the bottom of the middle frame and the floating nav pill, and
/// between the nav and the system home-indicator strip. Reused for map route
/// sheet margins so header↔sheet and sheet↔nav match that spacing.
const double kShellFloatingNavBottomMargin = 12;

/// Horizontal inset for the floating nav and the map route sheet (aligned).
const double kShellFloatingNavHorizontalMargin = 16;

/// Bottom inset for the map sheet [Stack] slot: clears the nav plus [kShellFloatingNavBottomMargin] above it (same as nav↔home strip).
double mapSheetStackBottomInset(BuildContext context) {
  return shellBottomContentPadding(context) + kShellFloatingNavBottomMargin;
}

/// Bottom padding for scrollable tab content so it clears the floating nav inside the frame.
double shellBottomContentPadding(BuildContext context) {
  return kShellFloatingNavBottomMargin + kShellFloatingNavHeight;
}
