import 'package:conduit/features/hermes/widgets/hermes_job_editor.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit/shared/widgets/conduit_components.dart';
import 'package:conduit_core/features/hermes/models/hermes_delivery_target.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _targets = [
  HermesDeliveryTarget(id: 'local', name: 'Local (save only)'),
  HermesDeliveryTarget(id: 'ntfy', name: 'ntfy'),
  HermesDeliveryTarget(id: 'discord', name: 'Discord', homeTargetSet: false),
];

({String name, String prompt, String schedule, String deliver})? _result;

Widget _host({String? initialDeliver}) => ProviderScope(
  overrides: [
    hermesDeliveryTargetsProvider.overrideWith((ref) async => _targets),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            _result = await showHermesJobEditor(
              context,
              initialDeliver: initialDeliver,
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

Future<void> _openAndSave(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(ConduitInput).at(0),
      matching: find.byType(TextField),
    ),
    'job',
  );
  await tester.enterText(
    find.descendant(
      of: find.byType(ConduitInput).at(1),
      matching: find.byType(TextField),
    ),
    'do a thing',
  );
  await tester.pump();
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('defaults to local delivery', (tester) async {
    _result = null;
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await _openAndSave(tester);

    expect(_result, isNotNull);
    expect(_result!.deliver, 'local');
    expect(_result!.name, 'job');
  });

  testWidgets('saves the target the operator picked', (tester) async {
    _result = null;
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('hermes-job-deliver')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ntfy').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(ConduitInput).at(0),
        matching: find.byType(TextField),
      ),
      'job',
    );
    await tester.enterText(
      find.descendant(
        of: find.byType(ConduitInput).at(1),
        matching: find.byType(TextField),
      ),
      'do a thing',
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(_result!.deliver, 'ntfy');
  });

  testWidgets('opens on the job\'s current target', (tester) async {
    _result = null;
    await tester.pumpWidget(_host(initialDeliver: 'ntfy'));
    await tester.pumpAndSettle();
    await _openAndSave(tester);

    expect(_result!.deliver, 'ntfy');
  });

  testWidgets('a target without a home channel is called out', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('hermes-job-deliver')));
    await tester.pumpAndSettle();

    expect(find.textContaining('no home channel'), findsWidgets);
  });
}
