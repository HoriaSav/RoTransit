import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';

export '../errors/app_user_message.dart' show userFacingMessageForDioFailure;

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        options.extra['startedAtMs'] = DateTime.now().millisecondsSinceEpoch;
        if (kDebugMode) {
          debugPrint('API -> ${options.method} ${options.uri}');
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        if (kDebugMode) {
          final requestId = response.headers.value('X-Request-Id') ?? '-';
          final startedAt = response.requestOptions.extra['startedAtMs'] as int?;
          final elapsedMs = startedAt == null
              ? -1
              : DateTime.now().millisecondsSinceEpoch - startedAt;
          debugPrint(
            'API <- ${response.statusCode} ${response.requestOptions.path} requestId=$requestId elapsedMs=$elapsedMs',
          );
        }
        handler.next(response);
      },
      onError: (DioException error, handler) {
        if (kDebugMode) {
          final requestId =
              error.response?.headers.value('X-Request-Id') ?? '-';
          final startedAt = error.requestOptions.extra['startedAtMs'] as int?;
          final elapsedMs = startedAt == null
              ? -1
              : DateTime.now().millisecondsSinceEpoch - startedAt;
          debugPrint(
            'API !! ${error.response?.statusCode} ${error.requestOptions.path} requestId=$requestId elapsedMs=$elapsedMs body=${error.response?.data}',
          );
        }
        handler.next(error);
      },
    ),
  );
  return dio;
});
