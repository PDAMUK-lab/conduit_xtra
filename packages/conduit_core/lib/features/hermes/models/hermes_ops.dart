/// One long-running server action (`POST /api/ops/*` → `{ok,pid,name}`),
/// polled through `GET /api/actions/{name}/status`.
final class HermesActionStatus {
  const HermesActionStatus({
    required this.name,
    this.running = false,
    this.exitCode,
    this.pid,
    this.lines = const [],
  });

  final String name;
  final bool running;
  final int? exitCode;
  final int? pid;
  final List<String> lines;

  bool get finished => !running && exitCode != null;
  bool get succeeded => finished && exitCode == 0;

  static HermesActionStatus? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name']?.toString() ?? '';
    if (name.isEmpty) return null;
    final lines = <String>[];
    for (final line in (json['lines'] as List? ?? const [])) {
      lines.add(line?.toString() ?? '');
      if (lines.length >= 2000) break;
    }
    final code = json['exit_code'];
    final pid = json['pid'];
    return HermesActionStatus(
      name: name,
      running: json['running'] == true,
      exitCode: code is num ? code.toInt() : null,
      pid: pid is num ? pid.toInt() : null,
      lines: List.unmodifiable(lines),
    );
  }
}

/// One lifecycle hook from `GET /api/ops/hooks`.
final class HermesHook {
  const HermesHook({
    required this.event,
    required this.command,
    this.matcher,
    this.timeout,
    this.allowed = false,
    this.executable = false,
  });

  final String event;
  final String command;
  final String? matcher;
  final int? timeout;
  final bool allowed;
  final bool executable;

  static HermesHook? fromJson(Map<String, dynamic> json) {
    final event = json['event']?.toString().trim() ?? '';
    final command = json['command']?.toString().trim() ?? '';
    if (event.isEmpty || command.isEmpty) return null;
    final timeout = json['timeout'];
    return HermesHook(
      event: event,
      command: command,
      matcher: json['matcher']?.toString(),
      timeout: timeout is num ? timeout.toInt() : null,
      allowed: json['allowed'] == true,
      executable: json['executable'] == true,
    );
  }

  static List<HermesHook> listFromJson(Object? json) {
    if (json is! Map || json['hooks'] is! List) return const [];
    final out = <HermesHook>[];
    for (final row in json['hooks'] as List) {
      if (row is! Map) continue;
      final hook = fromJson(Map<String, dynamic>.from(row));
      if (hook != null) out.add(hook);
    }
    return List.unmodifiable(out);
  }
}

/// One session's checkpoint directory.
final class HermesCheckpointSession {
  const HermesCheckpointSession({
    required this.session,
    this.files = 0,
    this.bytes = 0,
  });

  final String session;
  final int files;
  final int bytes;

  static HermesCheckpointSession? fromJson(Map<String, dynamic> json) {
    final session = json['session']?.toString().trim() ?? '';
    if (session.isEmpty) return null;
    int n(Object? v) => v is num ? v.toInt().clamp(0, 1 << 50) : 0;
    return HermesCheckpointSession(
      session: session,
      files: n(json['files']),
      bytes: n(json['bytes']),
    );
  }
}

/// `GET /api/ops/checkpoints` — what a prune would reclaim.
final class HermesCheckpoints {
  const HermesCheckpoints({this.sessions = const [], this.totalBytes = 0});

  final List<HermesCheckpointSession> sessions;
  final int totalBytes;

  bool get isEmpty => sessions.isEmpty;

  static HermesCheckpoints? fromJson(Object? json) {
    if (json is! Map) return null;
    final sessions = <HermesCheckpointSession>[];
    for (final row in (json['sessions'] as List? ?? const [])) {
      if (row is! Map) continue;
      final session = HermesCheckpointSession.fromJson(
        Map<String, dynamic>.from(row),
      );
      if (session != null) sessions.add(session);
    }
    final total = json['total_bytes'];
    return HermesCheckpoints(
      sessions: List.unmodifiable(sessions),
      totalBytes: total is num ? total.toInt().clamp(0, 1 << 50) : 0,
    );
  }
}
