import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _dio(DioExceptionType type) => DioException(
  requestOptions: RequestOptions(path: '/api/cron/jobs/x/trigger'),
  type: type,
);

void main() {
  test('a slow trigger counts as started', () {
    check(hermesJobStartTimedOut(_dio(DioExceptionType.receiveTimeout))).isTrue();
    check(hermesJobStartTimedOut(_dio(DioExceptionType.sendTimeout))).isTrue();
    check(
      hermesJobStartTimedOut(_dio(DioExceptionType.connectionTimeout)),
    ).isTrue();
  });

  test('a refused trigger is a real failure', () {
    check(hermesJobStartTimedOut(_dio(DioExceptionType.badResponse))).isFalse();
    check(hermesJobStartTimedOut(StateError('nope'))).isFalse();
  });
}
