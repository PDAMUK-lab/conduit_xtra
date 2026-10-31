import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/models/hermes_skill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the dashboard list and keeps the useful fields', () {
    final skills = HermesSkill.listFromJson([
      {
        'name': 'audit',
        'description': 'Review what a session did.',
        'category': null,
        'enabled': true,
        'usage': 58,
        'provenance': 'agent',
      },
      {
        'name': 'software-development--code-wiki',
        'description': 'Generate wiki docs.',
        'category': 'software-development',
        'enabled': false,
        'usage': 3,
        'provenance': 'agent',
      },
    ]);

    check(skills).length.equals(2);
    check(skills.first.name).equals('audit');
    check(skills.first.category).isNull();
    check(skills.first.enabled).isTrue();
    check(skills.first.usage).equals(58);
    check(skills.last.enabled).isFalse();
    check(skills.last.category).equals('software-development');
  });

  test('drops rows without a usable name and survives junk', () {
    final skills = HermesSkill.listFromJson([
      {'name': '', 'description': 'empty'},
      {'name': 'bad name with spaces'},
      {'description': 'no name'},
      'not-a-map',
      {'name': 'ok', 'description': 'kept'},
    ]);
    check(skills.map((skill) => skill.name)).deepEquals(['ok']);
  });

  test('a missing description stays empty rather than throwing', () {
    final skill = HermesSkill.fromJson({'name': 'bare'});
    check(skill).isNotNull();
    check(skill!.description).equals('');
    check(skill.enabled).isTrue();
    check(skill.usage).equals(0);
  });

  test('matches name, description and category case-insensitively', () {
    const skill = HermesSkill(
      name: 'code-wiki',
      description: 'Generate wiki docs for a repo.',
      category: 'software-development',
    );
    check(skill.matches('')).isTrue();
    check(skill.matches('WIKI')).isTrue();
    check(skill.matches('repo')).isTrue();
    check(skill.matches('software')).isTrue();
    check(skill.matches('nope')).isFalse();
  });
}
