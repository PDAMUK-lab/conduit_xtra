import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/models/hermes_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the profiles envelope the dashboard returns', () {
    final profiles = HermesProfileSummary.listFromJson({
      'profiles': [
        {
          'name': 'default',
          'path': '/home/hermes/.hermes',
          'is_default': true,
          'model': 'deepseek-v4.1-flash',
          'provider': 'openrouter',
          'has_env': true,
          'skill_count': 88,
          'gateway_running': true,
          'description': 'The main agent',
          'description_auto': false,
          'display_name': 'Hermes',
          'bot_title': '',
          'has_alias': true,
        },
        {
          'name': 'alternative',
          'path': '/home/hermes/.hermes/profiles/alternative',
          'is_default': false,
          'model': null,
          'provider': null,
          'has_env': false,
          'skill_count': 0,
          'gateway_running': false,
          'description': '',
          'display_name': '',
          'bot_title': 'Alt bot',
        },
      ],
    });
    check(profiles).length.equals(2);
    check(profiles.first.name).equals('default');
    check(profiles.first.isDefault).isTrue();
    check(profiles.first.modelLabel).equals('openrouter · deepseek-v4.1-flash');
    check(profiles.first.title).equals('Hermes');
    check(profiles.first.skillCount).equals(88);
    check(profiles.last.title).equals('Alt bot');
    check(profiles.last.modelLabel).equals('');
  });

  test('drops a profile without a name', () {
    final profiles = HermesProfileSummary.listFromJson({
      'profiles': [
        {'path': '/x'},
        {'name': 'ok'},
      ],
    });
    check(profiles.map((p) => p.name)).deepEquals(['ok']);
  });

  test('parses the active profile pair', () {
    final active = HermesProfileActive.fromJson({
      'active': 'default',
      'current': 'default',
    });
    check(active).isNotNull();
    check(active!.active).equals('default');
    check(active.current).equals('default');
    check(HermesProfileActive.fromJson({'active': 'x'})).isNull();
  });

  test('parses a missing soul as empty content', () {
    final missing = HermesProfileSoul.fromJson({'content': '', 'exists': false});
    check(missing!.exists).isFalse();
    check(missing.content).equals('');
    final present = HermesProfileSoul.fromJson({
      'content': '# Soul\nBe careful.',
      'exists': true,
    });
    check(present!.exists).isTrue();
    check(present.content).equals('# Soul\nBe careful.');
    check(HermesProfileSoul.fromJson({'exists': true})).isNull();
  });
}
