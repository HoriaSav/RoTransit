import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotransit_frontend/src/core/errors/app_user_message.dart';

void main() {
  test('fromDio maps connection errors to server unreachable', () {
    final message = UserMessageResolver.fromDio(
      DioException(
        requestOptions: RequestOptions(path: '/routes/search'),
        type: DioExceptionType.connectionError,
      ),
    );
    expect(message.visible, isTrue);
    expect(message.resolveText(), AppUserMessages.serverUnreachable.resolveText());
  });

  test('fromDio maps 502 to routing unavailable', () {
    final message = UserMessageResolver.fromDio(
      DioException(
        requestOptions: RequestOptions(path: '/routes/search'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/routes/search'),
          statusCode: 502,
        ),
      ),
    );
    expect(message.resolveText(), AppUserMessages.routingUnavailable.resolveText());
  });

  test('map coordinate tap is suppressed', () {
    final message = AppUserMessages.mapCoordinateTap('45.65,25.60');
    expect(message.visible, isFalse);
    expect(message.text, isEmpty);
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
