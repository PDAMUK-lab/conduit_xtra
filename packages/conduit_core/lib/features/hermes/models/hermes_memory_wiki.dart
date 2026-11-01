import 'package:conduit_core/features/hermes/services/hermes_identifier.dart';

/// Bounds for every list the Memory Wiki endpoint can return. The server
/// already clamps; these keep a hostile or future payload from bloating a
/// phone list.
const int kMaxHermesWikiSubjects = 200;
const int kMaxHermesWikiDays = 120;
const int kMaxHermesWikiSessions = 100;
const int kMaxHermesWikiSnippets = 20;
const int kMaxHermesWikiWorkItems = 60;
const int kMaxHermesWikiMemoryEntries = 200;
const int kMaxHermesWikiArchiveEntries = 200;
const int kMaxHermesWikiTextCharacters = 4096;

String _text(Object? value, {int max = 512}) {
  final raw = value?.toString().trim() ?? '';
  if (raw.length <= max) return raw;
  return raw.substring(0, max);
}

double _epoch(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _count(Object? value) {
  if (value is num) return value.toInt().clamp(0, 1 << 30);
  return 0;
}

List<String> _strings(Object? value, {int max = 12, int maxChars = 64}) {
  if (value is! List) return const [];
  final out = <String>[];
  for (final item in value) {
    if (out.length >= max) break;
    final text = _text(item, max: maxChars);
    if (text.isNotEmpty) out.add(text);
  }
  return List.unmodifiable(out);
}

/// One session a wiki subject or day points at.
final class HermesWikiSessionInfo {
  const HermesWikiSessionInfo({
    required this.id,
    this.title,
    this.source,
    this.preview,
    this.startedAt = 0,
    this.lastActive = 0,
  });

  final String id;
  final String? title;
  final String? source;
  final String? preview;
  final double startedAt;
  final double lastActive;

  static HermesWikiSessionInfo? fromJson(Map<String, dynamic> json) {
    final id = validateHermesOpaqueIdentifier(json['id']);
    if (id == null) return null;
    return HermesWikiSessionInfo(
      id: id,
      title: validateHermesBoundedString(
        json['title'],
        maxCharacters: 512,
      ),
      source: validateHermesBoundedString(
        json['source'],
        maxCharacters: 64,
      ),
      preview: validateHermesBoundedString(
        json['preview'],
        maxCharacters: kMaxHermesWikiTextCharacters,
      ),
      startedAt: _epoch(json['started_at']),
      lastActive: _epoch(json['last_active']),
    );
  }

  static List<HermesWikiSessionInfo> listFromJson(Object? value) {
    if (value is! List) return const [];
    final out = <HermesWikiSessionInfo>[];
    for (final row in value) {
      if (row is! Map) continue;
      final session = fromJson(Map<String, dynamic>.from(row));
      if (session != null) out.add(session);
      if (out.length >= kMaxHermesWikiSessions) break;
    }
    return List.unmodifiable(out);
  }
}

/// One quoted message that mentions a subject.
final class HermesWikiSnippet {
  const HermesWikiSnippet({
    required this.text,
    this.role,
    this.sessionId,
    this.messageId,
    this.timestamp = 0,
  });

  final String text;
  final String? role;
  final String? sessionId;
  final String? messageId;
  final double timestamp;

  static HermesWikiSnippet? fromJson(Map<String, dynamic> json) {
    final text = _text(json['text'], max: 240);
    if (text.isEmpty) return null;
    return HermesWikiSnippet(
      text: text,
      role: validateHermesOpaqueIdentifier(json['role']),
      sessionId: validateHermesOpaqueIdentifier(json['session_id']),
      messageId: validateHermesOpaqueIdentifier(json['message_id']),
      timestamp: _epoch(json['timestamp']),
    );
  }
}

/// A subject aggregated from session history (`GET …/subjects`).
final class HermesWikiSubject {
  const HermesWikiSubject({
    required this.slug,
    required this.name,
    this.keywords = const [],
    this.sessionCount = 0,
    this.messageCount = 0,
    this.firstSeen = 0,
    this.lastSeen = 0,
    this.sessions = const [],
    this.snippets = const [],
  });

  final String slug;
  final String name;
  final List<String> keywords;
  final int sessionCount;
  final int messageCount;
  final double firstSeen;
  final double lastSeen;
  final List<HermesWikiSessionInfo> sessions;
  final List<HermesWikiSnippet> snippets;

  static HermesWikiSubject? fromJson(Map<String, dynamic> json) {
    final slug = validateHermesOpaqueIdentifier(json['slug']);
    if (slug == null) return null;
    final name = validateHermesBoundedString(
          json['name'],
          maxCharacters: 256,
        ) ??
        slug;
    final sessions = <HermesWikiSessionInfo>[
      for (final row in (json['sessions'] as List? ?? const []))
        if (row is Map)
          ?HermesWikiSessionInfo.fromJson(Map<String, dynamic>.from(row)),
    ];
    final snippets = <HermesWikiSnippet>[
      for (final row in (json['snippets'] as List? ?? const []))
        if (row is Map)
          ?HermesWikiSnippet.fromJson(Map<String, dynamic>.from(row)),
    ];
    return HermesWikiSubject(
      slug: slug,
      name: name,
      keywords: _strings(json['keywords']),
      sessionCount: _count(json['session_count']),
      messageCount: _count(json['message_count']),
      firstSeen: _epoch(json['first_seen']),
      lastSeen: _epoch(json['last_seen']),
      sessions: sessions.take(kMaxHermesWikiSessions).toList(growable: false),
      snippets: snippets.take(kMaxHermesWikiSnippets).toList(growable: false),
    );
  }

  static List<HermesWikiSubject> listFromJson(Object? value) {
    if (value is! List) return const [];
    final out = <HermesWikiSubject>[];
    for (final row in value) {
      if (row is! Map) continue;
      final subject = fromJson(Map<String, dynamic>.from(row));
      if (subject != null) out.add(subject);
      if (out.length >= kMaxHermesWikiSubjects) break;
    }
    return List.unmodifiable(out);
  }

  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return name.toLowerCase().contains(needle) ||
        slug.contains(needle) ||
        keywords.any((keyword) => keyword.toLowerCase().contains(needle));
  }
}

