/// One slot of a blueprint form (`GET /api/cron/blueprints`).
///
/// Types the server emits: `time` (HH:MM), `enum` (choose from [options]),
/// `text`, and `weekdays` (a named recurrence preset). A slot with
/// [strict] false offers [options] as suggestions and accepts any value.
final class HermesBlueprintField {
  const HermesBlueprintField({
    required this.name,
    required this.type,
    required this.label,
    this.defaultValue,
    this.options = const [],
    this.optional = false,
    this.strict = true,
    this.help = '',
  });

  final String name;
  final String type;
  final String label;
  final String? defaultValue;
  final List<String> options;
  final bool optional;
  final bool strict;
  final String help;

  bool get isEnum => type == 'enum' || type == 'weekdays';
  bool get isTime => type == 'time';

  static HermesBlueprintField? fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? '';
    final label = json['label']?.toString().trim() ?? '';
    if (name.isEmpty || label.isEmpty) return null;
    final options = <String>[];
    for (final option in (json['options'] as List? ?? const [])) {
      final value = option?.toString().trim() ?? '';
      if (value.isNotEmpty) options.add(value);
    }
    final fallback = json['default'];
    return HermesBlueprintField(
      name: name,
      type: json['type']?.toString() ?? 'text',
      label: label,
      defaultValue: fallback?.toString(),
      options: List.unmodifiable(options),
      optional: json['optional'] == true,
      strict: json['strict'] != false,
      help: json['help']?.toString() ?? '',
    );
  }
}

/// One entry of the blueprint catalog.
final class HermesBlueprint {
  const HermesBlueprint({
    required this.key,
    required this.title,
    required this.description,
    this.category = '',
    this.tags = const [],
    this.source = 'builtin',
    this.plugin,
    this.schedule = '',
    this.scheduleHuman = '',
    this.fields = const [],
  });

  final String key;
  final String title;
  final String description;
  final String category;
  final List<String> tags;
  final String source;
  final String? plugin;
  final String schedule;
  final String scheduleHuman;
  final List<HermesBlueprintField> fields;

  bool get isPlugin => source == 'plugin';

  static HermesBlueprint? fromJson(Map<String, dynamic> json) {
    final key = json['key']?.toString().trim() ?? '';
    final title = json['title']?.toString().trim() ?? '';
    if (key.isEmpty || title.isEmpty) return null;
    final fields = <HermesBlueprintField>[];
    for (final row in (json['fields'] as List? ?? const [])) {
      if (row is! Map) continue;
      final field = HermesBlueprintField.fromJson(
        Map<String, dynamic>.from(row),
      );
      if (field != null) fields.add(field);
    }
    final tags = <String>[];
    for (final tag in (json['tags'] as List? ?? const [])) {
      final value = tag?.toString().trim() ?? '';
      if (value.isNotEmpty) tags.add(value);
    }
    return HermesBlueprint(
      key: key,
      title: title,
      description: json['description']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      tags: List.unmodifiable(tags),
      source: json['source']?.toString() ?? 'builtin',
      plugin: json['plugin']?.toString(),
      schedule: json['schedule']?.toString() ?? '',
      scheduleHuman: json['scheduleHuman']?.toString() ?? '',
      fields: List.unmodifiable(fields),
    );
  }

  static List<HermesBlueprint> listFromJson(Object? json) {
    if (json is! Map || json['blueprints'] is! List) return const [];
    final out = <HermesBlueprint>[];
    for (final row in json['blueprints'] as List) {
      if (row is! Map) continue;
      final blueprint = fromJson(Map<String, dynamic>.from(row));
      if (blueprint != null) out.add(blueprint);
    }
    return List.unmodifiable(out);
  }
}
