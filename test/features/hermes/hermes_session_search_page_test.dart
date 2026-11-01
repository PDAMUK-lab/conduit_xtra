import 'package:conduit/features/hermes/views/hermes_session_search_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit_core/features/hermes/models/hermes_session.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _hits = [
  HermesSessionSummary(
    id: 's1',
    title: 'Conduit build plan',
    preview: 'The Hermes-first Android client…',
  ),
  HermesSessionSummary(
    id: 's2',
    title: 'Bench matrix results',
    preview: 'MoE flags screened on the laptop…',
  ),
];

Widget _host(List<HermesSessionSummary> hits) => ProviderScope(
  overrides: [
    hermesSessionSearchProvider.overrideWith((ref, query) async => hits),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const HermesSessionSearchPage(),
  ),
);

void main() {
  testWidgets('asks for two characters before searching', (tester) async {
    await tester.pumpWidget(_host(_hits));
    await tester.pumpAndSettle();
    expect(find.text('Type at least two characters.'), findsOneWidget);
  });

  testWidgets('renders matches with title and preview', (tester) async {
    await tester.pumpWidget(_host(_hits));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'conduit');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Conduit build plan'), findsOneWidget);
    expect(find.textContaining('Hermes-first Android'), findsOneWidget);
    expect(find.text('Bench matrix results'), findsOneWidget);
  });

  testWidgets('no matches says so', (tester) async {
    await tester.pumpWidget(_host(const []));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('No matches.'), findsOneWidget);
  });
}