/// A subject mentioned on one day.
final class HermesWikiDaySubject {
  const HermesWikiDaySubject({
    required this.slug,
    required this.name,
    this.count = 0,
  });

  final String slug;
  final String name;
  final int count;

  static HermesWikiDaySubject? fromJson(Map<String, dynamic> json) {
    final slug = validateHermesOpaqueIdentifier(json['slug']);
    if (slug == null) return null;
    return HermesWikiDaySubject(
      slug: slug,
      name:
          validateHermesBoundedString(json['name'], maxCharacters: 256) ?? slug,
      count: _count(json['count']),
    );
  }
}

/// One line of work extracted from a day's sessions.
final class HermesWikiWorkItem {
  const HermesWikiWorkItem({
    required this.kind,
    required this.text,
    this.sessionId,
    this.timestamp = 0,
  });

  final String kind;
  final String text;
  final String? sessionId;
  final double timestamp;

  static HermesWikiWorkItem? fromJson(Map<String, dynamic> json) {
    final text = _text(json['text'], max: 240);
    if (text.isEmpty) return null;
    return HermesWikiWorkItem(
      kind: validateHermesOpaqueIdentifier(json['kind']) ?? 'conversation',
      text: text,
      sessionId: validateHermesOpaqueIdentifier(json['session_id']),
      timestamp: _epoch(json['timestamp']),
    );
  }
}

/// One daily log (`GET …/days`).
final class HermesWikiDay {
  const HermesWikiDay({
    required this.date,
    this.sessionCount = 0,
    this.messageCount = 0,
    this.startedAtMin = 0,
    this.lastActiveMax = 0,
    this.subjects = const [],
    this.sessions = const [],
    this.workItems = const [],
  });

  final String date;
  final int sessionCount;
  final int messageCount;
  final double startedAtMin;
  final double lastActiveMax;
  final List<HermesWikiDaySubject> subjects;
  final List<HermesWikiSessionInfo> sessions;
  final List<HermesWikiWorkItem> workItems;

  static HermesWikiDay? fromJson(Map<String, dynamic> json) {
    final date = json['date']?.toString().trim() ?? '';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) return null;
    return HermesWikiDay(
      date: date,
      sessionCount: _count(json['session_count']),
      messageCount: _count(json['message_count']),
      startedAtMin: _epoch(json['started_at_min']),
      lastActiveMax: _epoch(json['last_active_max']),
      subjects: [
        for (final row in (json['subjects'] as List? ?? const []))
          if (row is Map)
            ?HermesWikiDaySubject.fromJson(Map<String, dynamic>.from(row)),
      ],
      sessions: HermesWikiSessionInfo.listFromJson(json['sessions']),
      workItems: [
        for (final row in (json['work_items'] as List? ?? const []))
          if (row is Map)
            ?HermesWikiWorkItem.fromJson(Map<String, dynamic>.from(row)),
      ].take(kMaxHermesWikiWorkItems).toList(growable: false),
    );
  }

  static List<HermesWikiDay> listFromJson(Object? value) {
    if (value is! List) return const [];
    final out = <HermesWikiDay>[];
    for (final row in value) {
      if (row is! Map) continue;
      final day = fromJson(Map<String, dynamic>.from(row));
      if (day != null) out.add(day);
      if (out.length >= kMaxHermesWikiDays) break;
    }
    return List.unmodifiable(out);
  }
}

