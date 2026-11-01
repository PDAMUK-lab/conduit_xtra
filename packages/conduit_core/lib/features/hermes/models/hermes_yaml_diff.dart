/// Line-level diff for the config editor.
///
/// The server replaces the whole `config.yaml` on save, so the editor must show
/// exactly what would change before it writes: this is a plain LCS diff over
/// lines, collapsed to hunks with a few lines of context.
library;

import 'dart:convert';

import 'package:yaml/yaml.dart';

enum HermesDiffKind { context, added, removed }

final class HermesDiffLine {
  const HermesDiffLine(this.kind, this.text, {this.isGap = false});

  final HermesDiffKind kind;
  final String text;

  /// A marker standing in for skipped unchanged lines, not real file content.
  final bool isGap;
}

final class HermesYamlDiff {
  const HermesYamlDiff({
    required this.lines,
    required this.added,
    required this.removed,
    required this.truncated,
  });

  final List<HermesDiffLine> lines;
  final int added;
  final int removed;

  /// True when the inputs were too large to align and only a coarse comparison
  /// was produced.
  final bool truncated;

  bool get isEmpty => added == 0 && removed == 0;
}

const int _maxAlignedLines = 800;

/// A canonical form of a YAML document: structure only, keys sorted, no
/// comments or formatting.
///
/// `PUT /api/config/raw` re-serialises the parsed document, so a write that is
/// correct can still come back with different bytes (comments dropped, quoting
/// normalised). Verification compares this form, not the text.
String? canonicalYaml(String text) {
  try {
    final parsed = loadYaml(text);
    if (parsed is! Map) return null;
    return jsonEncode(_canonicalise(parsed));
  } on YamlException {
    return null;
  }
}

Object? _canonicalise(Object? node) {
  if (node is Map) {
    final keys = node.keys.map((k) => k.toString()).toList()..sort();
    return {for (final key in keys) key: _canonicalise(node[key])};
  }
  if (node is Iterable) return node.map(_canonicalise).toList();
  return node;
}

/// Diff two documents line by line, keeping [context] unchanged lines around
/// every change. Line endings are normalised to `\n`.
HermesYamlDiff diffYamlDocuments(String before, String after, {int context = 3}) {
  final a = _split(before);
  final b = _split(after);
  if (a.length > _maxAlignedLines || b.length > _maxAlignedLines) {
    return _coarseDiff(before, after);
  }

  // LCS table; config.yaml is a few hundred lines, so O(n*m) is fine here.
  final n = a.length;
  final m = b.length;
  final table = List<List<int>>.generate(
    n + 1,
    (_) => List<int>.filled(m + 1, 0),
    growable: false,
  );
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      table[i][j] = a[i] == b[j]
          ? table[i + 1][j + 1] + 1
          : (table[i + 1][j] >= table[i][j + 1]
                ? table[i + 1][j]
                : table[i][j + 1]);
    }
  }

  final raw = <HermesDiffLine>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      raw.add(HermesDiffLine(HermesDiffKind.context, a[i]));
      i++;
      j++;
    } else if (table[i + 1][j] >= table[i][j + 1]) {
      raw.add(HermesDiffLine(HermesDiffKind.removed, a[i]));
      i++;
    } else {
      raw.add(HermesDiffLine(HermesDiffKind.added, b[j]));
      j++;
    }
  }
  while (i < n) {
    raw.add(HermesDiffLine(HermesDiffKind.removed, a[i++]));
  }
  while (j < m) {
    raw.add(HermesDiffLine(HermesDiffKind.added, b[j++]));
  }

  final added = raw.where((l) => l.kind == HermesDiffKind.added).length;
  final removed = raw.where((l) => l.kind == HermesDiffKind.removed).length;
  return HermesYamlDiff(
    lines: _collapse(raw, context),
    added: added,
    removed: removed,
    truncated: false,
  );
}

List<HermesDiffLine> _collapse(List<HermesDiffLine> raw, int context) {
  final keep = List<bool>.filled(raw.length, false);
  for (var index = 0; index < raw.length; index++) {
    if (raw[index].kind == HermesDiffKind.context) continue;
    final from = index - context < 0 ? 0 : index - context;
    final to = index + context >= raw.length ? raw.length - 1 : index + context;
    for (var k = from; k <= to; k++) {
      keep[k] = true;
    }
  }
  final out = <HermesDiffLine>[];
  var previousKept = true;
  for (var index = 0; index < raw.length; index++) {
    if (keep[index]) {
      out.add(raw[index]);
      previousKept = true;
    } else if (previousKept) {
      out.add(const HermesDiffLine(HermesDiffKind.context, '', isGap: true));
      previousKept = false;
    }
  }
  return List.unmodifiable(out);
}

HermesYamlDiff _coarseDiff(String before, String after) {
  final a = _split(before);
  final b = _split(after);
  final inA = a.toSet();
  final inB = b.toSet();
  final lines = <HermesDiffLine>[
    for (final line in a)
      if (!inB.contains(line)) HermesDiffLine(HermesDiffKind.removed, line),
    for (final line in b)
      if (!inA.contains(line)) HermesDiffLine(HermesDiffKind.added, line),
  ];
  return HermesYamlDiff(
    lines: List.unmodifiable(lines),
    added: lines.where((l) => l.kind == HermesDiffKind.added).length,
    removed: lines.where((l) => l.kind == HermesDiffKind.removed).length,
    truncated: true,
  );
}

List<String> _split(String text) {
  final normalised = text.replaceAll('\r\n', '\n');
  if (normalised.isEmpty) return const [];
  final lines = normalised.split('\n');
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  return lines;
}
