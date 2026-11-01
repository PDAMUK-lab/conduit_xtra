import 'package:conduit/features/hermes/views/hermes_profiles_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit_core/features/hermes/models/hermes_profile.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _profiles = [
  HermesProfileSummary(
    name: 'default',
    isDefault: true,
    model: 'deepseek-v4.1-flash',
    provider: 'openrouter',
    skillCount: 88,
    gatewayRunning: true,
    displayName: 'Hermes',
  ),
  HermesProfileSummary(name: 'alternative', skillCount: 4),
];

const _active = HermesProfileActive(active: 'default', current: 'default');

Widget _page() => ProviderScope(
  overrides: [
    hermesProfileListProvider.overrideWith((ref) async => _profiles),
    hermesActiveProfileProvider.overrideWith((ref) async => _active),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const HermesProfilesPage(),
  ),
);

void main() {
  testWidgets('lists profiles with model, state and skill count', (
    tester,
  ) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    expect(find.text('Hermes'), findsOneWidget);
    expect(find.text('alternative'), findsOneWidget);
    expect(find.text('openrouter · deepseek-v4.1-flash'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Gateway running'), findsOneWidget);
    expect(find.text('88 skills'), findsOneWidget);
    expect(find.text('4 skills'), findsOneWidget);
  });
}