/// The persistent memory the agent actually carries (MEMORY.md / USER.md),
/// split into entries the same way the memory tool splits them.
final class HermesWikiNotes {
  const HermesWikiNotes({
    this.memory = const [],
    this.user = const [],
    this.memoryCount = 0,
    this.userCount = 0,
  });

  final List<String> memory;
  final List<String> user;
  final int memoryCount;
  final int userCount;

  static HermesWikiNotes fromJson(Object? value) {
    if (value is! Map) return const HermesWikiNotes();
    final memory = _strings(
      value['memory'],
      max: kMaxHermesWikiMemoryEntries,
      maxChars: kMaxHermesWikiTextCharacters,
    );
    final user = _strings(
      value['user'],
      max: kMaxHermesWikiMemoryEntries,
      maxChars: kMaxHermesWikiTextCharacters,
    );
    return HermesWikiNotes(
      memory: memory,
      user: user,
      memoryCount: _count(value['memory_count']) == 0
          ? memory.length
          : _count(value['memory_count']),
      userCount: _count(value['user_count']) == 0
          ? user.length
          : _count(value['user_count']),
    );
  }
}

/// One archived memory entry from the active provider (hermesmemory today).
final class HermesMemoryArchiveEntry {
  const HermesMemoryArchiveEntry({
    required this.id,
    required this.status,
    this.target,
    this.reason,
    this.content = '',
    this.contentLength = 0,
    this.truncated = false,
    this.sessionId,
    this.updatedAt = 0,
  });

  final int id;
  final String status;
  final String? target;
  final String? reason;
  final String content;
  final int contentLength;
  final bool truncated;
  final String? sessionId;
  final double updatedAt;

  static HermesMemoryArchiveEntry? fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
    if (id == null) return null;
    return HermesMemoryArchiveEntry(
      id: id,
      status: validateHermesBoundedString(
            json['status'],
            maxCharacters: 32,
          ) ??
          'unknown',
      target: validateHermesBoundedString(
        json['target'],
        maxCharacters: 32,
      ),
      reason: validateHermesBoundedString(
        json['reason'],
        maxCharacters: 64,
      ),
      content: _text(json['content'], max: kMaxHermesWikiTextCharacters),
      contentLength: _count(json['content_length']),
      truncated: json['truncated'] == true,
      sessionId: validateHermesOpaqueIdentifier(json['session_id']),
      updatedAt: _epoch(json['updated_at']),
    );
  }
}

/// `GET /api/plugins/memory-wiki/archive`.
final class HermesMemoryArchive {
  const HermesMemoryArchive({
    this.available = false,
    this.provider = '',
    this.path = '',
    this.total = 0,
    this.active = 0,
    this.archived = 0,
    this.notes = 0,
    this.pins = 0,
    this.entries = const [],
  });

  final bool available;
  final String provider;
  final String path;
  final int total;
  final int active;
  final int archived;
  final int notes;
  final int pins;
  final List<HermesMemoryArchiveEntry> entries;

  static HermesMemoryArchive? fromJson(Object? json) {
    if (json is! Map) return null;
    final summary = json['summary'];
    int summaryValue(String key) =>
        summary is Map ? _count(summary[key]) : 0;
    final entries = <HermesMemoryArchiveEntry>[];
    for (final row in (json['entries'] as List? ?? const [])) {
      if (row is! Map) continue;
      final entry = HermesMemoryArchiveEntry.fromJson(
        Map<String, dynamic>.from(row),
      );
      if (entry != null) entries.add(entry);
      if (entries.length >= kMaxHermesWikiArchiveEntries) break;
    }
    return HermesMemoryArchive(
      available: json['available'] == true,
      provider:
          validateHermesBoundedString(json['provider'], maxCharacters: 64) ??
          '',
      path: _text(json['path'], max: 512),
      total: summaryValue('total'),
      active: summaryValue('active'),
      archived: summaryValue('archived'),
      notes: summaryValue('note'),
      pins: summaryValue('pins'),
      entries: List.unmodifiable(entries),
    );
  }
}

/// `GET /api/plugins/memory-wiki/overview`.
final class HermesMemoryWikiOverview {
  const HermesMemoryWikiOverview({
    this.subjects = const [],
    this.days = const [],
    this.recentSessions = const [],
    this.notes = const HermesWikiNotes(),
  });

  final List<HermesWikiSubject> subjects;
  final List<HermesWikiDay> days;
  final List<HermesWikiSessionInfo> recentSessions;
  final HermesWikiNotes notes;

  static HermesMemoryWikiOverview? fromJson(Object? json) {
    if (json is! Map) return null;
    return HermesMemoryWikiOverview(
      subjects: HermesWikiSubject.listFromJson(json['subjects']),
      days: HermesWikiDay.listFromJson(json['daily_logs']),
      recentSessions: HermesWikiSessionInfo.listFromJson(
        json['recent_sessions'],
      ),
      notes: HermesWikiNotes.fromJson(json['notes']),
    );
  }
}
