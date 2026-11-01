import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/models/hermes_toolsets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the bare array the list route returns', () {
    final toolsets = HermesToolsetSummary.listFromJson([
      {
        'name': 'web',
        'label': 'Web',
        'description': 'Search and fetch',
        'platform': 'cli',
        'platform_label': 'CLI',
        'enabled': true,
        'available': true,
        'configured': true,
        'tools': ['web_search', 'web_extract'],
      },
      {
        'name': 'computer',
        'label': 'Computer use',
        'enabled': false,
        'configured': false,
        'tools': <String>[],
      },
    ]);
    check(toolsets).length.equals(2);
    check(toolsets.first.name).equals('web');
    check(toolsets.first.label).equals('Web');
    check(toolsets.first.platformLabel).equals('CLI');
    check(toolsets.first.tools).deepEquals(['web_search', 'web_extract']);
    check(toolsets.last.enabled).isFalse();
    check(toolsets.last.configured).isFalse();
  });

  test('drops a toolset without a name', () {
    final toolsets = HermesToolsetSummary.listFromJson([
      {'label': 'No name'},
      {'name': 'ok'},
      'nope',
    ]);
    check(toolsets.map((t) => t.name)).deepEquals(['ok']);
  });

  test('parses provider config with env state and the active provider', () {
    final config = HermesToolsetConfig.fromJson({
      'name': 'web',
      'has_category': true,
      'active_provider': 'tavily',
      'providers': [
        {
          'name': 'tavily',
          'badge': 'TAV',
          'tag': 'search',
          'is_active': true,
          'status': 'ready',
          'env_vars': [
            {'key': 'TAVILY_API_KEY', 'prompt': 'API key', 'is_set': true},
            {'key': 'TAVILY_BASE', 'prompt': 'Base URL', 'is_set': false},
          ],
          'requires_nous_auth': false,
        },
      ],
    });
    check(config).isNotNull();
    check(config!.hasCategory).isTrue();
    check(config.activeProvider).equals('tavily');
    check(config.providers.single.isActive).isTrue();
    check(config.providers.single.envVars.map((e) => e.key)).deepEquals([
      'TAVILY_API_KEY',
      'TAVILY_BASE',
    ]);
    check(config.providers.single.envVars.first.isSet).isTrue();
    check(config.providers.single.envVars.last.isSet).isFalse();
  });

  test('parses the model catalog with current and default', () {
    final models = HermesToolsetModels.fromJson({
      'name': 'web',
      'has_models': true,
      'provider': 'openai',
      'plugin': 'web_models',
      'models': [
        {'id': 'gpt-5-mini', 'display': 'GPT-5 mini', 'price': r'$0.15/M', 'speed': 'fast'},
      ],
      'current': 'gpt-5-mini',
      'default': 'gpt-5-mini',
    });
    check(models).isNotNull();
    check(models!.hasModels).isTrue();
    check(models.current).equals('gpt-5-mini');
    check(models.defaultModel).equals('gpt-5-mini');
    check(models.models.single.display).equals('GPT-5 mini');
    check(models.models.single.price).equals(r'$0.15/M');
  });

  test('non-map bodies are null rather than throws', () {
    check(HermesToolsetConfig.fromJson(null)).isNull();
    check(HermesToolsetModels.fromJson('x')).isNull();
  });
}
