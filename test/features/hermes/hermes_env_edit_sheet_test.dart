import 'package:conduit/features/hermes/widgets/hermes_env_edit_sheet.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit/shared/widgets/conduit_components.dart';
import 'package:conduit_core/features/hermes/models/hermes_config_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(HermesEnvVar variable) => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: HermesEnvEditSheet(variable: variable)),
  ),
);

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<ConduitButton>(find.byKey(ValueKey<String>(key))).onPressed !=
    null;

void main() {
  testWidgets('shows the key, its redacted value and a disabled save', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const HermesEnvVar(
          name: 'OPENROUTER_API_KEY',
          isSet: true,
          redactedValue: 'sk-or-…9f2a',
          isPassword: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('OPENROUTER_API_KEY'), findsOneWidget);
    expect(find.textContaining('sk-or-…9f2a'), findsOneWidget);
    expect(_enabled(tester, 'hermes-env-save'), isFalse);
  });

  testWidgets('hides typed secrets and enables saving once a value exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const HermesEnvVar(name: 'TOKEN', isPassword: true)),
    );
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('hermes-env-value')),
    );
    expect(field.obscureText, isTrue);

    await tester.enterText(
      find.byKey(const ValueKey<String>('hermes-env-value')),
      'secret-value',
    );
    await tester.pump();
    expect(_enabled(tester, 'hermes-env-save'), isTrue);
  });

  testWidgets('a remove action only appears for a key that is set', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const HermesEnvVar(name: 'PLAIN_SETTING')));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('hermes-env-remove')), findsNothing);

    await tester.pumpWidget(
      _host(const HermesEnvVar(name: 'PLAIN_SETTING', isSet: true)),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('hermes-env-remove')),
      findsOneWidget,
    );
  });
}
