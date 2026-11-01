import 'package:conduit/features/hermes/widgets/hermes_restore_sheet.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit/shared/widgets/conduit_components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host() => MaterialApp(
  theme: AppTheme.light(TweakcnThemes.t3Chat),
  localizationsDelegates: conduitLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: const Scaffold(
    body: HermesRestoreSheet(
      archive: '/home/hermes/.hermes/backups/hermes-backup-2026-11-01.zip',
    ),
  ),
);

bool _enabled(WidgetTester tester) =>
    tester
        .widget<ConduitButton>(
          find.byKey(const ValueKey<String>('hermes-restore-submit')),
        )
        .onPressed !=
    null;

void main() {
  testWidgets('shows the archive, the damage warning and the drain note', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text('hermes-backup-2026-11-01.zip'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    expect(find.textContaining('gateway stops'), findsOneWidget);
  });

  testWidgets('restore needs the word typed exactly', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();
    expect(_enabled(tester), isFalse);

    await tester.enterText(
      find.byKey(const ValueKey<String>('hermes-restore-confirm')),
      'restore',
    );
    await tester.pump();
    expect(_enabled(tester), isFalse);

    await tester.enterText(
      find.byKey(const ValueKey<String>('hermes-restore-confirm')),
      'import',
    );
    await tester.pump();
    expect(_enabled(tester), isTrue);
  });
}
