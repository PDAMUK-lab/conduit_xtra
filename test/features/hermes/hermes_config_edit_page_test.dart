import 'package:conduit/features/hermes/views/hermes_config_edit_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit/shared/widgets/conduit_components.dart';
import 'package:conduit_core/features/hermes/models/hermes_config_view.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _config = HermesRawConfig(
  yaml: 'model: a\nprovider: auto\n',
  path: '/home/hermes/.hermes/config.yaml',
);

Widget _page({String? restoreText}) => ProviderScope(
  overrides: [
    hermesRawConfigProvider.overrideWith((ref) async => _config),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: HermesConfigEditPage(restoreText: restoreText),
  ),
);

Future<bool> _saveEnabled(WidgetTester tester) async {
  final finder = find.byKey(const ValueKey<String>('hermes-config-save'));
  if (finder.evaluate().isEmpty) {
    // The button sits below the fold; bring it into the tree first.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await tester.pumpAndSettle();
  }
  if (finder.evaluate().isEmpty) return false;
  final button = tester.widget<ConduitButton>(finder);
  return button.onPressed != null;
}

void main() {
  testWidgets('opens with the file text and no diff yet', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    expect(find.text('/home/hermes/.hermes/config.yaml'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('hermes-config-editor')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('hermes-config-save')),
        findsNothing);
  });

  testWidgets('review shows the diff and gates saving on the typed name', (
    tester,
  ) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('hermes-config-editor')),
      'model: b\nprovider: auto\n',
    );
    await tester.tap(find.byKey(const ValueKey<String>('hermes-config-review')));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 added'), findsOneWidget);
    expect(find.textContaining('1 removed'), findsOneWidget);
    expect(find.textContaining('−model: a'), findsOneWidget);
    expect(find.textContaining('+model: b'), findsOneWidget);
    expect(await _saveEnabled(tester), isFalse);

    await tester.enterText(
      find.byKey(const ValueKey<String>('hermes-config-confirm')),
      'config.yaml',
    );
    await tester.pumpAndSettle();
    expect(await _saveEnabled(tester), isTrue);

    await tester.enterText(
      find.byKey(const ValueKey<String>('hermes-config-confirm')),
      'config',
    );
    await tester.pumpAndSettle();
    expect(await _saveEnabled(tester), isFalse);
  });

  testWidgets('rejects YAML that is not a mapping', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('hermes-config-editor')),
      '- just\n- a list\n',
    );
    await tester.tap(find.byKey(const ValueKey<String>('hermes-config-review')));
    await tester.pumpAndSettle();

    expect(find.textContaining('must be a YAML mapping'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('hermes-config-save')),
        findsNothing);
  });

  testWidgets('an unchanged document cannot be saved', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('hermes-config-review')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('hermes-config-confirm')),
      'config.yaml',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('0 added'), findsOneWidget);
    expect(find.textContaining('0 removed'), findsOneWidget);
  });

  testWidgets('a restore opens with the previous text', (tester) async {
    await tester.pumpWidget(_page(restoreText: 'model: old\nprovider: auto\n'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('hermes-config-review')));
    await tester.pumpAndSettle();
    if (find.textContaining('−model: a').evaluate().isEmpty) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await tester.pumpAndSettle();
    }

    expect(find.textContaining('−model: a'), findsOneWidget);
    expect(find.textContaining('+model: old'), findsOneWidget);
  });
}
