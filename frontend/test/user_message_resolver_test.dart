import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit/src/core/errors/app_user_message.dart';

void main() {
  test('fromDio maps connection errors to server unreachable', () {
    final message = UserMessageResolver.fromDio(
      DioException(
        requestOptions: RequestOptions(path: '/cities'),
        type: DioExceptionType.connectionError,
      ),
    );
    expect(message.visible, isTrue);
    expect(message.resolveText(), AppUserMessages.serverUnreachable.resolveText());
  });

  DioException badResponse(int status) => DioException(
        requestOptions: RequestOptions(path: '/cities'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/cities'),
          statusCode: status,
        ),
      );

  test('fromDio maps 5xx to server unreachable (no trip-planning copy)', () {
    for (final status in [500, 502, 503]) {
      final message = UserMessageResolver.fromDio(badResponse(status));
      expect(message.resolveText(),
          AppUserMessages.serverUnreachable.resolveText());
    }
  });

  test('fromDio maps 4xx to unexpected error', () {
    for (final status in [400, 404]) {
      final message = UserMessageResolver.fromDio(badResponse(status));
      expect(message.resolveText(),
          AppUserMessages.unexpectedError.resolveText());
    }
  });

  test('userFacingMessageForDioFailure returns friendly text', () {
    final text = userFacingMessageForDioFailure(
      DioException(
        requestOptions: RequestOptions(path: '/cities'),
        type: DioExceptionType.connectionTimeout,
      ),
    );
    expect(text, AppUserMessages.serverTimeout.resolveText());
    expect(text.contains('API_BASE_URL'), isFalse);
  });
}
