import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rotransit/l10n/app_localizations.dart';

import '../errors/app_user_message.dart';
import 'app_snackbar.dart';

void showUserMessage(
  BuildContext context,
  AppUserMessage message, {
  VoidCallback? onAction,
}) {
  if (!message.visible) {
    if (kDebugMode && message.debugDetail != null) {
      debugPrint('[UserFeedback suppressed] ${message.debugDetail}');
    }
    return;
  }

  final l10n = AppLocalizations.of(context);
  final text = message.resolveText(l10n);
  if (text.trim().isEmpty) return;

  showAppSnackBar(
    context,
    SnackBar(
      content: Text(text),
      duration: message.duration ?? _defaultDuration(message.severity),
      action: message.actionLabel != null && onAction != null
          ? SnackBarAction(
              label: message.actionLabel!,
              onPressed: onAction,
            )
          : null,
    ),
  );
}

void showUserError(BuildContext context, Object error) {
  showUserMessage(context, UserMessageResolver.fromError(error));
}

Duration _defaultDuration(UserMessageSeverity severity) {
  return switch (severity) {
    UserMessageSeverity.success => const Duration(seconds: 3),
    UserMessageSeverity.error => const Duration(seconds: 5),
    _ => const Duration(seconds: 4),
  };
}
