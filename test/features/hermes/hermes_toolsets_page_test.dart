import 'package:conduit/features/hermes/views/hermes_toolsets_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit_core/features/hermes/models/hermes_toolsets.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _toolsets = [
  HermesToolsetSummary(
    name: 'web',
    label: 'Web',
    description: 'Search and fetch',
    platformLabel: 'CLI',
    enabled: true,
    configured: true,
    tools: ['web_search', 'web_extract'],
  ),
  HermesToolsetSummary(
    name: 'computer',
    label: 'Computer use',
    enabled: false,
    configured: false,
  ),
];

Widget _page(List<HermesToolsetSummary> toolsets) => ProviderScope(
  overrides: [
    hermesToolsetListProvider.overrideWith((ref) async => toolsets),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const HermesToolsetsPage(),
  ),
);

void main() {
  testWidgets('lists toolsets with switches, counts and setup warnings', (
    tester,
  ) async {
    await tester.pumpWidget(_page(_toolsets));
    await tester.pumpAndSettle();

    expect(find.text('Web'), findsOneWidget);
    expect(find.text('Search and fetch'), findsOneWidget);
    expect(find.text('Computer use'), findsOneWidget);
    expect(find.text('Needs setup'), findsOneWidget);
    expect(find.textContaining('Tools: 2'), findsOneWidget);
    expect(find.textContaining('CLI'), findsOneWidget);

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches.length, 2);
    expect(switches.where((value) => value.value).length, 1);
  });

  testWidgets('an empty list explains itself', (tester) async {
    await tester.pumpWidget(_page(const []));
    await tester.pumpAndSettle();

    expect(find.text('Could not load toolsets.'), findsOneWidget);
  });
}
