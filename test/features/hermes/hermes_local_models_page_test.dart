import 'package:conduit/features/hermes/views/hermes_local_models_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit_core/features/hermes/models/hermes_local_models.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _status = HermesLocalModelStatus(
  enabled: false,
  tag: 'b11671',
  runtimeInstalled: false,
  serverRunning: false,
  modelsDir: '/home/hermes/.hermes/models',
);

const _hardware = HermesLocalHardware(
  gpuName: 'NVIDIA GeForce GTX 1070 with Max-Q Design',
  vramTotalBytes: 8589934592,
  vramUsableBytes: 7000000000,
  vramUsedBytes: 7689207808,
  ramTotalBytes: 16646877184,
  ramAvailableBytes: 6029570048,
  vramLabel: '8.0 GB',
);

Widget _host({
  HermesLocalModelStatus? status = _status,
  HermesLocalHardware? hardware = _hardware,
}) => ProviderScope(
  overrides: [
    hermesLocalModelStatusProvider.overrideWith((ref) async => status),
    hermesLocalModelHardwareProvider.overrideWith((ref) async => hardware),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const HermesLocalModelsPage(),
  ),
);

void main() {
  testWidgets('shows manager state, models and hardware', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('Local models'), findsOneWidget);
    expect(find.textContaining('disabled'), findsWidgets);
    expect(find.textContaining('not installed'), findsWidgets);
    expect(find.textContaining('stopped'), findsWidgets);
    expect(find.text('No models staged.'), findsOneWidget);
    expect(find.textContaining('1070'), findsOneWidget);
    expect(find.textContaining('7.2 GB / 8.0 GB'), findsOneWidget);
    expect(find.textContaining('outside this manager'), findsOneWidget);
  });

  testWidgets('an externally served router is named', (tester) async {
    await tester.pumpWidget(
      _host(
        status: const HermesLocalModelStatus(
          enabled: false,
          externalServer: HermesExternalServer(
            baseUrl: 'http://127.0.0.1:8080/v1',
            model: 'ornith-1.5-9b-heretic',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('did not start'), findsOneWidget);
    expect(find.textContaining('127.0.0.1:8080'), findsWidgets);
    expect(find.textContaining('ornith-1.5-9b-heretic'), findsWidgets);
  });

  testWidgets('the fleet lists peers and their state', (tester) async {
    await tester.pumpWidget(
      _host(
        status: const HermesLocalModelStatus(
          enabled: true,
          peers: [
            HermesLocalPeer(
              name: 'desktop',
              baseUrl: 'http://20.20.0.40:8080/v1',
              canRaise: true,
            ),
            HermesLocalPeer(
              name: 'laptop',
              baseUrl: 'http://127.0.0.1:8080/v1',
              up: true,
              model: 'ornith-1.5-9b-heretic',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.text('Fleet'), findsOneWidget);
    expect(find.text('desktop'), findsOneWidget);
    expect(find.textContaining('asleep'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('hermes-peer-raise-desktop')),
      findsOneWidget,
    );
    expect(find.textContaining('serving ornith-1.5-9b-heretic'), findsOneWidget);
  });

  testWidgets('a running manager with models lists them', (tester) async {
    await tester.pumpWidget(
      _host(
        status: const HermesLocalModelStatus(
          enabled: true,
          runtimeInstalled: true,
          runtimeBackend: 'cuda',
          serverRunning: true,
          serverBaseUrl: 'http://127.0.0.1:8080',
          activeModelId: 'ornith9h-q4-best',
          models: [
            HermesLocalModel(
              id: 'ornith9h-q4-best',
              name: 'Ornith 9H',
              sizeBytes: 5800000000,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('enabled'), findsWidgets);
    expect(find.textContaining('127.0.0.1:8080'), findsOneWidget);
    expect(find.text('Ornith 9H'), findsOneWidget);
    expect(find.textContaining('5.4 GB'), findsOneWidget);
    expect(find.textContaining('outside this manager'), findsNothing);
  });
}
