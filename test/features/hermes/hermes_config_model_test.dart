import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/models/hermes_config_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses raw config with its path', () {
    final config = HermesRawConfig.fromJson({
      'yaml': 'model:\n  provider: openrouter\n',
      'path': '/home/hermes/.hermes/config.yaml',
    });
    check(config).isNotNull();
    check(config!.path).equals('/home/hermes/.hermes/config.yaml');
    check(config.yaml).contains('provider: openrouter');
    check(HermesRawConfig.fromJson({'yaml': ''})).isNull();
  });

  test('parses the env map into sorted rows', () {
    final env = HermesEnvVar.listFromJson({
      'ZED_KEY': {'is_set': true, 'redacted_value': 'z…1'},
      'ALPHA_KEY': {
        'is_set': false,
        'description': 'Alpha',
        'category': 'providers',
        'is_password': true,
        'custom': true,
      },
    });
    check(env.map((e) => e.name)).deepEquals(['ALPHA_KEY', 'ZED_KEY']);
    check(env.first.isSet).isFalse();
    check(env.first.isPassword).isTrue();
    check(env.first.custom).isTrue();
    check(env.last.isSet).isTrue();
    check(env.last.redactedValue).equals('z…1');
  });

  test('matches name, description and category', () {
    const env = HermesEnvVar(
      name: 'OPENROUTER_API_KEY',
      description: 'OpenRouter key',
      category: 'providers',
    );
    check(env.matches('')).isTrue();
    check(env.matches('openrouter')).isTrue();
    check(env.matches('PROVIDERS')).isTrue();
    check(env.matches('nope')).isFalse();
  });
}
