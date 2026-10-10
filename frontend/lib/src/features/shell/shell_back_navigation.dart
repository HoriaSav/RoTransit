import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/navigation_provider.dart';

/// Handles Android back / system back when possible.
///
/// Returns `true` if navigation state was consumed (caller should not exit).
bool tryConsumeAppBack(WidgetRef ref, BuildContext context) {
  if (ref.read(settingsOpenProvider)) {
    ref.read(settingsOpenProvider.notifier).state = false;
    return true;
  }

  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
    return true;
  }

  return false;
}
