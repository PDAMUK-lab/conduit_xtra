import 'package:conduit/features/hermes/views/hermes_file_editor_page.dart';
import 'package:conduit/features/hermes/views/hermes_files_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit_core/features/hermes/models/hermes_fs.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _defaults = HermesFsDefaults(cwd: '/repo', branch: 'hermes-first');

const Map<String, List<HermesFsEntry>> _listings = {
  '/repo': [
    HermesFsEntry(name: 'src', path: '/repo/src', isDirectory: true),
    HermesFsEntry(name: 'README.md', path: '/repo/README.md'),
    HermesFsEntry(name: 'empty', path: '/repo/empty', isDirectory: true),
  ],
  '/repo/src': [HermesFsEntry(name: 'main.dart', path: '/repo/src/main.dart')],
  '/repo/empty': [],
  '/src': [],
};

Widget _filesPage() => ProviderScope(
  overrides: [
    hermesFsDefaultsProvider.overrideWith((ref) async => _defaults),
    hermesFsListingProvider.overrideWith(
      (ref, path) async =>
          HermesFsListing(entries: _listings[path] ?? const []),
    ),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const HermesFilesPage(),
  ),
);

Widget _editorPage(String path, HermesFsTextFile? file) => ProviderScope(
  overrides: [
    hermesFsTextProvider.overrideWith((ref, _) async => file),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: HermesFileEditorPage(path: path),
  ),
);

void main() {
  testWidgets('lists a directory and walks into it', (tester) async {
    await tester.pumpWidget(_filesPage());
    await tester.pumpAndSettle();

    expect(find.text('/repo'), findsOneWidget);
    expect(find.text('src'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);

    await tester.tap(find.text('src'));
    await tester.pumpAndSettle();

    expect(find.text('/repo/src'), findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);
  });

  testWidgets('an empty directory says so', (tester) async {
    await tester.pumpWidget(_filesPage());
    await tester.pumpAndSettle();

    await tester.tap(find.text('empty'));
    await tester.pumpAndSettle();

    expect(find.text('/repo/empty'), findsOneWidget);
    expect(find.text('This directory is empty.'), findsOneWidget);
  });

  testWidgets('Up returns to the parent directory', (tester) async {
    await tester.pumpWidget(_filesPage());
    await tester.pumpAndSettle();

    await tester.tap(find.text('src'));
    await tester.pumpAndSettle();
    expect(find.text('/repo/src'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('hermes-files-up')));
    await tester.pumpAndSettle();
    expect(find.text('/repo'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
  });

  testWidgets('binary files are read-only', (tester) async {
    await tester.pumpWidget(
      _editorPage(
        '/repo/blob.bin',
        const HermesFsTextFile(path: '/repo/blob.bin', text: '', binary: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Binary file — editing is disabled.'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('hermes-file-save')), findsNothing);
  });

  testWidgets('a truncated preview cannot be saved', (tester) async {
    await tester.pumpWidget(
      _editorPage(
        '/repo/big.log',
        const HermesFsTextFile(
          path: '/repo/big.log',
          text: 'head',
          truncated: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Preview truncated at 512 KB'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('hermes-file-save')), findsNothing);
  });

  testWidgets('a text file offers the editor and a save action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _editorPage(
        '/repo/README.md',
        const HermesFsTextFile(
          path: '/repo/README.md',
          text: '# Repo',
          language: 'markdown',
          byteSize: 6,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('# Repo'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('hermes-file-save')), findsOneWidget);
  });
}
