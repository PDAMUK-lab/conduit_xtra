/// `GET /api/logs`: a tail of one server log file, already filtered server-side.
final class HermesLogTail {
  const HermesLogTail({required this.file, this.lines = const []});

  final String file;
  final List<String> lines;

  static HermesLogTail? fromJson(Object? json) {
    if (json is! Map) return null;
    final file = json['file']?.toString() ?? '';
    if (file.isEmpty) return null;
    final lines = <String>[];
    for (final line in (json['lines'] as List? ?? const [])) {
      final text = line?.toString() ?? '';
      if (text.isNotEmpty) lines.add(text);
      if (lines.length >= 500) break;
    }
    return HermesLogTail(file: file, lines: List.unmodifiable(lines));
  }
}

/// The log files the server exposes, with the keys the API expects.
const List<({String key, String label})> hermesLogFiles = [
  (key: 'agent', label: 'agent.log'),
  (key: 'errors', label: 'errors.log'),
  (key: 'gateway', label: 'gateway.log'),
  (key: 'gui', label: 'gui.log'),
  (key: 'mcp', label: 'mcp-stderr.log'),
  (key: 'update', label: 'update.log'),
];
