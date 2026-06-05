import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/navigation_provider.dart';

void _signalRouteSheetExpandFull(WidgetRef ref) {
  ref.read(routeSheetExpandFullProvider.notifier).state++;
}

/// Handles Android back / system back when possible.
///
/// Returns `true` if navigation state was consumed (caller should not exit).
bool tryConsumeAppBack(WidgetRef ref, BuildContext context) {
  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
    return true;
  }

  if (ref.read(mapSelectionTargetProvider) != null) {
    ref.read(mapSelectionTargetProvider.notifier).state = null;
    ref.read(mapPickedLocationProvider.notifier).state = null;
    return true;
  }

  if (!ref.read(showMapSheetProvider)) {
    return false;
  }

  final mapState = ref.read(searchMapStateProvider);
  final ctrl = ref.read(searchMapStateProvider.notifier);

  if (mapState.mode == SheetMode.details && mapState.selectedOption != null) {
    _signalRouteSheetExpandFull(ref);
    if (mapState.openedFromSavedFavorite) {
      ref.read(showMapSheetProvider.notifier).state = false;
      ctrl.closeFavoriteMapPreview();
      ref.read(selectedTabProvider.notifier).state = 2;
    } else {
      ctrl.backToList();
    }
    return true;
  }

  _signalRouteSheetExpandFull(ref);
  ref.read(showMapSheetProvider.notifier).state = false;
  ref.read(routeMapOverlaySuppressedProvider.notifier).state = true;
  ctrl.clearRouteSheetSelection();
  return true;
}
