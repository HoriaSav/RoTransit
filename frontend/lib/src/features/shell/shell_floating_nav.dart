import 'package:flutter/material.dart';

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
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      elevation: 0,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: kShellFloatingNavHeight,
        child: Row(
          children: [
            _Slot(
              selected: selectedIndex == 0,
              icon: Icons.search_outlined,
              selectedIcon: Icons.search,
              label: 'Search',
              onTap: () => onDestinationSelected(0),
            ),
            _Slot(
              selected: selectedIndex == 1,
              icon: Icons.directions_bus_outlined,
              selectedIcon: Icons.directions_bus,
              label: 'Bus',
              onTap: () => onDestinationSelected(1),
            ),
            _Slot(
              selected: selectedIndex == 2,
              icon: Icons.favorite_border_rounded,
              selectedIcon: Icons.favorite_rounded,
              label: 'Favorites',
              onTap: () => onDestinationSelected(2),
            ),
            _Slot(
              selected: selectedIndex == 3,
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: 'Settings',
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

  static const Color _brandBlue = Color(0xFF0A3E96);
  static const Color _muted = Color(0xFF6E7480);
  static const Color _indicator = Color(0xFFC8F7E5);

  @override
  Widget build(BuildContext context) {
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
                          color: _indicator,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    Icon(
                      selected ? selectedIcon : icon,
                      size: 24,
                      color: selected ? _brandBlue : _muted,
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
                  color: selected ? _brandBlue : _muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
