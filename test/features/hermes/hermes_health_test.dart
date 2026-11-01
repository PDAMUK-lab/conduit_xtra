import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/models/hermes_health.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a healthy node', () {
    final health = HermesHealth.fromJson({
      'overall': 'ok',
      'version': '0.22.5',
      'gateway_running': true,
      'active_sessions': 3,
      'disk': {'pressure': 'ok', 'total_mb': 462657, 'free_mb': 333023},
      'components': {
        'gateway': {'status': 'ok', 'state': 'running'},
      },
    });
    check(health).isNotNull();
    check(health!.healthy).isTrue();
    check(health.degraded).isFalse();
    check(health.gatewayRunning).isTrue();
    check(health.diskFreeMb).equals(333023);
    check(health.activeSessions).equals(3);
    check(health.gatewayState).equals('running');
  });

  test('a degraded node is not healthy', () {
    final health = HermesHealth.fromJson({
      'overall': 'degraded',
      'gateway_running': false,
      'components': {
        'gateway': {'state': 'stopped'},
      },
    });
    check(health!.healthy).isFalse();
    check(health.degraded).isTrue();
    check(health.diskFreeMb).isNull();
  });

  test('junk is null rather than a throw', () {
    check(HermesHealth.fromJson(null)).isNull();
    check(HermesHealth.fromJson('nope')).isNull();
  });
}
