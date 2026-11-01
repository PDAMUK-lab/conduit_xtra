/// One entry of `GET /api/git/status`'s `files` list.
final class HermesGitFile {
  const HermesGitFile({
    required this.path,
    this.staged = false,
    this.unstaged = false,
    this.untracked = false,
    this.conflicted = false,
  });

  final String path;
  final bool staged;
  final bool unstaged;
  final bool untracked;
  final bool conflicted;

  /// A one-letter marker for the list: U (conflict), ? (untracked),
  /// M (modified), else the staged state.
  String get marker {
    if (conflicted) return 'U';
    if (untracked) return '?';
    if (staged && unstaged) return 'M';
    if (staged) return 'A';
    if (unstaged) return 'M';
    return '·';
  }

  static HermesGitFile? fromJson(Map<String, dynamic> json) {
    final path = json['path']?.toString().trim() ?? '';
    if (path.isEmpty) return null;
    return HermesGitFile(
      path: path,
      staged: json['staged'] == true,
      unstaged: json['unstaged'] == true,
      untracked: json['untracked'] == true,
      conflicted: json['conflicted'] == true,
    );
  }
}

/// `GET /api/git/status`; the route returns null for a non-repository.
final class HermesGitStatus {
  const HermesGitStatus({
    this.branch,
    this.defaultBranch,
    this.detached = false,
    this.ahead = 0,
    this.behind = 0,
    this.staged = 0,
    this.unstaged = 0,
    this.untracked = 0,
    this.conflicted = 0,
    this.changed = 0,
    this.added = 0,
    this.removed = 0,
    this.files = const [],
  });

  final String? branch;
  final String? defaultBranch;
  final bool detached;
  final int ahead;
  final int behind;
  final int staged;
  final int unstaged;
  final int untracked;
  final int conflicted;
  final int changed;
  final int added;
  final int removed;
  final List<HermesGitFile> files;

  bool get clean => files.isEmpty;

  static int _int(Object? value) =>
      value is num ? value.toInt().clamp(0, 1 << 30) : 0;

  static HermesGitStatus? fromJson(Object? json) {
    if (json is! Map) return null;
    final files = <HermesGitFile>[];
    for (final row in (json['files'] as List? ?? const [])) {
      if (row is! Map) continue;
      final file = HermesGitFile.fromJson(Map<String, dynamic>.from(row));
      if (file != null) files.add(file);
      if (files.length >= 200) break;
    }
    return HermesGitStatus(
      branch: json['branch']?.toString(),
      defaultBranch: json['defaultBranch']?.toString(),
      detached: json['detached'] == true,
      ahead: _int(json['ahead']),
      behind: _int(json['behind']),
      staged: _int(json['staged']),
      unstaged: _int(json['unstaged']),
      untracked: _int(json['untracked']),
      conflicted: _int(json['conflicted']),
      changed: _int(json['changed']),
      added: _int(json['added']),
      removed: _int(json['removed']),
      files: List.unmodifiable(files),
    );
  }
}

/// `GET /api/git/file-diff` / `review/diff`.
final class HermesGitDiff {
  const HermesGitDiff({this.diff = ''});

  final String diff;

  static HermesGitDiff? fromJson(Object? json) {
    if (json is! Map) return null;
    final diff = json['diff'];
    if (diff is! String) return null;
    return HermesGitDiff(diff: diff);
  }
}
