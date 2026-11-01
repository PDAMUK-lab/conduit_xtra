/// One choice from `GET /api/cron/delivery-targets`.
///
/// The server always lists `local` first (save-only, no channel), then each
/// configured gateway platform. A platform with no cron home channel is still
/// listed with [homeTargetSet] false so the picker can say so instead of
/// silently failing at delivery time.
final class HermesDeliveryTarget {
  const HermesDeliveryTarget({
    required this.id,
    required this.name,
    this.homeTargetSet = true,
    this.homeEnvVar,
  });

  final String id;
  final String name;
  final bool homeTargetSet;
  final String? homeEnvVar;

  bool get isLocal => id == 'local';

  static HermesDeliveryTarget? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    final name = json['name']?.toString().trim();
    return HermesDeliveryTarget(
      id: id,
      name: name == null || name.isEmpty ? id : name,
      homeTargetSet: json['home_target_set'] != false,
      homeEnvVar: json['home_env_var']?.toString(),
    );
  }

  static List<HermesDeliveryTarget> listFromJson(Object? json) {
    if (json is! Map || json['targets'] is! List) return const [];
    final out = <HermesDeliveryTarget>[];
    for (final row in json['targets'] as List) {
      if (row is! Map) continue;
      final target = fromJson(Map<String, dynamic>.from(row));
      if (target != null) out.add(target);
    }
    return List.unmodifiable(out);
  }
}
