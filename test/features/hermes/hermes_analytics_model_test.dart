import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/models/hermes_analytics.dart';
import 'package:conduit_core/features/hermes/models/hermes_logs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses usage totals, models, skills and tools', () {
    final usage = HermesUsageAnalytics.fromJson({
      'daily': [
        {'day': '2026-10-31', 'input_tokens': 10, 'output_tokens': 5},
      ],
      'by_model': [
        {
          'model': 'deepseek-v4.1-flash',
          'billing_provider': 'openrouter',
          'input_tokens': 1000,
          'output_tokens': 500,
          'estimated_cost': 0.12,
          'actual_cost': 0.1,
          'sessions': 4,
          'api_calls': 9,
          'last_used_at': 12,
        },
      ],
      'totals': {
        'total_input': 1000,
        'total_output': 500,
        'total_estimated_cost': 0.12,
        'total_actual_cost': 0.1,
        'total_sessions': 4,
        'total_api_calls': 9,
      },
      'period_days': 30,
      'skills': {'audit': 3},
      'tools': {'terminal': 12, 'web_search': 2},
    });
    check(usage).isNotNull();
    check(usage!.totals.inputTokens).equals(1000);
    check(usage.totals.outputTokens).equals(500);
    check(usage.totals.totalTokens).equals(1500);
    check(usage.totals.sessions).equals(4);
    check(usage.byModel.single.model).equals('deepseek-v4.1-flash');
    check(usage.byModel.single.provider).equals('openrouter');
    check(usage.byModel.single.totals.totalTokens).equals(1500);
    check(usage.periodDays).equals(30);
    check(usage.skills['audit']).equals(3);
    check(usage.tools['terminal']).equals(12);
  });

  test('parses model analytics with distinct_models', () {
    final models = HermesModelsAnalytics.fromJson({
      'models': [
        {'model': 'a', 'input_tokens': 1, 'output_tokens': 2, 'sessions': 1},
      ],
      'totals': {'total_input': 1, 'total_output': 2, 'total_sessions': 1, 'distinct_models': 7},
      'period_days': 7,
    });
    check(models).isNotNull();
    check(models!.models.single.model).equals('a');
    check(models.distinctModels).equals(7);
    check(models.periodDays).equals(7);
    check(models.totals.totalTokens).equals(3);
  });

  test('parses a log tail and drops empty lines', () {
    final tail = HermesLogTail.fromJson({
      'file': 'agent',
      'lines': ['2026-10-31 INFO one', '', '2026-10-31 ERROR two'],
    });
    check(tail).isNotNull();
    check(tail!.file).equals('agent');
    check(tail.lines).deepEquals(['2026-10-31 INFO one', '2026-10-31 ERROR two']);
    check(HermesLogTail.fromJson({'lines': ['x']})).isNull();
  });
}
