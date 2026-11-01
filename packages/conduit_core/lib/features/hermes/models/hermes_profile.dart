import 'package:conduit_core/features/hermes/services/hermes_identifier.dart';

/// One Hermes profile, from `GET /api/profiles` (`{profiles: [...]}`).
final class HermesProfileSummary {
  const HermesProfileSummary({
    required this.name,
    this.path = '',
    this.isDefault = false,
    this.model,
    this.provider,
    this.hasEnv = false,
    this.skillCount = 0,
    this.gatewayRunning = false,
    this.description = '',
    this.descriptionAuto = false,
    this.displayName = '',
    this.botTitle = '',
    this.hasAlias = false,
  });

  final String name;
  final String path;
  final bool isDefault;
  final String? model;
  final String? provider;

  /// Whether the profile has its own `.env`.
  final bool hasEnv;

  final int skillCount;

  /// Whether a gateway is running for this profile right now.
  final bool gatewayRunning;

  final String description;
  final bool descriptionAuto;
  final String displayName;
  final String botTitle;
  final bool hasAlias;

  String get title => displayName.isNotEmpty
      ? displayName
      : (botTitle.isNotEmpty ? botTitle : name);

  String get modelLabel {
    if (model == null || model!.isEmpty) return '';
    return provider == null || provider!.isEmpty
        ? model!
        : '${provider!} · ${model!}';
  }

  static HermesProfileSummary? fromJson(Map<String, dynamic> json) {
    final name = validateHermesBoundedString(json['name'], maxCharacters: 128);
    if (name == null || name.isEmpty) return null;
    final skills = json['skill_count'];
    return HermesProfileSummary(
      name: name,
      path: validateHermesBoundedString(json['path'], maxCharacters: 4096) ?? '',
      isDefault: json['is_default'] == true,
      model: validateHermesBoundedString(json['model'], maxCharacters: 256),
      provider: validateHermesBoundedString(json['provider'], maxCharacters: 128),
      hasEnv: json['has_env'] == true,
      skillCount: skills is num ? skills.toInt().clamp(0, 100000) : 0,
      gatewayRunning: json['gateway_running'] == true,
      description:
          validateHermesBoundedString(
            json['description'],
            maxCharacters: 2048,
          ) ??
          '',
      descriptionAuto: json['description_auto'] == true,
      displayName:
          validateHermesBoundedString(
            json['display_name'],
            maxCharacters: 256,
          ) ??
          '',
      botTitle:
          validateHermesBoundedString(json['bot_title'], maxCharacters: 256) ??
          '',
      hasAlias: json['has_alias'] == true,
    );
  }

  static List<HermesProfileSummary> listFromJson(Object? json) {
    if (json is! Map) return const [];
    final rows = json['profiles'];
    if (rows is! List) return const [];
    final out = <HermesProfileSummary>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final profile = fromJson(Map<String, dynamic>.from(row));
      if (profile != null) out.add(profile);
    }
    return List.unmodifiable(out);
  }
}

/// `GET /api/profiles/active`: the sticky default vs this dashboard's profile.
final class HermesProfileActive {
  const HermesProfileActive({required this.active, required this.current});

  final String active;
  final String current;

  static HermesProfileActive? fromJson(Object? json) {
    if (json is! Map) return null;
    final active = validateHermesBoundedString(
      json['active'],
      maxCharacters: 128,
    );
    final current = validateHermesBoundedString(
      json['current'],
      maxCharacters: 128,
    );
    if (active == null || current == null) return null;
    return HermesProfileActive(active: active, current: current);
  }
}

/// `GET /api/profiles/{name}/soul`.
final class HermesProfileSoul {
  const HermesProfileSoul({required this.content, this.exists = false});

  final String content;
  final bool exists;

  static HermesProfileSoul? fromJson(Object? json) {
    if (json is! Map) return null;
    final content = json['content'];
    if (content is! String) return null;
    return HermesProfileSoul(
      content: content,
      exists: json['exists'] == true,
    );
  }
}
