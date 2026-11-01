import 'package:conduit/features/hermes/views/hermes_analytics_page.dart';
import 'package:conduit/features/hermes/views/hermes_logs_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/tweakcn_themes.dart';
import 'package:conduit_core/features/hermes/models/hermes_analytics.dart';
import 'package:conduit_core/features/hermes/models/hermes_logs.dart';
import 'package:conduit_core/features/hermes/providers/hermes_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _usage = HermesUsageAnalytics(
  totals: HermesUsageTotals(
    inputTokens: 1500,
    outputTokens: 500,
    estimatedCost: 0.12,
    sessions: 4,
    apiCalls: 9,
  ),
  byModel: [
    HermesModelUsage(
      model: 'deepseek-v4.1-flash',
      provider: 'openrouter',
      totals: HermesUsageTotals(
        inputTokens: 1500,
        outputTokens: 500,
        sessions: 4,
      ),
    ),
  ],
  periodDays: 30,
  tools: {'terminal': 12, 'web_search': 2},
);

Widget _analytics() => ProviderScope(
  overrides: [
    hermesUsageAnalyticsProvider.overrideWith((ref, days) async => _usage),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const HermesAnalyticsPage(),
  ),
);

Widget _logs(HermesLogTail? tail) => ProviderScope(
  overrides: [
    hermesLogTailProvider.overrideWith((ref, query) async => tail),
  ],
  child: MaterialApp(
    theme: AppTheme.light(TweakcnThemes.t3Chat),
    localizationsDelegates: conduitLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const HermesLogsPage(),
  ),
);

void main() {
  testWidgets('shows totals, model breakdown and tools', (tester) async {
    await tester.pumpWidget(_analytics());
    await tester.pumpAndSettle();

    expect(find.text('2.0k'), findsWidgets); // tokens
    expect(find.text('4'), findsWidgets); // sessions
    expect(find.text('\$0.12'), findsWidgets); // cost
    expect(find.text('deepseek-v4.1-flash'), findsOneWidget);
    expect(find.text('terminal'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('says when there is no usage', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hermesUsageAnalyticsProvider.overrideWith(
            (ref, days) async => const HermesUsageAnalytics(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(TweakcnThemes.t3Chat),
          localizationsDelegates: conduitLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HermesAnalyticsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No usage in this period.'), findsOneWidget);
  });

  testWidgets('shows a log tail', (tester) async {
    await tester.pumpWidget(
      _logs(
        const HermesLogTail(
          file: 'agent',
          lines: ['2026-10-31 INFO started', '2026-10-31 ERROR broke'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('INFO started'), findsOneWidget);
    expect(find.textContaining('ERROR broke'), findsOneWidget);
  });

  testWidgets('says when the log is empty', (tester) async {
    await tester.pumpWidget(_logs(const HermesLogTail(file: 'agent')));
    await tester.pumpAndSettle();
    expect(find.text('No lines.'), findsOneWidget);
  });
}
