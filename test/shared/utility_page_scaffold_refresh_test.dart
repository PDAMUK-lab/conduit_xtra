import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit/shared/widgets/utility_components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host({Future<void> Function()? onRefresh}) => MaterialApp(
  theme: AppTheme.light(TweakcnThemes.t3Chat),
  localizationsDelegates: conduitLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: UtilityPageScaffold.settings(
    title: 'Test',
    onRefresh: onRefresh,
    children: const [Text('content')],
  ),
);

void main() {
  testWidgets('a settings page has no pull-to-refresh unless asked for', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.byType(RefreshIndicator), findsNothing);
  });

  testWidgets('onRefresh wraps the page and fires on a pull', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(
        onRefresh: () async {
          calls++;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RefreshIndicator), findsOneWidget);

    await tester.fling(find.text('content'), const Offset(0, 400), 1200);
    await tester.pumpAndSettle();

    expect(calls, 1);
  });
}
