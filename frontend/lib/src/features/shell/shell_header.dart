import 'package:flutter/material.dart';

import 'shell_layout.dart';

/// Solid top bar for the shell “frame” (content sits below this, not underneath it).
class ShellBrandingHeader extends StatelessWidget {
  const ShellBrandingHeader({super.key});

  static const Color brandBlue = Color(0xFF0A3E96);

  /// Light cream frame color (matches reference-style header strip).
  static const Color frameBackground = Color(0xFFF5F3EF);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Material(
        color: frameBackground,
        elevation: 0,
        child: SizedBox(
          height: kShellHeaderBarHeight,
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Image.asset(
                  'assets/icons/bus_noBG.png',
                  height: 36,
                  width: 36,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.directions_bus_rounded,
                    size: 32,
                    color: brandBlue,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'RoTransit',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: brandBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
