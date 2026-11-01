import 'package:checks/checks.dart';
import 'package:conduit/features/hermes/views/hermes_config_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit_core/features/hermes/models/hermes_config_view.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _config = HermesRawConfig(
  yaml: 'model:\n  provider: openrouter\n',
  path: '/home/hermes/.hermes/config.yaml',
);

const _env = [
  HermesEnvVar(
    name: 'OPENROUTER_API_KEY',
    isSet: true,
    redactedValue: 'sk-or…abc',
    description: 'OpenRouter key',
    category: 'providers',
  ),
  HermesEnvVar(name: 'TAVILY_API_KEY', description: 'Search key'),
];

Widget _page({HermesRawConfig? config = _config}) => ProviderScope(
  overrides: [
    hermesRawConfigProvider.overrideWith((ref) async => config),
    hermesEnvVarsProvider.overrideWith((ref) async => _env),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const HermesConfigPage(),
  ),
);

void main() {
  testWidgets('shows the raw config and only set env keys by default', (
    tester,
  ) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    expect(find.text('/home/hermes/.hermes/config.yaml'), findsOneWidget);
    expect(find.textContaining('provider: openrouter'), findsOneWidget);
    expect(find.text('OPENROUTER_API_KEY'), findsOneWidget);
    expect(find.text('sk-or…abc'), findsOneWidget);
    // TAVILY_API_KEY is not set, so the "set only" default hides it.
    expect(find.text('TAVILY_API_KEY'), findsNothing);
  });

  testWidgets('turning set-only off reveals unset keys', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('TAVILY_API_KEY'), findsOneWidget);
  });

  testWidgets('search filters keys', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'tavily');
    await tester.pumpAndSettle();
    expect(find.text('TAVILY_API_KEY'), findsNothing);
    expect(find.text('OPENROUTER_API_KEY'), findsNothing);
    expect(find.text('No environment keys.'), findsOneWidget);
  });

  testWidgets('a config backend without a file explains itself', (
    tester,
  ) async {
    await tester.pumpWidget(_page(config: null));
    await tester.pumpAndSettle();
    expect(find.text('This config backend has no file.'), findsOneWidget);
  });
}
