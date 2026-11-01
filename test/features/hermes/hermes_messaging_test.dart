import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/models/hermes_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a platform with its credential checklist', () {
    final platforms = HermesMessagingPlatform.listFromJson({
      'platforms': [
        {
          'id': 'ntfy',
          'name': 'ntfy',
          'description': 'Push topics',
          'enabled': true,
          'configured': false,
          'gateway_running': true,
          'state': 'enabled',
          'error_message': 'NTFY_TOPIC missing',
          'home_channel': 'hermes-in',
          'env_vars': [
            {
              'key': 'NTFY_TOPIC',
              'required': true,
              'is_set': false,
              'description': 'Topic to subscribe to',
              'is_password': false,
            },
            {'key': 'NTFY_TOKEN', 'is_password': true},
          ],
        },
      ],
    });
    check(platforms).length.equals(1);
    final platform = platforms.first;
    check(platform.enabled).isTrue();
    check(platform.configured).isFalse();
    check(platform.needsSetup).isTrue();
    check(platform.homeChannel).equals('hermes-in');
    check(platform.envVars).length.equals(2);
    check(platform.envVars.first.required).isTrue();
    check(platform.envVars.last.isPassword).isTrue();
  });

  test('a healthy channel is neither setup-needed nor broken', () {
    const platform = HermesMessagingPlatform(
      id: 'x',
      name: 'X',
      enabled: true,
      configured: true,
      state: 'connected',
    );
    check(platform.needsSetup).isFalse();
    check(platform.healthy).isTrue();
  });

  test('parses a test result and survives junk', () {
    final result = HermesMessagingTestResult.fromJson({
      'ok': false,
      'state': 'enabled',
      'message': 'Telegram is not connected.',
    });
    check(result).isNotNull();
    check(result!.ok).isFalse();
    check(result.message).contains('not connected');
    check(HermesMessagingPlatform.listFromJson(null)).isEmpty();
    check(HermesMessagingPlatform.listFromJson({'platforms': 'x'})).isEmpty();
  });
}
