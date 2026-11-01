/// `GET /api/config/raw`: the whole config.yaml and the path it came from.
///
/// Saving is a full-document replacement on the server, so this model is
/// read-only by design for now; the editor that writes it lands separately.
final class HermesRawConfig {
  const HermesRawConfig({required this.yaml, required this.path});

  final String yaml;
  final String path;

  static HermesRawConfig? fromJson(Object? json) {
    if (json is! Map) return null;
    final yaml = json['yaml'];
    final path = json['path'];
    if (yaml is! String || path is! String) return null;
    return HermesRawConfig(yaml: yaml, path: path);
  }
}

/// One key from `GET /api/env` (a map of NAME → this shape).
///
/// Values arrive redacted; the app never shows or stores the plaintext.
final class HermesEnvVar {
  const HermesEnvVar({
    required this.name,
    this.isSet = false,
    this.redactedValue = '',
    this.description = '',
    this.category = '',
    this.isPassword = false,
    this.channelManaged = false,
    this.custom = false,
    this.advanced = false,
  });

  final String name;
  final bool isSet;
  final String redactedValue;
  final String description;
  final String category;
  final bool isPassword;
  final bool channelManaged;
  final bool custom;
  final bool advanced;

  static HermesEnvVar? fromJson(String name, Object? json) {
    if (json is! Map) return null;
    if (name.isEmpty) return null;
    return HermesEnvVar(
      name: name,
      isSet: json['is_set'] == true,
      redactedValue: (json['redacted_value']?.toString() ?? '').trim(),
      description: (json['description']?.toString() ?? '').trim(),
      category: (json['category']?.toString() ?? '').trim(),
      isPassword: json['is_password'] == true,
      channelManaged: json['channel_managed'] == true,
      custom: json['custom'] == true,
      advanced: json['advanced'] == true,
    );
  }

  static List<HermesEnvVar> listFromJson(Object? json) {
    if (json is! Map) return const [];
    final out = <HermesEnvVar>[];
    json.forEach((key, value) {
      final row = fromJson(key.toString(), value);
      if (row != null) out.add(row);
    });
    out.sort((a, b) => a.name.compareTo(b.name));
    return List.unmodifiable(out);
  }

  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return name.toLowerCase().contains(needle) ||
        description.toLowerCase().contains(needle) ||
        category.toLowerCase().contains(needle);
  }
}
