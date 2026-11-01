import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/models/hermes_delivery_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses local plus platform targets', () {
    final targets = HermesDeliveryTarget.listFromJson({
      'targets': [
        {
          'id': 'local',
          'name': 'Local (save only)',
          'home_target_set': true,
          'home_env_var': null,
        },
        {
          'id': 'ntfy',
          'name': 'ntfy',
          'home_target_set': true,
          'home_env_var': 'NTFY_TOPIC',
        },
        {
          'id': 'discord',
          'name': 'Discord',
          'home_target_set': false,
          'home_env_var': 'DISCORD_HOME_CHANNEL',
        },
      ],
    });
    check(targets).length.equals(3);
    check(targets.first.isLocal).isTrue();
    check(targets[1].homeEnvVar).equals('NTFY_TOPIC');
    check(targets.last.homeTargetSet).isFalse();
  });

  test('drops rows without an id and survives junk', () {
    final targets = HermesDeliveryTarget.listFromJson({
      'targets': [
        {'name': 'no id'},
        {'id': 'local', 'name': 'Local'},
        'nonsense',
      ],
    });
    check(targets).length.equals(1);
    check(HermesDeliveryTarget.listFromJson(null)).isEmpty();
    check(HermesDeliveryTarget.listFromJson({'targets': 'nope'})).isEmpty();
  });
}
