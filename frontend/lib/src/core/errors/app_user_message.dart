import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:rotransit_frontend/l10n/app_localizations.dart';

import 'app_user_message_l10n.dart';

enum UserMessageSeverity { info, success, warning, error }

enum AppUserMessageId {
  completeSearchFields,
  selectStationsFromPicker,
  cityContextUnavailable,
  searchRequiresInternet,
  noRoutesFound,
  serverUnreachable,
  serverTimeout,
  routingUnavailable,
  invalidSearchParams,
  cityNotFound,
  unexpectedError,
  routeShapeSimplified,
  loadMoreRoutesFailed,
  addedToFavorites,
  mapPickHint,
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

  static const completeSearchFields = AppUserMessage(
    id: AppUserMessageId.completeSearchFields,
    severity: UserMessageSeverity.warning,
  );

  static const selectStationsFromPicker = AppUserMessage(
    id: AppUserMessageId.selectStationsFromPicker,
    severity: UserMessageSeverity.warning,
  );

  static const cityContextUnavailable = AppUserMessage(
    id: AppUserMessageId.cityContextUnavailable,
    severity: UserMessageSeverity.error,
  );

  static const searchRequiresInternet = AppUserMessage(
    id: AppUserMessageId.searchRequiresInternet,
    severity: UserMessageSeverity.warning,
  );

  static const noRoutesFound = AppUserMessage(
    id: AppUserMessageId.noRoutesFound,
    severity: UserMessageSeverity.info,
  );

  static const serverUnreachable = AppUserMessage(
    id: AppUserMessageId.serverUnreachable,
    severity: UserMessageSeverity.error,
  );

  static const serverTimeout = AppUserMessage(
    id: AppUserMessageId.serverTimeout,
    severity: UserMessageSeverity.error,
  );

  static const routingUnavailable = AppUserMessage(
    id: AppUserMessageId.routingUnavailable,
    severity: UserMessageSeverity.error,
  );

  static const invalidSearchParams = AppUserMessage(
    id: AppUserMessageId.invalidSearchParams,
    severity: UserMessageSeverity.warning,
  );

  static const cityNotFound = AppUserMessage(
    id: AppUserMessageId.cityNotFound,
    severity: UserMessageSeverity.error,
  );

  static const unexpectedError = AppUserMessage(
    id: AppUserMessageId.unexpectedError,
    severity: UserMessageSeverity.error,
  );

  static const routeShapeSimplified = AppUserMessage(
    id: AppUserMessageId.routeShapeSimplified,
    severity: UserMessageSeverity.warning,
  );

  static const loadMoreRoutesFailed = AppUserMessage(
    id: AppUserMessageId.loadMoreRoutesFailed,
    severity: UserMessageSeverity.error,
  );

  static const addedToFavorites = AppUserMessage(
    id: AppUserMessageId.addedToFavorites,
    severity: UserMessageSeverity.success,
  );

  static AppUserMessage mapCoordinateTap(String coordinates) => AppUserMessage(
        text: '',
        visible: false,
        debugDetail: 'Map tap ignored: $coordinates',
      );

  static AppUserMessage mapLocationPicked(String target) => AppUserMessage(
        text: '',
        visible: false,
        debugDetail: 'Map location picked for $target',
      );

  static const mapPickHint = AppUserMessage(
    id: AppUserMessageId.mapPickHint,
    visible: false,
    debugDetail: 'Map pick mode started',
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

    return switch (status) {
      400 => AppUserMessages.invalidSearchParams,
      404 => AppUserMessages.cityNotFound,
      502 => AppUserMessages.routingUnavailable,
      503 => AppUserMessages.routingUnavailable,
      null => AppUserMessages.serverUnreachable,
      _ => AppUserMessages.serverUnreachable,
    };
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
    AppUserMessageId.completeSearchFields =>
      'Please fill in From, To, date, and time.',
    AppUserMessageId.selectStationsFromPicker =>
      'Select both stations from the list or map.',
    AppUserMessageId.cityContextUnavailable =>
      'Could not load your city. Try again later.',
    AppUserMessageId.searchRequiresInternet =>
      'Route search needs an internet connection.',
    AppUserMessageId.noRoutesFound => 'No routes found for this trip.',
    AppUserMessageId.serverUnreachable =>
      'Cannot reach the server. Check your connection and try again.',
    AppUserMessageId.serverTimeout =>
      'The server took too long to respond. Try again.',
    AppUserMessageId.routingUnavailable =>
      'Trip planning is temporarily unavailable.',
    AppUserMessageId.invalidSearchParams =>
      'Check your stations, date, and time.',
    AppUserMessageId.cityNotFound => 'This city is not available yet.',
    AppUserMessageId.unexpectedError =>
      'Something went wrong. Please try again.',
    AppUserMessageId.routeShapeSimplified =>
      'Could not load full route details. Showing a simplified view.',
    AppUserMessageId.loadMoreRoutesFailed =>
      'Could not load more routes. Try again.',
    AppUserMessageId.addedToFavorites => 'Added to favorites',
    AppUserMessageId.mapPickHint => '',
    null => '',
  };
}
