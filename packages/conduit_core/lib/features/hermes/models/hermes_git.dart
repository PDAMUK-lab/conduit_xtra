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

/// One entry of `GET /api/git/worktrees`.
final class HermesGitWorktree {
  const HermesGitWorktree({
    required this.path,
    this.branch,
    this.isMain = false,
  });

  final String path;
  final String? branch;
  final bool isMain;

  static HermesGitWorktree? fromJson(Map<String, dynamic> json) {
    final path = json['path']?.toString().trim() ?? '';
    if (path.isEmpty) return null;
    final branch = json['branch']?.toString();
    return HermesGitWorktree(
      path: path,
      branch: branch != null && branch.trim().isNotEmpty ? branch.trim() : null,
      isMain: json['isMain'] == true,
    );
  }

  static List<HermesGitWorktree> listFromJson(Object? json) {
    if (json is! Map || json['worktrees'] is! List) return const [];
    final out = <HermesGitWorktree>[];
    for (final row in json['worktrees'] as List) {
      if (row is! Map) continue;
      final worktree = fromJson(Map<String, dynamic>.from(row));
      if (worktree != null) out.add(worktree);
    }
    return List.unmodifiable(out);
  }
}

/// One entry of `GET /api/git/branches`.
final class HermesGitBranch {
  const HermesGitBranch({
    required this.name,
    this.checkedOut = false,
    this.isDefault = false,
    this.isRemote = false,
  });

  final String name;
  final bool checkedOut;
  final bool isDefault;
  final bool isRemote;

  static HermesGitBranch? fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? '';
    if (name.isEmpty) return null;
    return HermesGitBranch(
      name: name,
      checkedOut: json['checkedOut'] == true,
      isDefault: json['isDefault'] == true,
      isRemote: json['isRemote'] == true,
    );
  }

  static List<HermesGitBranch> listFromJson(Object? json) {
    if (json is! Map || json['branches'] is! List) return const [];
    final out = <HermesGitBranch>[];
    for (final row in json['branches'] as List) {
      if (row is! Map) continue;
      final branch = fromJson(Map<String, dynamic>.from(row));
      if (branch != null) out.add(branch);
    }
    return List.unmodifiable(out);
  }
}
