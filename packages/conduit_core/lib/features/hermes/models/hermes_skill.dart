import 'package:conduit_core/features/hermes/services/hermes_identifier.dart';

/// Longest skill name the dashboard will round-trip.
const int kMaxHermesSkillNameCharacters = 128;

/// Longest description the list shows before truncating.
const int kMaxHermesSkillDescriptionCharacters = 2048;

/// One installed skill, as `GET /api/skills` reports it.
///
/// The dashboard returns a bare JSON array; the fields that matter on a phone
/// are the name, description, category and whether the skill is enabled. Usage
/// counts and provenance are carried so the list can explain itself without a
/// second request.
final class HermesSkill {
  const HermesSkill({
    required this.name,
    required this.description,
    this.category,
    this.enabled = true,
    this.usage = 0,
    this.provenance,
  });

  final String name;
  final String description;

  /// Dashboard grouping (e.g. `software-development`), or null for top level.
  final String? category;

  final bool enabled;

  /// How often the agent has loaded this skill, when the server reports it.
  final int usage;

  /// Where the skill came from (`agent`, `bundled`, `hub`, …), when reported.
  final String? provenance;

  static HermesSkill? fromJson(Map<String, dynamic> json) {
    final name = validateHermesOpaqueIdentifier(json['name']);
    if (name == null || name.length > kMaxHermesSkillNameCharacters) {
      return null;
    }
    final rawDescription = json['description']?.toString().trim() ?? '';
    final description = rawDescription.length > kMaxHermesSkillDescriptionCharacters
        ? rawDescription.substring(0, kMaxHermesSkillDescriptionCharacters)
        : rawDescription;
    final rawUsage = json['usage'];
    return HermesSkill(
      name: name,
      description: description,
      category: validateHermesOpaqueIdentifier(json['category']),
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      usage: rawUsage is num ? rawUsage.toInt().clamp(0, 1 << 30) : 0,
      provenance: validateHermesOpaqueIdentifier(json['provenance']),
    );
  }

  /// Parses `GET /api/skills` (a JSON array), dropping unusable rows.
  static List<HermesSkill> listFromJson(Object? json) {
    if (json is! List) return const [];
    final skills = <HermesSkill>[];
    for (final row in json) {
      if (row is! Map) continue;
      final skill = HermesSkill.fromJson(Map<String, dynamic>.from(row));
      if (skill != null) skills.add(skill);
    }
    return List.unmodifiable(skills);
  }

  /// Case-insensitive match against name, description and category, for the
  /// list's search field.
  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return name.toLowerCase().contains(needle) ||
        description.toLowerCase().contains(needle) ||
        (category?.toLowerCase().contains(needle) ?? false);
  }
}
