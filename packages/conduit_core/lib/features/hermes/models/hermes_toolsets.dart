import 'package:conduit_core/features/hermes/services/hermes_identifier.dart';

/// One configurable toolset, as `GET /api/tools/toolsets` reports it (the
/// route returns a bare array, not an envelope).
final class HermesToolsetSummary {
  const HermesToolsetSummary({
    required this.name,
    required this.label,
    this.description = '',
    this.platformLabel = '',
    this.enabled = false,
    this.configured = false,
    this.tools = const [],
  });

  final String name;
  final String label;
  final String description;
  final String platformLabel;
  final bool enabled;

  /// Whether the toolset's own credentials/keys are present. A toolset can be
  /// enabled but not configured, and then its tools fail at call time.
  final bool configured;

  final List<String> tools;

  static HermesToolsetSummary? fromJson(Map<String, dynamic> json) {
    final name = validateHermesOpaqueIdentifier(json['name']);
    if (name == null) return null;
    final rawTools = json['tools'];
    final tools = <String>[];
    if (rawTools is List) {
      for (final tool in rawTools) {
        final value = validateHermesBoundedString(tool, maxCharacters: 128);
        if (value != null) tools.add(value);
        if (tools.length >= 256) break;
      }
    }
    return HermesToolsetSummary(
      name: name,
      label:
          validateHermesBoundedString(json['label'], maxCharacters: 128) ??
          name,
      description:
          validateHermesBoundedString(
            json['description'],
            maxCharacters: 1024,
          ) ??
          '',
      platformLabel:
          validateHermesBoundedString(
            json['platform_label'],
            maxCharacters: 64,
          ) ??
          '',
      enabled: json['enabled'] == true,
      configured: json['configured'] == true,
      tools: List.unmodifiable(tools),
    );
  }

  static List<HermesToolsetSummary> listFromJson(Object? json) {
    if (json is! List) return const [];
    final out = <HermesToolsetSummary>[];
    for (final row in json) {
      if (row is! Map) continue;
      final toolset = fromJson(Map<String, dynamic>.from(row));
      if (toolset != null) out.add(toolset);
    }
    return List.unmodifiable(out);
  }
}

/// One env variable a provider needs, with whether the profile already has it.
final class HermesToolsetEnvVar {
  const HermesToolsetEnvVar({
    required this.key,
    this.prompt = '',
    this.isSet = false,
    this.url,
  });

  final String key;
  final String prompt;
  final bool isSet;
  final String? url;

  static HermesToolsetEnvVar? fromJson(Map<String, dynamic> json) {
    final key = validateHermesBoundedString(json['key'], maxCharacters: 128);
    if (key == null) return null;
    return HermesToolsetEnvVar(
      key: key,
      prompt:
          validateHermesBoundedString(json['prompt'], maxCharacters: 256) ?? '',
      isSet: json['is_set'] == true,
      url: validateHermesBoundedString(json['url'], maxCharacters: 512),
    );
  }
}

/// A provider a toolset can run on (search/extract backends, model plugins…).
final class HermesToolsetProvider {
  const HermesToolsetProvider({
    required this.name,
    this.badge = '',
    this.tag = '',
    this.isActive = false,
    this.status = '',
    this.envVars = const [],
    this.requiresNousAuth = false,
  });

  final String name;
  final String badge;
  final String tag;
  final bool isActive;

  /// The provider's readiness word (`ready`, `needs key`, …), when reported.
  final String status;

  final List<HermesToolsetEnvVar> envVars;
  final bool requiresNousAuth;

  static HermesToolsetProvider? fromJson(Map<String, dynamic> json) {
    final name = validateHermesBoundedString(json['name'], maxCharacters: 128);
    if (name == null) return null;
    final envVars = <HermesToolsetEnvVar>[];
    for (final row in (json['env_vars'] as List? ?? const [])) {
      if (row is! Map) continue;
      final env = HermesToolsetEnvVar.fromJson(Map<String, dynamic>.from(row));
      if (env != null) envVars.add(env);
      if (envVars.length >= 32) break;
    }
    return HermesToolsetProvider(
      name: name,
      badge:
          validateHermesBoundedString(json['badge'], maxCharacters: 32) ?? '',
      tag: validateHermesBoundedString(json['tag'], maxCharacters: 64) ?? '',
      isActive: json['is_active'] == true,
      status:
          validateHermesBoundedString(json['status'], maxCharacters: 64) ?? '',
      envVars: List.unmodifiable(envVars),
      requiresNousAuth: json['requires_nous_auth'] == true,
    );
  }
}

