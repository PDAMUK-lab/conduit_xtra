import 'package:conduit_core/features/hermes/services/hermes_identifier.dart';

/// One directory entry from `GET /api/fs/list`.
///
/// The server deliberately returns only these three fields — a network share
/// answers slowly, so it does not stat sizes or mtimes. Anything richer has to
/// come from reading the file.
final class HermesFsEntry {
  const HermesFsEntry({
    required this.name,
    required this.path,
    this.isDirectory = false,
  });

  final String name;
  final String path;
  final bool isDirectory;

  static HermesFsEntry? fromJson(Map<String, dynamic> json) {
    final name = validateHermesBoundedString(json['name'], maxCharacters: 512);
    final path = validateHermesBoundedString(json['path'], maxCharacters: 4096);
    if (name == null || path == null) return null;
    return HermesFsEntry(
      name: name,
      path: path,
      isDirectory: json['isDirectory'] == true,
    );
  }
}

/// `GET /api/fs/list`: entries plus the server's own error word when the
/// directory could not be read (the route returns 200 with `error` for the
/// common errno cases instead of failing).
final class HermesFsListing {
  const HermesFsListing({this.entries = const [], this.error});

  final List<HermesFsEntry> entries;
  final String? error;

  static HermesFsListing? fromJson(Object? json) {
    if (json is! Map) return null;
    final entries = <HermesFsEntry>[];
    for (final row in (json['entries'] as List? ?? const [])) {
      if (row is! Map) continue;
      final entry = HermesFsEntry.fromJson(Map<String, dynamic>.from(row));
      if (entry != null) entries.add(entry);
      if (entries.length >= 5000) break;
    }
    return HermesFsListing(
      entries: List.unmodifiable(entries),
      error: validateHermesBoundedString(json['error'], maxCharacters: 64),
    );
  }
}

/// `GET /api/fs/read-text`: a preview of a text file, bounded by the server.
final class HermesFsTextFile {
  const HermesFsTextFile({
    required this.path,
    required this.text,
    this.byteSize = 0,
    this.language = 'text',
    this.mimeType = 'text/plain',
    this.binary = false,
    this.truncated = false,
  });

  final String path;
  final String text;
  final int byteSize;
  final String language;
  final String mimeType;
  final bool binary;

  /// True when the file is larger than the server's preview cap (512 KB) and
  /// [text] is only the head.
  final bool truncated;

  static HermesFsTextFile? fromJson(Object? json) {
    if (json is! Map) return null;
    final path = validateHermesBoundedString(json['path'], maxCharacters: 4096);
    final text = json['text'];
    if (path == null || text is! String) return null;
    final size = json['byteSize'];
    return HermesFsTextFile(
      path: path,
      text: text,
      byteSize: size is num ? size.toInt().clamp(0, 1 << 40) : 0,
      language:
          validateHermesBoundedString(json['language'], maxCharacters: 32) ??
          'text',
      mimeType:
          validateHermesBoundedString(json['mimeType'], maxCharacters: 128) ??
          'text/plain',
      binary: json['binary'] == true,
      truncated: json['truncated'] == true,
    );
  }
}

/// `GET /api/fs/default-cwd`: where the agent's terminal starts, and its branch.
final class HermesFsDefaults {
  const HermesFsDefaults({required this.cwd, this.branch});

  final String cwd;
  final String? branch;

  static HermesFsDefaults? fromJson(Object? json) {
    if (json is! Map) return null;
    final cwd = validateHermesBoundedString(json['cwd'], maxCharacters: 4096);
    if (cwd == null || cwd.isEmpty) return null;
    final branch = validateHermesBoundedString(
      json['branch'],
      maxCharacters: 256,
    );
    return HermesFsDefaults(
      cwd: cwd,
      // The route returns "" when the directory is not in a git work tree.
      branch: branch == null || branch.isEmpty ? null : branch,
    );
  }
}
