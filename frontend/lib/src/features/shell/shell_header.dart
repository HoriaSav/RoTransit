import 'package:flutter/material.dart';
import 'package:rotransit/l10n/app_localizations.dart';

import '../../core/theme/app_extra_colors.dart';
import 'shell_layout.dart';

/// Solid top bar for the shell “frame” (content sits below this, not underneath it).
class ShellBrandingHeader extends StatelessWidget {
  const ShellBrandingHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extra = context.extraColors;
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      bottom: false,
      child: Material(
        color: extra.shellHeader,
        elevation: 0,
        child: SizedBox(
          height: kShellHeaderBarHeight,
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/app_icon.png',
                    height: 36,
                    width: 36,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.directions_bus_rounded,
                      size: 32,
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.appTitle,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: scheme.primary,
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
