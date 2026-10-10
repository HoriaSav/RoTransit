import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:rotransit/l10n/app_localizations.dart';

import 'app_user_message_l10n.dart';

enum UserMessageSeverity { info, success, warning, error }

enum AppUserMessageId {
  serverUnreachable,
  serverTimeout,
  unexpectedError,
}

/// A message that may be shown in a SnackBar. [visible] false = never toast.
class AppUserMessage {
  const AppUserMessage({
    this.id,
    this.text,
    this.visible = true,
    this.severity = UserMessageSeverity.info,
    this.duration,
    this.actionLabel,
    this.debugDetail,
  });

  final AppUserMessageId? id;
  final String? text;
  final bool visible;
  final UserMessageSeverity severity;
  final Duration? duration;
  final String? actionLabel;
  final String? debugDetail;

  static const suppressed = AppUserMessage(
    text: '',
    visible: false,
  );

  static AppUserMessage custom(
    String text, {
    UserMessageSeverity severity = UserMessageSeverity.info,
    Duration? duration,
    String? actionLabel,
  }) {
    return AppUserMessage(
      text: text,
      severity: severity,
      duration: duration,
      actionLabel: actionLabel,
    );
  }

  static const serverUnreachable = AppUserMessage(
    id: AppUserMessageId.serverUnreachable,
    severity: UserMessageSeverity.error,
  );

  static const serverTimeout = AppUserMessage(
    id: AppUserMessageId.serverTimeout,
    severity: UserMessageSeverity.error,
  );

  static const unexpectedError = AppUserMessage(
    id: AppUserMessageId.unexpectedError,
    severity: UserMessageSeverity.error,
  );

  static AppUserMessage mapLocationPicked(String target) => AppUserMessage(
        text: '',
        visible: false,
        debugDetail: 'Map location picked for $target',
      );

  String resolveText([AppLocalizations? l10n]) {
    final trimmed = text?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    if (l10n != null && id != null) return l10n.localizeUserMessage(id!);
    return _englishFallback(id);
  }
}

class UserMessageResolver {
  const UserMessageResolver._();

  static AppUserMessage fromError(Object error) {
    if (error is DioException) return fromDio(error);
    if (kDebugMode) {
      debugPrint('[UserMessageResolver] $error');
    }
    return AppUserMessages.unexpectedError;
  }

  static AppUserMessage fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return AppUserMessages.serverTimeout;
      case DioExceptionType.connectionError:
        return AppUserMessages.serverUnreachable;
      case DioExceptionType.badCertificate:
        return AppUserMessages.serverUnreachable;
      case DioExceptionType.cancel:
        return AppUserMessages.suppressed;
      default:
        break;
    }

    final status = error.response?.statusCode;
    final backendCode = _backendErrorCode(error);
    if (kDebugMode) {
      debugPrint(
        '[Dio] status=$status code=$backendCode path=${error.requestOptions.path}',
      );
    }

    // The only API call left is the city list, so keep the copy generic:
    // a 4xx is our bug, anything else means the server is not usable.
    if (status != null && status >= 400 && status < 500) {
      return AppUserMessages.unexpectedError;
    }
    return AppUserMessages.serverUnreachable;
  }

  static String? _backendErrorCode(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final code = data['code'];
      if (code is String && code.trim().isNotEmpty) return code.trim();
    }
    return null;
  }
}

typedef AppUserMessages = AppUserMessage;

String userFacingMessageForDioFailure(Object error) {
  return UserMessageResolver.fromError(error).resolveText();
}

String _englishFallback(AppUserMessageId? id) {
  return switch (id) {
    AppUserMessageId.serverUnreachable =>
      'Cannot reach the server. Check your connection and try again.',
    AppUserMessageId.serverTimeout =>
      'The server took too long to respond. Try again.',
    AppUserMessageId.unexpectedError =>
      'Something went wrong. Please try again.',
    null => '',
  };
}
