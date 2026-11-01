import 'package:conduit/features/hermes/widgets/hermes_jobs_sheet.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit/shared/widgets/themed_sheets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('the jobs sheet lays out with the bounded height it is opened '
      'with', (tester) async {
    // showHermesJobsSheet supplies this SizedBox; without it the surface's
    // unbounded column makes the sheet\'s Expanded throw and the user sees
    // only a dimmed barrier.
    await tester.pumpWidget(
      _host(
        SizedBox(
          height: 600,
          child: const ConduitModalSheetSurface(child: HermesJobsSheet()),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Scheduled agents'), findsOneWidget);
  });

  testWidgets('opening the real sheet route shows content, not a bare barrier', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(TweakcnThemes.t3Chat),
          localizationsDelegates: conduitLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showHermesJobsSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Scheduled agents'), findsWidgets);
    expect(find.text('Manage'), findsWidgets);
  });
}
