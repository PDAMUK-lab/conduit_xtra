import 'package:conduit/features/hermes/views/hermes_messaging_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit_core/features/hermes/models/hermes_messaging.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _platforms = [
  HermesMessagingPlatform(
    id: 'ntfy',
    name: 'ntfy',
    enabled: true,
    configured: true,
    state: 'connected',
  ),
  HermesMessagingPlatform(
    id: 'telegram',
    name: 'Telegram',
    enabled: true,
    configured: false,
    state: 'enabled',
  ),
  HermesMessagingPlatform(id: 'discord', name: 'Discord'),
];

Widget _host(List<HermesMessagingPlatform> platforms) => ProviderScope(
  overrides: [
    hermesMessagingProvider.overrideWith((ref) async => platforms),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const HermesMessagingPage(),
  ),
);

void main() {
  testWidgets('lists channels with their state and a toggle each', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_platforms));
    await tester.pumpAndSettle();

    expect(find.text('ntfy'), findsOneWidget);
    expect(find.text('Telegram'), findsOneWidget);
    expect(find.text('Discord'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);
    expect(find.text('Enabled — needs setup'), findsOneWidget);
    expect(find.text('Disabled'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('hermes-messaging-toggle-ntfy')),
      findsOneWidget,
    );
  });

  testWidgets('no channels says so', (tester) async {
    await tester.pumpWidget(_host(const []));
    await tester.pumpAndSettle();
    expect(find.text('No channels.'), findsOneWidget);
  });
}
