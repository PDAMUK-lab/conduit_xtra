import 'package:conduit/features/hermes/widgets/hermes_blueprint_form.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit/shared/widgets/conduit_components.dart';
import 'package:conduit_core/features/hermes/models/hermes_blueprint.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _blueprint = HermesBlueprint(
  key: 'morning-brief',
  title: 'Morning briefing',
  description: 'A short daily briefing.',
  category: 'daily',
  scheduleHuman: 'Every day at 08:00',
  fields: [
    HermesBlueprintField(
      name: 'time',
      type: 'time',
      label: 'Time',
      defaultValue: '08:00',
    ),
    HermesBlueprintField(
      name: 'deliver',
      type: 'enum',
      label: 'Deliver to',
      defaultValue: 'origin',
      options: ['origin', 'local'],
      strict: false,
    ),
  ],
);

Widget _host(HermesBlueprint blueprint) => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: HermesBlueprintForm(blueprint: blueprint)),
  ),
);

bool _enabled(WidgetTester tester) =>
    tester
        .widget<ConduitButton>(
          find.byKey(const ValueKey<String>('hermes-blueprint-submit')),
        )
        .onPressed !=
    null;

void main() {
  testWidgets('renders the slots with their defaults and can submit', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_blueprint));
    await tester.pump();

    expect(find.text('Morning briefing'), findsOneWidget);
    expect(find.text('Time'), findsOneWidget);
    expect(find.text('Deliver to'), findsOneWidget);
    expect(_enabled(tester), isTrue);
  });

  testWidgets('a malformed time blocks submission', (tester) async {
    await tester.pumpWidget(_host(_blueprint));
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey<String>('hermes-blueprint-time')),
      '99:99',
    );
    await tester.pump();
    expect(_enabled(tester), isFalse);

    await tester.enterText(
      find.byKey(const ValueKey<String>('hermes-blueprint-time')),
      '09:30',
    );
    await tester.pump();
    expect(_enabled(tester), isTrue);
  });

  testWidgets('a required slot left empty blocks submission', (tester) async {
    await tester.pumpWidget(
      _host(
        const HermesBlueprint(
          key: 'k',
          title: 'K',
          description: '',
          fields: [
            HermesBlueprintField(name: 'subject', type: 'text', label: 'Subject'),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(_enabled(tester), isFalse);

    await tester.enterText(
      find.byKey(const ValueKey<String>('hermes-blueprint-subject')),
      'hello',
    );
    await tester.pump();
    expect(_enabled(tester), isTrue);
  });

  testWidgets('an optional slot may stay empty', (tester) async {
    await tester.pumpWidget(
      _host(
        const HermesBlueprint(
          key: 'k',
          title: 'K',
          description: '',
          fields: [
            HermesBlueprintField(
              name: 'note',
              type: 'text',
              label: 'Note',
              optional: true,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(_enabled(tester), isTrue);
  });
}
