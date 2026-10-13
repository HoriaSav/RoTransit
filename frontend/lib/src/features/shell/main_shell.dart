import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rotransit/l10n/app_localizations.dart';

import '../map/presentation/map_tab.dart';
import '../saved/presentation/bus_tab.dart';
import '../saved/presentation/favorites_tab.dart';
import '../map/presentation/map_companion_tab.dart';
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
    final message = AppLocalizations.of(context).pressBackAgainToExit;
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
    final selectedTab = ref.watch(selectedTabProvider);
    const busTabIndex = 1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onSystemBackInvoked(didPop),
      child: Scaffold(
      backgroundColor: extra.shellFrame,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (selectedTab != busTabIndex && selectedTab != 0 &&
              !ref.watch(settingsOpenProvider))
            const ShellBrandingHeader(),
          const Expanded(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              fit: StackFit.expand,
              children: [
                _ShellMapLayer(),
                _ShellTabPages(),
                _ShellFloatingNavBarSlot(),
                _SettingsOverlay(),
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

    return Positioned.fill(
      child: TickerMode(
        enabled: index == 0,
        child: const MapTab(),
      ),
    );
  }
}

class _ShellTabPages extends ConsumerWidget {
  const _ShellTabPages();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(selectedTabProvider);
    const pages = [
      // Map companion chrome (search stations). Map stays interactive underneath.
      MapCompanionTab(),
      BusTab(),
      FavoritesTab(),
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
    final settingsOpen = ref.watch(settingsOpenProvider);
    if (settingsOpen) return const SizedBox.shrink();

    return Positioned(
      left: kShellFloatingNavHorizontalMargin,
      right: kShellFloatingNavHorizontalMargin,
      bottom: kShellFloatingNavBottomMargin,
      child: ShellFloatingNavBar(
        selectedIndex: index,
        onDestinationSelected: (value) {
          ref.read(selectedTabProvider.notifier).state = value;
        },
      ),
    );
  }
}

class _SettingsOverlay extends ConsumerWidget {
  const _SettingsOverlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(settingsOpenProvider)) {
      return const SizedBox.shrink();
    }
    final extra = context.extraColors;
    return Positioned.fill(
      child: Material(
        color: extra.tabBackground,
        child: const SettingsTab(showBackButton: true),
      ),
    );
  }
}
