import 'package:conduit/features/hermes/views/hermes_memory_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit_core/features/hermes/models/hermes_memory.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _status = HermesMemoryStatus(
  active: 'hermesmemory',
  providers: [
    HermesMemoryProvider(
      name: 'hermesmemory',
      description: 'Tiered memory for Hermes.',
      status: 'ready',
      available: true,
      configured: true,
    ),
    HermesMemoryProvider(
      name: 'byterover',
      description: 'ByteRover knowledge tree.',
      status: 'unavailable',
      available: false,
      configured: true,
    ),
  ],
  memoryFileBytes: 2048,
  userFileBytes: 512,
);

Widget _page(HermesMemoryStatus? status) => ProviderScope(
  overrides: [
    hermesMemoryStatusProvider.overrideWith((ref) async => status),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const HermesMemoryPage(),
  ),
);

void main() {
  testWidgets('shows the active provider, readiness and built-in files', (
    tester,
  ) async {
    await tester.pumpWidget(_page(_status));
    await tester.pumpAndSettle();

    expect(find.text('hermesmemory'), findsNWidgets(2)); // active row + card
    expect(find.text('byterover'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('unavailable'), findsOneWidget);
    expect(find.text('MEMORY.md'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.text('512 B'), findsOneWidget);
    // The active provider offers no switch; the unavailable one cannot be used.
    expect(find.text('Use'), findsNothing);
  });

  testWidgets('offers a switch to a provider that is ready but inactive', (
    tester,
  ) async {
    const other = HermesMemoryStatus(
      active: 'builtin',
      providers: [
        HermesMemoryProvider(
          name: 'hermesmemory',
          description: 'Tiered memory for Hermes.',
          status: 'ready',
          available: true,
          configured: true,
        ),
      ],
    );
    await tester.pumpWidget(_page(other));
    await tester.pumpAndSettle();

    expect(find.text('Use'), findsOneWidget);
  });

  testWidgets('says so when no provider is active', (tester) async {
    const none = HermesMemoryStatus(active: '', providers: []);
    await tester.pumpWidget(_page(none));
    await tester.pumpAndSettle();

    expect(find.text('No memory provider is active.'), findsOneWidget);
  });
}
