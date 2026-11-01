import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/models/hermes_blueprint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a catalog entry with its slots', () {
    final list = HermesBlueprint.listFromJson({
      'blueprints': [
        {
          'key': 'morning-brief',
          'title': 'Morning briefing',
          'description': 'A short daily briefing.',
          'category': 'daily',
          'tags': ['daily', 'briefing'],
          'source': 'builtin',
          'plugin': null,
          'schedule': '{minute} {hour} * * *',
          'scheduleHuman': 'Every day at 08:00',
          'fields': [
            {
              'name': 'time',
              'type': 'time',
              'label': 'Time',
              'default': '08:00',
              'options': <String>[],
              'optional': false,
              'strict': true,
              'help': '',
            },
            {
              'name': 'deliver',
              'type': 'enum',
              'label': 'Deliver to',
              'default': 'origin',
              'options': ['origin', 'local', 'ntfy'],
              'optional': false,
              'strict': false,
              'help': 'Where it goes',
            },
          ],
        },
      ],
    });
    check(list).length.equals(1);
    final blueprint = list.first;
    check(blueprint.key).equals('morning-brief');
    check(blueprint.isPlugin).isFalse();
    check(blueprint.fields).length.equals(2);
    check(blueprint.fields.first.isTime).isTrue();
    check(blueprint.fields.first.defaultValue).equals('08:00');
    check(blueprint.fields.last.isEnum).isTrue();
    check(blueprint.fields.last.strict).isFalse();
    check(blueprint.fields.last.options).deepEquals(['origin', 'local', 'ntfy']);
  });

  test('marks plugin blueprints and tolerates missing pieces', () {
    final list = HermesBlueprint.listFromJson({
      'blueprints': [
        {'key': 'p', 'title': 'Plugin one', 'source': 'plugin', 'plugin': 'acme'},
        {'title': 'no key'},
        'junk',
      ],
    });
    check(list).length.equals(1);
    check(list.first.isPlugin).isTrue();
    check(list.first.plugin).equals('acme');
    check(HermesBlueprint.listFromJson(null)).isEmpty();
  });

  test('a slot without a label is dropped rather than half-rendered', () {
    final blueprint = HermesBlueprint.fromJson({
      'key': 'k',
      'title': 'T',
      'fields': [
        {'name': 'good', 'type': 'text', 'label': 'Good'},
        {'name': 'bad', 'type': 'text'},
      ],
    });
    check(blueprint).isNotNull();
    check(blueprint!.fields).length.equals(1);
  });
}
