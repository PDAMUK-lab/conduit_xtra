import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/models/hermes_memory_wiki.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the overview the memory-wiki plugin returns', () {
    final overview = HermesMemoryWikiOverview.fromJson({
      'subjects': [
        {
          'slug': 'memory-wiki',
          'name': 'Memory Wiki',
          'keywords': ['memory', 'wiki'],
          'session_count': 3,
          'message_count': 42,
          'first_seen': 1,
          'last_seen': 2,
          'sessions': [
            {
              'id': 's1',
              'title': 'Build the wiki',
              'source': 'cli',
              'preview': '…',
              'started_at': 1,
              'last_active': 2,
            },
          ],
          'snippets': [
            {
              'message_id': 'm1',
              'session_id': 's1',
              'role': 'user',
              'timestamp': 1,
              'text': 'mentions the wiki',
            },
          ],
        },
      ],
      'daily_logs': [
        {
          'date': '2026-10-31',
          'session_count': 2,
          'message_count': 9,
          'started_at_min': 1,
          'last_active_max': 3,
          'subjects': [
            {'slug': 'memory-wiki', 'name': 'Memory Wiki', 'count': 2},
          ],
          'sessions': [
            {'id': 's1', 'title': 'Build the wiki'},
          ],
          'work_items': [
            {
              'session_id': 's1',
              'kind': 'coding',
              'text': 'implemented the page',
              'timestamp': 2,
            },
          ],
        },
      ],
      'recent_sessions': [
        {'id': 's2', 'title': 'Yesterday'},
      ],
      'notes': {
        'memory': ['Prefers rebase merges', 'CI watcher is canonical'],
        'user': ['UK-based'],
        'memory_count': 2,
        'user_count': 1,
      },
    });

    check(overview).isNotNull();
    final wiki = overview!;
    check(wiki.subjects).length.equals(1);
    check(wiki.subjects.single.slug).equals('memory-wiki');
    check(wiki.subjects.single.keywords).deepEquals(['memory', 'wiki']);
    check(wiki.subjects.single.sessions.single.title).equals('Build the wiki');
    check(wiki.subjects.single.snippets.single.text).equals(
      'mentions the wiki',
    );
    check(wiki.days).length.equals(1);
    check(wiki.days.single.date).equals('2026-10-31');
    check(wiki.days.single.subjects.single.count).equals(2);
    check(wiki.days.single.workItems.single.kind).equals('coding');
    check(wiki.notes.memoryCount).equals(2);
    check(wiki.notes.user.single).equals('UK-based');
    check(wiki.recentSessions.single.id).equals('s2');
  });

  test('drops unusable subjects, days and snippets', () {
    final overview = HermesMemoryWikiOverview.fromJson({
      'subjects': [
        {'slug': 'bad slug with spaces'},
        {'name': 'no slug'},
        {'slug': 'ok', 'name': 'Ok'},
      ],
      'daily_logs': [
        {'date': 'not-a-date'},
        {'date': '2026-01-01'},
      ],
      'notes': {'memory': [1, null, 'kept']},
    });
    final wiki = overview!;
    check(wiki.subjects.map((s) => s.slug)).deepEquals(['ok']);
    check(wiki.days.map((d) => d.date)).deepEquals(['2026-01-01']);
    check(wiki.notes.memory).deepEquals(['1', 'kept']);
  });

  test('parses the provider archive, available or not', () {
    final archive = HermesMemoryArchive.fromJson({
      'available': true,
      'provider': 'hermesmemory',
      'path': '/home/hermes/.hermes/memories/archive.db',
      'summary': {'total': 4, 'active': 1, 'archived': 2, 'note': 1, 'pins': 0},
      'entries': [
        {
          'id': 7,
          'target': 'memory',
          'status': 'replaced',
          'reason': 'superseded',
          'content': 'old entry',
          'content_length': 9,
          'truncated': false,
          'updated_at': 5,
        },
      ],
    });
    check(archive).isNotNull();
    check(archive!.available).isTrue();
    check(archive.provider).equals('hermesmemory');
    check(archive.total).equals(4);
    check(archive.archived).equals(2);
    check(archive.entries.single.status).equals('replaced');
    check(archive.entries.single.content).equals('old entry');

    final missing = HermesMemoryArchive.fromJson({'available': false});
    check(missing!.available).isFalse();
    check(missing.entries).isEmpty();
    check(missing.total).equals(0);
  });

  test('a non-map body is null rather than a throw', () {
    check(HermesMemoryWikiOverview.fromJson(null)).isNull();
    check(HermesMemoryArchive.fromJson('nope')).isNull();
  });
}