/// `GET /api/tools/toolsets/{name}/config`.
final class HermesToolsetConfig {
  const HermesToolsetConfig({
    required this.name,
    this.hasCategory = false,
    this.providers = const [],
    this.activeProvider,
    this.activeSearchBackend,
    this.activeExtractBackend,
  });

  final String name;
  final bool hasCategory;
  final List<HermesToolsetProvider> providers;
  final String? activeProvider;
  final String? activeSearchBackend;
  final String? activeExtractBackend;

  bool get hasSubCapabilities =>
      activeSearchBackend != null || activeExtractBackend != null;

  static HermesToolsetConfig? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = validateHermesOpaqueIdentifier(json['name']);
    if (name == null) return null;
    final providers = <HermesToolsetProvider>[];
    for (final row in (json['providers'] as List? ?? const [])) {
      if (row is! Map) continue;
      final provider = HermesToolsetProvider.fromJson(
        Map<String, dynamic>.from(row),
      );
      if (provider != null) providers.add(provider);
      if (providers.length >= 64) break;
    }
    return HermesToolsetConfig(
      name: name,
      hasCategory: json['has_category'] == true,
      providers: List.unmodifiable(providers),
      activeProvider: validateHermesBoundedString(
        json['active_provider'],
        maxCharacters: 128,
      ),
      activeSearchBackend: validateHermesBoundedString(
        json['active_search_backend'],
        maxCharacters: 128,
      ),
      activeExtractBackend: validateHermesBoundedString(
        json['active_extract_backend'],
        maxCharacters: 128,
      ),
    );
  }
}

/// One model a toolset can use.
final class HermesToolsetModel {
  const HermesToolsetModel({
    required this.id,
    this.display = '',
    this.speed = '',
    this.strengths = '',
    this.price = '',
  });

  final String id;
  final String display;
  final String speed;
  final String strengths;
  final String price;

  static HermesToolsetModel? fromJson(Map<String, dynamic> json) {
    final id = validateHermesBoundedString(json['id'], maxCharacters: 256);
    if (id == null) return null;
    return HermesToolsetModel(
      id: id,
      display:
          validateHermesBoundedString(json['display'], maxCharacters: 256) ??
          id,
      speed: validateHermesBoundedString(json['speed'], maxCharacters: 64) ?? '',
      strengths:
          validateHermesBoundedString(json['strengths'], maxCharacters: 256) ??
          '',
      price: validateHermesBoundedString(json['price'], maxCharacters: 64) ?? '',
    );
  }
}

/// `GET /api/tools/toolsets/{name}/models`.
final class HermesToolsetModels {
  const HermesToolsetModels({
    required this.name,
    this.hasModels = false,
    this.provider,
    this.models = const [],
    this.current,
    this.defaultModel,
  });

  final String name;
  final bool hasModels;
  final String? provider;
  final List<HermesToolsetModel> models;
  final String? current;
  final String? defaultModel;

  static HermesToolsetModels? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = validateHermesOpaqueIdentifier(json['name']);
    if (name == null) return null;
    final models = <HermesToolsetModel>[];
    for (final row in (json['models'] as List? ?? const [])) {
      if (row is! Map) continue;
      final model = HermesToolsetModel.fromJson(Map<String, dynamic>.from(row));
      if (model != null) models.add(model);
      if (models.length >= 256) break;
    }
    return HermesToolsetModels(
      name: name,
      hasModels: json['has_models'] == true,
      provider: validateHermesBoundedString(
        json['provider'],
        maxCharacters: 128,
      ),
      models: List.unmodifiable(models),
      current: validateHermesBoundedString(json['current'], maxCharacters: 256),
      defaultModel: validateHermesBoundedString(
        json['default'],
        maxCharacters: 256,
      ),
    );
  }
}
