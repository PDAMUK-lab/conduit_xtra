/// One credential a messaging platform needs (`env_vars` in
/// `GET /api/messaging/platforms`). Values are never shown: only whether the
/// key is set and what it is for.
final class HermesMessagingEnvVar {
  const HermesMessagingEnvVar({
    required this.key,
    this.required = false,
    this.isSet = false,
    this.description = '',
    this.isPassword = false,
  });

  final String key;
  final bool required;
  final bool isSet;
  final String description;
  final bool isPassword;

  static HermesMessagingEnvVar? fromJson(Map<String, dynamic> json) {
    final key = json['key']?.toString().trim() ?? '';
    if (key.isEmpty) return null;
    return HermesMessagingEnvVar(
      key: key,
      required: json['required'] == true,
      isSet: json['is_set'] == true,
      description: json['description']?.toString() ?? '',
      isPassword: json['is_password'] == true,
    );
  }
}

/// One channel from `GET /api/messaging/platforms`.
final class HermesMessagingPlatform {
  const HermesMessagingPlatform({
    required this.id,
    required this.name,
    this.description = '',
    this.enabled = false,
    this.configured = false,
    this.gatewayRunning = false,
    this.state = 'disabled',
    this.errorMessage,
    this.homeChannel,
    this.envVars = const [],
  });

  final String id;
  final String name;
  final String description;
  final bool enabled;
  final bool configured;
  final bool gatewayRunning;
  final String state;
  final String? errorMessage;
  final String? homeChannel;
  final List<HermesMessagingEnvVar> envVars;

  bool get needsSetup => enabled && !configured;
  bool get healthy => enabled && configured && (state == 'connected' || state == 'ready');

  static HermesMessagingPlatform? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    final envVars = <HermesMessagingEnvVar>[];
    for (final row in (json['env_vars'] as List? ?? const [])) {
      if (row is! Map) continue;
      final env = HermesMessagingEnvVar.fromJson(Map<String, dynamic>.from(row));
      if (env != null) envVars.add(env);
    }
    return HermesMessagingPlatform(
      id: id,
      name: name,
      description: json['description']?.toString() ?? '',
      enabled: json['enabled'] == true,
      configured: json['configured'] == true,
      gatewayRunning: json['gateway_running'] == true,
      state: json['state']?.toString() ?? 'disabled',
      errorMessage: json['error_message']?.toString(),
      homeChannel: json['home_channel']?.toString(),
      envVars: List.unmodifiable(envVars),
    );
  }

  static List<HermesMessagingPlatform> listFromJson(Object? json) {
    if (json is! Map || json['platforms'] is! List) return const [];
    final out = <HermesMessagingPlatform>[];
    for (final row in json['platforms'] as List) {
      if (row is! Map) continue;
      final platform = fromJson(Map<String, dynamic>.from(row));
      if (platform != null) out.add(platform);
    }
    return List.unmodifiable(out);
  }
}

/// `POST /api/messaging/platforms/{id}/test` → `{ok, state, message}`.
final class HermesMessagingTestResult {
  const HermesMessagingTestResult({required this.ok, this.message = ''});

  final bool ok;
  final String message;

  static HermesMessagingTestResult? fromJson(Object? json) {
    if (json is! Map) return null;
    return HermesMessagingTestResult(
      ok: json['ok'] == true,
      message: json['message']?.toString() ?? '',
    );
  }
}
