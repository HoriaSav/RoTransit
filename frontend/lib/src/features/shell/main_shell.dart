import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../map/presentation/map_tab.dart';
import '../saved/presentation/bus_tab.dart';
import '../saved/presentation/favorites_tab.dart';
import '../search/presentation/search_tab.dart';
import '../settings/presentation/settings_tab.dart';
import 'shell_floating_nav.dart';
import 'shell_header.dart';
import 'shell_layout.dart';
import 'state/navigation_provider.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  static const Color _frameFooterColor = Color(0xFFF2F2F2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(selectedTabProvider);
    final mapOverlayVisible = ref.watch(mapShellOverlayVisibleProvider);
    final showSharedMapLayer = index == 0 || mapOverlayVisible;
    final pages = [
      mapOverlayVisible ? const SizedBox.shrink() : const SearchTab(),
      const BusTab(),
      const FavoritesTab(),
      const SettingsTab(),
    ];

    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _frameFooterColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ShellBrandingHeader(),
          Expanded(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              fit: StackFit.expand,
              children: [
                if (showSharedMapLayer)
                  const Positioned.fill(
                    child: MapTab(),
                  ),
                if (index == 0 && !mapOverlayVisible)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.30),
                              Colors.black.withValues(alpha: 0.16),
                              const Color(0xFFF2F2F2).withValues(alpha: 0.90),
                            ],
                            stops: const [0.0, 0.38, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: IndexedStack(index: index, children: pages),
                ),
                Positioned(
                  left: kShellFloatingNavHorizontalMargin,
                  right: kShellFloatingNavHorizontalMargin,
                  bottom: kShellFloatingNavBottomMargin,
                  child: ShellFloatingNavBar(
                    selectedIndex: index,
                    onDestinationSelected: (value) {
                      if (value != 0) {
                        ref.read(showMapSheetProvider.notifier).state = false;
                        ref.read(mapSelectionTargetProvider.notifier).state =
                            null;
                        ref
                            .read(routeMapOverlaySuppressedProvider.notifier)
                            .state = true;
                      }
                      ref.read(selectedTabProvider.notifier).state = value;
                    },
                  ),
                ),
              ],
            ),
          ),
          ColoredBox(
            color: _frameFooterColor,
            child: SizedBox(height: bottomInset),
          ),
        ],
      ),
    );
  }
}
