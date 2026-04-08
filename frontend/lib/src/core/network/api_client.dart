import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';

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
        if (kDebugMode) {
          debugPrint('API -> ${options.method} ${options.uri}');
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        if (kDebugMode) {
          final requestId = response.headers.value('X-Request-Id') ?? '-';
          debugPrint(
            'API <- ${response.statusCode} ${response.requestOptions.path} requestId=$requestId',
          );
        }
        handler.next(response);
      },
      onError: (error, handler) {
        if (kDebugMode) {
          final requestId =
              error.response?.headers.value('X-Request-Id') ?? '-';
          debugPrint(
            'API !! ${error.response?.statusCode} ${error.requestOptions.path} requestId=$requestId body=${error.response?.data}',
          );
        }
        handler.next(error);
      },
    ),
  );
  return dio;
});
