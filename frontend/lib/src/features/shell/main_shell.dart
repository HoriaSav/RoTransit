import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotransit_frontend/l10n/app_localizations.dart';

import '../map/presentation/map_tab.dart';
import '../saved/presentation/bus_tab.dart';
import '../saved/presentation/favorites_tab.dart';
import '../search/presentation/search_tab.dart';
import '../settings/presentation/settings_tab.dart';
import 'shell_floating_nav.dart';
import 'shell_header.dart';
import 'shell_layout.dart';
import '../../core/theme/app_extra_colors.dart';
import '../../core/ui/app_snackbar.dart';
import 'shell_back_navigation.dart';
import 'state/navigation_provider.dart';

/// Root shell: hosts tab UI and global navigation.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  static const _exitConfirmWindow = Duration(seconds: 2);
  DateTime? _lastBackPressForExit;

  void _onSystemBackInvoked(bool didPop) {
    if (didPop) return;

    if (tryConsumeAppBack(ref, context)) {
      _lastBackPressForExit = null;
      return;
    }

    final now = DateTime.now();
    final last = _lastBackPressForExit;
    if (last != null && now.difference(last) <= _exitConfirmWindow) {
      SystemNavigator.pop();
      return;
    }

    _lastBackPressForExit = now;
    final message = AppLocalizations.of(context)!.pressBackAgainToExit;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    showAppSnackBar(
      context,
      SnackBar(
        content: Text(message),
        duration: _exitConfirmWindow,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final extra = context.extraColors;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onSystemBackInvoked(didPop),
      child: Scaffold(
      backgroundColor: extra.shellFrame,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ShellBrandingHeader(),
          const Expanded(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              fit: StackFit.expand,
              children: [
                _ShellMapLayer(),
                _SearchGradientOverlay(),
                _ShellTabPages(),
                _ShellFloatingNavBarSlot(),
              ],
            ),
          ),
          ColoredBox(
            color: extra.shellFrame,
            child: SizedBox(height: bottomInset),
          ),
        ],
      ),
      ),
    );
  }
}

class _ShellMapLayer extends ConsumerWidget {
  const _ShellMapLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(selectedTabProvider);
    final mapOverlayVisible = ref.watch(mapShellOverlayVisibleProvider);
    final mapSurfaceActive = index == 0 || mapOverlayVisible;

    return Positioned.fill(
      child: TickerMode(
        enabled: mapSurfaceActive,
        child: const MapTab(),
      ),
    );
  }
}

class _SearchGradientOverlay extends ConsumerWidget {
  const _SearchGradientOverlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(selectedTabProvider);
    final mapOverlayVisible = ref.watch(mapShellOverlayVisibleProvider);
    if (index != 0 || mapOverlayVisible) {
      return const SizedBox.shrink();
    }
    final extra = context.extraColors;
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                extra.searchGradientTop,
                extra.searchGradientMid,
                extra.searchGradientBottom,
              ],
              stops: const [0.0, 0.38, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellTabPages extends ConsumerWidget {
  const _ShellTabPages();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(selectedTabProvider);
    final mapOverlayVisible = ref.watch(mapShellOverlayVisibleProvider);
    final pages = [
      IgnorePointer(
        ignoring: mapOverlayVisible,
        child: Opacity(
          opacity: mapOverlayVisible ? 0 : 1,
          child: const SearchTab(),
        ),
      ),
      const BusTab(),
      IgnorePointer(
        ignoring: mapOverlayVisible,
        child: Opacity(
          opacity: mapOverlayVisible ? 0 : 1,
          child: const FavoritesTab(),
        ),
      ),
      const SettingsTab(),
    ];

    return Positioned.fill(
      child: IndexedStack(index: index, children: pages),
    );
  }
}

class _ShellFloatingNavBarSlot extends ConsumerWidget {
  const _ShellFloatingNavBarSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(selectedTabProvider);

    return Positioned(
      left: kShellFloatingNavHorizontalMargin,
      right: kShellFloatingNavHorizontalMargin,
      bottom: kShellFloatingNavBottomMargin,
      child: ShellFloatingNavBar(
        selectedIndex: index,
        onDestinationSelected: (value) {
          final current = ref.read(selectedTabProvider);
          if (value != 0) {
            ref.read(showMapSheetProvider.notifier).state = false;
            ref.read(mapSelectionTargetProvider.notifier).state = null;
            ref.read(routeMapOverlaySuppressedProvider.notifier).state = true;
          } else if (value == 0 && current != 0) {
            ref.read(showMapSheetProvider.notifier).state = false;
            ref.read(mapSelectionTargetProvider.notifier).state = null;
            ref.read(routeMapOverlaySuppressedProvider.notifier).state = true;
            if (ref.read(searchMapStateProvider).openedFromSavedFavorite) {
              ref
                  .read(searchMapStateProvider.notifier)
                  .closeFavoriteMapPreview();
            }
          }
          ref.read(selectedTabProvider.notifier).state = value;
        },
      ),
    );
  }
}
