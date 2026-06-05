import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/branding/operator_branding.dart';
import '../../core/theme/app_extra_colors.dart';
import 'state/navigation_provider.dart';
import 'shell_layout.dart';

/// RATBV asset is wide; size by height so text stays readable in the header.
const _kOperatorLogoHeight = 50.0;
const _kOperatorLogoMaxWidth = 140.0;

/// Solid top bar for the shell “frame” (content sits below this, not underneath it).
class ShellBrandingHeader extends ConsumerWidget {
  const ShellBrandingHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final extra = context.extraColors;
    final cityState = ref.watch(searchMapStateProvider);
    final operatorLogo = operatorLogoAssetForCity(
      cityId: cityState.cityId,
      cityName: cityState.cityName,
    );

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
                Image.asset(
                  'assets/icons/bus_noBG.png',
                  height: 36,
                  width: 36,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.directions_bus_rounded,
                    size: 32,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'RoTransit',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: scheme.primary,
                  ),
                ),
                const Spacer(),
                if (operatorLogo != null)
                  Image.asset(
                    operatorLogo,
                    height: _kOperatorLogoHeight,
                    width: _kOperatorLogoMaxWidth,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerRight,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
