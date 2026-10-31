import 'package:conduit/features/hermes/views/hermes_skills_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit_core/features/hermes/models/hermes_skill.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _skills = [
  HermesSkill(
    name: 'audit',
    description: 'Review what a session did.',
    enabled: true,
  ),
  HermesSkill(
    name: 'code-wiki',
    description: 'Generate wiki docs for a repo.',
    category: 'software-development',
    enabled: false,
  ),
];

Widget _page(List<HermesSkill> skills) => ProviderScope(
  overrides: [
    hermesDashboardSkillsProvider.overrideWith((ref) async => skills),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const HermesSkillsPage(),
  ),
);

void main() {
  testWidgets('lists skills with their category and enabled state', (
    tester,
  ) async {
    await tester.pumpWidget(_page(_skills));
    await tester.pumpAndSettle();

    expect(find.text('audit'), findsOneWidget);
    expect(find.text('code-wiki'), findsOneWidget);
    expect(find.text('software-development'), findsOneWidget);
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    // One per skill; the disabled skill's switch is off.
    expect(switches.length, 2);
    expect(switches.where((value) => value.value).length, 1);
  });

  testWidgets('search narrows the list without touching the server', (
    tester,
  ) async {
    await tester.pumpWidget(_page(_skills));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'wiki');
    await tester.pumpAndSettle();

    expect(find.text('code-wiki'), findsOneWidget);
    expect(find.text('audit'), findsNothing);
  });

  testWidgets('says when nothing is installed', (tester) async {
    await tester.pumpWidget(_page(const []));
    await tester.pumpAndSettle();

    expect(find.text('No skills installed.'), findsOneWidget);
  });
}
