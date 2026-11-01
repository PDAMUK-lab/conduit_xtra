import 'package:conduit/features/hermes/widgets/hermes_git_commit_sheet.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit/shared/widgets/conduit_components.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host({required int staged}) => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: HermesGitCommitSheet(path: '/repo', staged: staged),
    ),
  ),
);

bool _enabled(WidgetTester tester, String key) =>
    tester
        .widget<ConduitButton>(find.byKey(ValueKey<String>(key)))
        .onPressed !=
    null;

void main() {
  testWidgets('needs a message before it will commit', (tester) async {
    await tester.pumpWidget(_host(staged: 2));
    await tester.pump();

    expect(find.textContaining('2 staged'), findsOneWidget);
    expect(_enabled(tester, 'hermes-git-commit-submit'), isFalse);

    await tester.enterText(
      find.byKey(const ValueKey<String>('hermes-git-commit-message')),
      'fix the thing',
    );
    await tester.pump();
    expect(_enabled(tester, 'hermes-git-commit-submit'), isTrue);
  });

  testWidgets('push starts off', (tester) async {
    await tester.pumpWidget(_host(staged: 1));
    await tester.pump();

    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey<String>('hermes-git-commit-push')),
    );
    expect(toggle.value, isFalse);
  });

  testWidgets('nothing staged means nothing to commit', (tester) async {
    await tester.pumpWidget(_host(staged: 0));
    await tester.pump();

    expect(find.text('Nothing staged.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('hermes-git-commit-message')),
      'message',
    );
    await tester.pump();
    expect(_enabled(tester, 'hermes-git-commit-submit'), isFalse);
  });
}
