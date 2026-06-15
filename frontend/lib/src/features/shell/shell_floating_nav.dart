import 'package:flutter/material.dart';
import 'package:rotransit_frontend/l10n/app_localizations.dart';

import '../../core/theme/accent_badge_style.dart';
import '../../core/theme/app_extra_colors.dart';
import 'shell_layout.dart';

/// Compact floating tab bar (fixed height). [NavigationBar] ignores small heights
/// in practice due to its internal M3 layout.
class ShellFloatingNavBar extends StatelessWidget {
  const ShellFloatingNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final extra = context.extraColors;
    final isLight = scheme.brightness == Brightness.light;
    return Material(
      color: extra.floatingNavBackground,
      elevation: isLight ? 1 : 0,
      shadowColor: isLight ? const Color(0x1A0A3E96) : scheme.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: isLight
            ? BorderSide(color: extra.recentTileBorder)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: kShellFloatingNavHeight,
        child: Row(
          children: [
            _Slot(
              selected: selectedIndex == 0,
              icon: Icons.search_outlined,
              selectedIcon: Icons.search,
              label: l10n.navSearch,
              onTap: () => onDestinationSelected(0),
            ),
            _Slot(
              selected: selectedIndex == 1,
              icon: Icons.directions_bus_outlined,
              selectedIcon: Icons.directions_bus,
              label: l10n.navBus,
              onTap: () => onDestinationSelected(1),
            ),
            _Slot(
              selected: selectedIndex == 2,
              icon: Icons.favorite_border_rounded,
              selectedIcon: Icons.favorite_rounded,
              label: l10n.navFavorites,
              onTap: () => onDestinationSelected(2),
            ),
            _Slot(
              selected: selectedIndex == 3,
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: l10n.navSettings,
              onTap: () => onDestinationSelected(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extra = context.extraColors;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 34,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (selected)
                      Container(
                        width: 50,
                        height: 30,
                        decoration: BoxDecoration(
                          color: extra.floatingNavIndicator,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    Icon(
                      selected ? selectedIcon : icon,
                      size: 24,
                      color: selected
                          ? selectedShellAccentColor(context)
                          : scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: 0.12,
                  height: 1,
                  color: selected
                      ? selectedShellAccentColor(context)
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
