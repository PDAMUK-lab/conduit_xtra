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

Widget _gitPage({
  HermesGitStatus? status = _status,
  String? root = '/repo',
  List<String> repos = const [],
}) => ProviderScope(
  overrides: [
    hermesFsDefaultsProvider.overrideWith(
      (ref) async => const HermesFsDefaults(cwd: '/workspace'),
    ),
    hermesGitRootProvider.overrideWith((ref, path) async => root),
    hermesGitReposProvider.overrideWith((ref, path) async => repos),
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
    await tester.pumpWidget(_gitPage());
    await tester.pumpAndSettle();

    expect(find.text('hermes-first'), findsOneWidget);
    expect(find.textContaining('2 changed'), findsOneWidget);
    expect(find.textContaining('2 ahead'), findsOneWidget);
    expect(find.text('lib/a.dart'), findsOneWidget);
    expect(find.text('new.txt'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('hermes-git-path')), findsOneWidget);
  });

  testWidgets('a clean tree says so', (tester) async {
    await tester.pumpWidget(
      _gitPage(status: const HermesGitStatus(branch: 'main', files: [])),
    );
    await tester.pumpAndSettle();
    expect(find.text('Working tree clean.'), findsOneWidget);
  });

  testWidgets('offers the repositories beside a non-repository cwd', (
    tester,
  ) async {
    await tester.pumpWidget(
      _gitPage(root: null, repos: const ['/workspace/one']),
    );
    await tester.pumpAndSettle();

    expect(find.text('Repositories in this folder'), findsOneWidget);
    expect(find.text('/workspace/one'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('hermes-git-repo-/workspace/one')),
      findsOneWidget,
    );
  });

  testWidgets('says so when nothing is a repository', (tester) async {
    await tester.pumpWidget(_gitPage(root: null));
    await tester.pumpAndSettle();
    expect(find.text('This path is not a git repository.'), findsOneWidget);
  });

  testWidgets('opening a repository path shows its status', (tester) async {
    await tester.pumpWidget(_gitPage(root: null));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('hermes-git-path')),
      '/workspace/two',
    );
    await tester.tap(find.byKey(const ValueKey<String>('hermes-git-open')));
    await tester.pumpAndSettle();

    expect(find.text('hermes-first'), findsOneWidget);
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
