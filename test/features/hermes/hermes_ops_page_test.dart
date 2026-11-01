import 'package:conduit/features/hermes/views/hermes_ops_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit_core/features/hermes/models/hermes_ops.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _checkpoints = HermesCheckpoints(
  sessions: [
    HermesCheckpointSession(session: 'abc', files: 3, bytes: 2048),
  ],
  totalBytes: 2048,
);

const _hooks = [
  HermesHook(event: 'agent_end', command: 'echo done', allowed: true),
  HermesHook(event: 'agent_start', command: 'notify'),
];

Widget _page({
  HermesCheckpoints? checkpoints = _checkpoints,
  List<HermesHook> hooks = _hooks,
}) => ProviderScope(
  overrides: [
    hermesCheckpointsProvider.overrideWith((ref) async => checkpoints),
    hermesHooksProvider.overrideWith((ref) async => hooks),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const HermesOpsPage(),
  ),
);

void main() {
  testWidgets('shows actions, checkpoint inventory and hooks', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    expect(find.text('Doctor'), findsOneWidget);
    expect(find.text('Security audit'), findsOneWidget);
    expect(find.text('Backup'), findsOneWidget);
    expect(find.textContaining('2.0 KB'), findsWidgets);
    expect(find.textContaining('abc'), findsOneWidget);
    expect(find.text('agent_end · echo done'), findsOneWidget);
    expect(find.text('allowed'), findsOneWidget);
    expect(find.text('not approved'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('hermes-ops-prune')), findsOneWidget);
  });

  testWidgets('empty checkpoints and hooks explain themselves', (tester) async {
    await tester.pumpWidget(
      _page(checkpoints: const HermesCheckpoints(), hooks: const []),
    );
    await tester.pumpAndSettle();

    expect(find.text('No checkpoints.'), findsOneWidget);
    expect(find.text('No hooks.'), findsOneWidget);
  });
}
