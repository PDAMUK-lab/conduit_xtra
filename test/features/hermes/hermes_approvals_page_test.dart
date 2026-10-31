import 'package:checks/checks.dart';
import 'package:conduit/features/hermes/views/hermes_approvals_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:conduit_core/features/hermes/services/hermes_pending_decision_store.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

List<HermesPendingDesktopDecision> _decisions() => [
  HermesPendingDesktopDecision(
    origin: 'https://hermes.example:443',
    storedSessionId: 'stored-1',
    runtimeId: 'runtime-1',
    requestId: 'request-1',
    kind: HermesPendingDesktopDecisionKind.approval,
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
    prompt: 'rm -rf build/',
  ),
  HermesPendingDesktopDecision(
    origin: 'https://hermes.example:443',
    storedSessionId: 'stored-2',
    runtimeId: 'runtime-2',
    requestId: 'request-2',
    kind: HermesPendingDesktopDecisionKind.clarification,
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
    prompt: 'Which branch should I use?',
  ),
];

Widget _page(List<HermesPendingDesktopDecision> pending) => ProviderScope(
  overrides: [
    hermesPendingDecisionsProvider.overrideWith(
      (ref) => Stream<List<HermesPendingDesktopDecision>>.value(pending),
    ),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const HermesApprovalsPage(),
  ),
);

void main() {
  testWidgets('lists approvals and questions across sessions', (tester) async {
    await tester.pumpWidget(_page(_decisions()));
    await tester.pumpAndSettle();

    expect(find.text('Approval required'), findsOneWidget);
    expect(find.text('Hermes needs clarification'), findsOneWidget);
    expect(find.text('rm -rf build/'), findsOneWidget);
    expect(find.text('Which branch should I use?'), findsOneWidget);
    // Only the approval can be answered without typing; the question opens
    // its conversation instead.
    expect(find.text('Allow once'), findsOneWidget);
    expect(find.text('Deny'), findsOneWidget);
    expect(find.text('Open conversation'), findsNWidgets(2));
    // Every waiting decision comes from a live run, so each card can stop it.
    expect(
      find.byKey(const ValueKey<String>('hermes-approval-stop-request-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('hermes-approval-stop-request-2')),
      findsOneWidget,
    );
  });

  testWidgets('says so when nothing is waiting', (tester) async {
    await tester.pumpWidget(_page(const []));
    await tester.pumpAndSettle();

    expect(find.text('Nothing is waiting for approval.'), findsOneWidget);
    check(find.text('Approval required').evaluate().length).equals(0);
  });
}
