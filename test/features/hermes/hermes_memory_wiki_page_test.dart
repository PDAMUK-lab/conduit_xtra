import 'package:conduit/features/hermes/views/hermes_memory_wiki_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit_core/features/hermes/models/hermes_memory_wiki.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _overview = HermesMemoryWikiOverview(
  subjects: [
    HermesWikiSubject(
      slug: 'memory-wiki',
      name: 'Memory Wiki',
      sessionCount: 3,
      messageCount: 42,
    ),
  ],
  days: [
    HermesWikiDay(date: '2026-10-31', sessionCount: 2, messageCount: 9),
  ],
  notes: HermesWikiNotes(
    memory: ['Prefers rebase merges'],
    user: ['UK-based'],
    memoryCount: 1,
    userCount: 1,
  ),
);

const _archive = HermesMemoryArchive(
  available: true,
  provider: 'hermesmemory',
  total: 4,
  active: 1,
  archived: 2,
  notes: 1,
  pins: 0,
  entries: [
    HermesMemoryArchiveEntry(
      id: 7,
      status: 'replaced',
      target: 'memory',
      content: 'old entry',
    ),
  ],
);

Widget _page({
  HermesMemoryWikiOverview? overview = _overview,
  HermesMemoryArchive? archive = _archive,
}) => ProviderScope(
  overrides: [
    hermesMemoryWikiOverviewProvider.overrideWith((ref) async => overview),
    hermesMemoryWikiArchiveProvider.overrideWith((ref) async => archive),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const HermesMemoryWikiPage(),
  ),
);

void main() {
  testWidgets('shows persistent memory, subjects, days and archive', (
    tester,
  ) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    expect(find.text('Memory Wiki'), findsWidgets);
    expect(find.textContaining('MEMORY.md'), findsOneWidget);
    expect(find.text('Prefers rebase merges'), findsOneWidget);
    expect(find.text('UK-based'), findsOneWidget);
    expect(find.text('Memory Wiki'), findsWidgets);
    expect(find.text('2026-10-31'), findsOneWidget);
    expect(find.textContaining('hermesmemory'), findsOneWidget);
    expect(find.text('old entry'), findsOneWidget);
  });

  testWidgets('says the archive is unavailable when the provider has none', (
    tester,
  ) async {
    await tester.pumpWidget(
      _page(archive: const HermesMemoryArchive(available: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No archive for this provider.'), findsOneWidget);
  });

  testWidgets('filters subjects with the search field', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'nomatch');
    await tester.pumpAndSettle();
    expect(find.text('No subjects yet.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'wiki');
    await tester.pumpAndSettle();
    expect(find.text('Memory Wiki'), findsWidgets);
  });
}
