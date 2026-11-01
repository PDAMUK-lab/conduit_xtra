/// `GET /api/status` — the few fields worth putting on a one-line health strip.
final class HermesHealth {
  const HermesHealth({
    this.overall = 'unknown',
    this.version = '',
    this.gatewayRunning = false,
    this.gatewayState,
    this.diskFreeMb,
    this.diskTotalMb,
    this.diskPressure = 'unknown',
    this.activeSessions = 0,
  });

  final String overall;
  final String version;
  final bool gatewayRunning;
  final String? gatewayState;
  final int? diskFreeMb;
  final int? diskTotalMb;
  final String diskPressure;
  final int activeSessions;

  bool get healthy => overall == 'ok';
  bool get degraded => overall == 'degraded' || overall == 'error';

  static int? _mb(Object? value) =>
      value is num ? value.toInt().clamp(0, 1 << 40) : null;

  static HermesHealth? fromJson(Object? json) {
    if (json is! Map) return null;
    final disk = json['disk'];
    final gateway = json['components'] is Map
        ? (json['components'] as Map)['gateway']
        : null;
    final active = json['active_sessions'];
    return HermesHealth(
      overall: json['overall']?.toString() ?? 'unknown',
      version: json['version']?.toString() ?? '',
      gatewayRunning: json['gateway_running'] == true,
      gatewayState: gateway is Map ? gateway['state']?.toString() : null,
      diskFreeMb: disk is Map ? _mb(disk['free_mb']) : null,
      diskTotalMb: disk is Map ? _mb(disk['total_mb']) : null,
      diskPressure: disk is Map ? (disk['pressure']?.toString() ?? 'unknown') : 'unknown',
      activeSessions: active is num ? active.toInt().clamp(0, 10000) : 0,
    );
  }
}
