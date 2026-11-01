import 'package:conduit/features/hermes/views/hermes_git_diff_page.dart';
import 'package:conduit/features/hermes/views/hermes_git_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit_core/features/hermes/models/hermes_fs.dart';
import 'package:conduit_core/features/hermes/models/hermes_git.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _status = HermesGitStatus(
  branch: 'hermes-first',
  ahead: 2,
  behind: 1,
  changed: 2,
  added: 30,
  removed: 4,
  files: [
    HermesGitFile(path: 'lib/a.dart', staged: true),
    HermesGitFile(path: 'new.txt', untracked: true),
  ],
);

Widget _gitPage(HermesGitStatus? status) => ProviderScope(
  overrides: [
    hermesFsDefaultsProvider.overrideWith(
      (ref) async => const HermesFsDefaults(cwd: '/repo'),
    ),
    hermesGitStatusProvider.overrideWith((ref, path) async => status),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const HermesGitPage(),
  ),
);

Widget _diffPage(HermesGitDiff? diff) => ProviderScope(
  overrides: [
    hermesGitFileDiffProvider.overrideWith((ref, query) async => diff),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const HermesGitDiffPage(path: '/repo', file: 'lib/a.dart'),
  ),
);

void main() {
  testWidgets('shows branch, counts and changed files', (tester) async {
    await tester.pumpWidget(_gitPage(_status));
    await tester.pumpAndSettle();

    expect(find.text('hermes-first'), findsOneWidget);
    expect(find.textContaining('2 changed'), findsOneWidget);
    expect(find.textContaining('2 ahead'), findsOneWidget);
    expect(find.text('lib/a.dart'), findsOneWidget);
    expect(find.text('new.txt'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('a clean tree says so', (tester) async {
    await tester.pumpWidget(
      _gitPage(const HermesGitStatus(branch: 'main', files: [])),
    );
    await tester.pumpAndSettle();
    expect(find.text('Working tree clean.'), findsOneWidget);
  });

  testWidgets('a non-repository path says so', (tester) async {
    await tester.pumpWidget(_gitPage(null));
    await tester.pumpAndSettle();
    expect(find.text('This path is not a git repository.'), findsOneWidget);
  });

  testWidgets('renders a diff', (tester) async {
    await tester.pumpWidget(
      _diffPage(const HermesGitDiff(diff: '@@ -1 +1 @@\n-old\n+new')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('+new'), findsOneWidget);
  });

  testWidgets('an empty diff says so', (tester) async {
    await tester.pumpWidget(_diffPage(const HermesGitDiff()));
    await tester.pumpAndSettle();
    expect(find.text('No diff for this file.'), findsOneWidget);
  });
}
