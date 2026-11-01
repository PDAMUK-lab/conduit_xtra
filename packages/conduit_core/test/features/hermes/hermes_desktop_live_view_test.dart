import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conduit_core/features/hermes/models/hermes_config.dart';
import 'package:conduit_core/features/hermes/models/hermes_live_activity.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:test/test.dart';

/// A chat left open on the phone must follow a turn another client runs.
///
/// The gateway fans `message.start` / `message.delta` / `message.complete` and
/// a terminal `session.info(running: false)` out to every attached viewer (see
/// `scratch/probe_viewer_events.py`: 1 delta, 1 complete, 2 info frames reached
/// an idle second client). The app therefore has everything it needs on the
/// wire; these tests pin what it does with those frames.
void main() {
  late _LiveGateway gateway;
  late HermesDesktopApiService service;

  setUp(() async {
    gateway = await _LiveGateway.start();
    service = HermesDesktopApiService(
      config: HermesConfig(
        enabled: true,
        baseUrl: gateway.baseUrl,
        mode: HermesBackendMode.desktopGateway,
        desktopAuthKind: HermesDesktopAuthKind.legacyToken,
        desktopProfile: 'default',
        desktopCredentials: HermesDesktopCredentials(
          legacyToken: 'legacy-token',
        ),
      ),
      liveWatchInterval: const Duration(milliseconds: 40),
    );
  });

  tearDown(() async {
    service.close();
    await gateway.close();
  });

  test('a turn completed by another client refreshes the open transcript', () async {
    final changes = <String>[];
    final subscription = service.transcriptChanges.listen(changes.add);
    addTearDown(subscription.cancel);

    await service.getSessionMessages('st-1');
    changes.clear();

    // Exactly the burst the gateway sent the idle viewer in the probe. No
    // local stream is consuming it: this client only has the chat open.
    gateway.push({'type': 'message.start'});
    gateway.push({'type': 'message.delta', 'delta': 'po'});
    gateway.push({'type': 'message.complete', 'text': 'pong'});
    await _settle();

    expect(
      changes,
      contains('st-1'),
      reason: 'a completion from another client must reload the transcript',
    );
  });

  test('a session stuck running returns to idle once the turn is over', () async {
    gateway.running = true;
    await service.getSessionMessages('st-1');
    expect(service.turnStateFor('st-1'), HermesDesktopTurnState.running);

    // The turn finishes but this client never sees the terminal event (socket
    // died, app was backgrounded, event dropped). Nothing else happens.
    gateway.running = false;
    await _settle(duration: const Duration(milliseconds: 400));

    expect(
      service.turnStateFor('st-1'),
      HermesDesktopTurnState.idle,
      reason: 'a stale running state leaves the typing indicator up forever',
    );
  });

  test('the steps of a turn another client runs are visible', () async {
    final streamed = <HermesLiveActivity?>[];
    final subscription = service.liveActivityFor('st-1').listen(streamed.add);
    addTearDown(subscription.cancel);

    await service.getSessionMessages('st-1');
    gateway.push({'type': 'thinking.delta', 'text': 'planning the fix'});
    gateway.push({'type': 'tool.start', 'name': 'terminal', 'detail': 'flutter test'});
    gateway.push({'type': 'tool.complete', 'name': 'terminal', 'result_text': 'ok'});
    gateway.push({'type': 'message.delta', 'delta': 'done.'});
    await _settle();

    final activities = streamed.whereType<HermesLiveActivity>().toList();
    final kinds = activities.map((activity) => activity.kind).toList();
    expect(kinds, contains(HermesLiveActivityKind.thinking));
    expect(kinds, contains(HermesLiveActivityKind.tool));
    expect(kinds, contains(HermesLiveActivityKind.writing));
    expect(
      activities.firstWhere((a) => a.kind == HermesLiveActivityKind.tool).text,
      'terminal',
    );

    gateway.push({'type': 'message.complete', 'text': 'done.'});
    await _settle();
    expect(
      streamed.last,
      anyOf(isNull, predicate<HermesLiveActivity>((a) => a.kind == HermesLiveActivityKind.done)),
      reason: 'the line must clear when the turn ends',
    );
  });

  test('a session absent from active_list is not read as idle at once', () async {
    gateway.running = true;
    await service.getSessionMessages('st-1');
    expect(service.turnStateFor('st-1'), HermesDesktopTurnState.running);

    gateway.includeInActiveList = false;
    await _settle(duration: const Duration(milliseconds: 70));
    expect(
      service.turnStateFor('st-1'),
      HermesDesktopTurnState.running,
      reason: 'one absent poll must not flip the chat to Ready under a live turn',
    );

    await _settle(duration: const Duration(milliseconds: 250));
    expect(
      service.turnStateFor('st-1'),
      HermesDesktopTurnState.idle,
      reason: 'a sustained absence is the gateway saying it has no turn',
    );
  });

  test('a refresh downloads the newest page, not the whole chat', () async {
    for (var i = 1; i <= 300; i++) {
      gateway.rows.add({'id': i, 'role': 'user', 'content': 'row $i'});
    }
    final first = await service.getSessionMessages('st-1');
    expect(first.length, 300);
    final fullReadsAfterOpen = gateway.fullTranscriptReads;
    expect(fullReadsAfterOpen, greaterThanOrEqualTo(2)); // 200 + 100 pages

    // Another client's turn adds a reply.
    gateway.rows.add({'id': 301, 'role': 'assistant', 'content': 'pong'});
    gateway.push({'type': 'message.complete', 'text': 'pong'});
    await _settle();

    final refreshed = await service.getSessionMessages('st-1');
    expect(refreshed.length, 301);
    expect(refreshed.last['id'], 301);
    expect(
      gateway.fullTranscriptReads,
      fullReadsAfterOpen,
      reason: 'a refresh must not re-read the pages it already has',
    );
    expect(gateway.transcriptRequests.last.order, 'latest');

    // An idle refresh re-uses the snapshot instead of re-downloading.
    final before = gateway.transcriptRequests.length;
    final again = await service.getSessionMessages('st-1');
    expect(identical(again, refreshed), isTrue);
    expect(gateway.transcriptRequests.length, before + 1);
  });

  test('a refused resume still opens the chat', () async {
    for (var i = 1; i <= 250; i++) {
      gateway.rows.add({'id': i, 'role': 'user', 'content': 'row $i'});
    }
    // Another runtime still owns the session: session.resume is refused.
    gateway.refuseResume = true;

    final opened = await service.openSessionTranscript('st-1');

    expect(opened.length, 250, reason: 'the REST transcript must still open');
    expect(opened.first['id'], 1);
  });

  test('a gap wider than one page falls back to the full transcript', () async {
    for (var i = 1; i <= 250; i++) {
      gateway.rows.add({'id': i, 'role': 'user', 'content': 'row $i'});
    }
    await service.getSessionMessages('st-1');
    final fullReads = gateway.fullTranscriptReads;

    for (var i = 251; i <= 600; i++) {
      gateway.rows.add({'id': i, 'role': 'user', 'content': 'row $i'});
    }
    final refreshed = await service.getSessionMessages('st-1');
    expect(refreshed.length, 600);
    expect(
      gateway.fullTranscriptReads,
      greaterThan(fullReads),
      reason: 'merging would drop the rows between the old tail and the page',
    );
  });

  test('opening a long chat shows the newest page, then backfills', () async {
    for (var i = 1; i <= 500; i++) {
      gateway.rows.add({'id': i, 'role': 'user', 'content': 'row $i'});
    }
    gateway.holdFullReads = true;

    final opened = await service.openSessionTranscript('st-1');
    expect(opened.length, 200);
    expect(opened.last['id'], 500);
    expect(
      gateway.fullTranscriptReads,
      0,
      reason: 'the open must not page the whole history before showing the chat',
    );

    gateway.releaseFullReads();
    await _settle(duration: const Duration(milliseconds: 600));
    final complete = await service.getSessionMessages('st-1');
    expect(complete.length, 500);
    expect(complete.first['id'], 1);
  });

  test('a dead socket reconnects and re-reads the open session', () async {
    await service.getSessionMessages('st-1');
    expect(gateway.connections, 1);

    await gateway.dropSockets();
    await _settle(duration: const Duration(milliseconds: 400));

    expect(
      gateway.connections,
      greaterThan(1),
      reason: 'the client must notice the dead socket and reconnect',
    );
    expect(
      gateway.resumesOnNewestSocket,
      greaterThan(0),
      reason: 'a reconnect must resume the open session, not just reopen a socket',
    );
  });
}

Future<void> _settle({
  Duration duration = const Duration(milliseconds: 250),
}) => Future<void>.delayed(duration);

/// The smallest gateway that behaves like Hermes for one session.
final class _LiveGateway {
  _LiveGateway(this.server);

  final HttpServer server;
  final List<WebSocket> sockets = [];
  final List<int> resumesByConnection = [];
  int connections = 0;
  int resumeCalls = 0;
  bool running = false;

  /// Whether `session.active_list` lists the session at all.
  bool includeInActiveList = true;

  /// Refuse `session.resume` the way a session owned by another runtime does.
  bool refuseResume = false;

  /// Rows `/api/sessions/st-1/messages` serves, in insertion order.
  final List<Map<String, Object?>> rows = [];

  /// Every transcript request this gateway answered: order, offset, limit.
  final List<({String order, int offset, int limit})> transcriptRequests = [];

  int get fullTranscriptReads =>
      transcriptRequests.where((r) => r.order != 'latest').length;

  /// When set, `order=oldest` pages wait until [releaseFullReads] — lets a test
  /// prove what the open path requested before the background backfill landed.
  bool holdFullReads = false;
  final List<Completer<void>> _heldFullReads = [];

  void releaseFullReads() {
    holdFullReads = false;
    for (final waiter in _heldFullReads) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _heldFullReads.clear();
  }

  /// Resumes this client asked for on the newest socket.
  int get resumesOnNewestSocket =>
      resumesByConnection.isEmpty ? 0 : resumesByConnection.last;

  String get baseUrl => 'http://127.0.0.1:${server.port}';

  static Future<_LiveGateway> start() async {
    final gateway = _LiveGateway(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    gateway.server.listen(gateway.handle);
    return gateway;
  }

  Future<void> handle(HttpRequest request) async {
    if (request.uri.path == '/api/ws' &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      connections++;
      final connectionIndex = resumesByConnection.length;
      resumesByConnection.add(0);
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      void send(Object? payload) {
        if (socket.readyState != WebSocket.open) return;
        try {
          socket.add(payload);
        } catch (_) {
          // The client closed while a reply was in flight (test teardown).
        }
      }
      send(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {'type': 'gateway.ready', 'payload': <String, Object?>{}},
        }),
      );
      socket.listen((raw) {
        final frame = jsonDecode(raw as String) as Map<String, dynamic>;
        final Object? result;
        Object? error;
        switch (frame['method']) {
          case 'session.resume':
            resumeCalls++;
            resumesByConnection[connectionIndex]++;
            if (refuseResume) {
              result = null;
              error = {'code': 4037, 'message': 'session owned by another runtime'};
              break;
            }
            result = {
              'session_id': 'rt-1',
              'stored_session_id': 'st-1',
              'running': running,
              'info': {'running': running, 'desktop_contract': 7},
            };
          case 'session.active_list':
            result = {
              'sessions': includeInActiveList
                  ? [
                {
                  'id': 'rt-1',
                  'session_key': 'st-1',
                  'status': running ? 'working' : 'idle',
                  'message_count': rows.length,
                },
              ]
                  : <Object?>[],
            };
          default:
            // The real gateway answers an unknown method with -32601; a fake
            // that answers everything lets the client call a method that does
            // not exist (session.info is an event, not an RPC).
            result = null;
            error = {
              'code': -32601,
              'message':
                  'unknown method: ${frame['method']} — not available on this Hermes backend',
            };
        }
        send(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': frame['id'],
            if (error == null) 'result': result else 'error': error,
          }),
        );
      }, onDone: () => sockets.remove(socket));
      return;
    }
    request.response.headers.contentType = ContentType.json;
    if (request.uri.path == '/api/status') {
      request.response.write(
        jsonEncode({'auth_required': false, 'desktop_contract': 7}),
      );
    } else if (request.uri.path == '/api/sessions/st-1/messages') {
      final query = request.uri.queryParameters;
      final offset = int.tryParse(query['offset'] ?? '0') ?? 0;
      final requested = int.tryParse(query['limit'] ?? '200') ?? 200;
      final order = query['order'] ?? 'oldest';
      transcriptRequests.add((order: order, offset: offset, limit: requested));
      if (order != 'latest' && holdFullReads) {
        final waiter = Completer<void>();
        _heldFullReads.add(waiter);
        await waiter.future;
      }
      final List<Map<String, Object?>> page;
      if (order == 'latest') {
        // The real route pages back from the newest but answers chronologically.
        final start = rows.length > requested ? rows.length - requested : 0;
        page = rows.sublist(start);
      } else {
        final end = (offset + requested).clamp(0, rows.length);
        page = offset >= rows.length ? const [] : rows.sublist(offset, end);
      }
      request.response.write(jsonEncode({'messages': page}));
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  }

  void push(Map<String, Object?> payload) {
    for (final socket in List<WebSocket>.of(sockets)) {
      socket.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {
            'type': payload['type'],
            'session_id': 'rt-1',
            'payload': payload,
          },
        }),
      );
    }
  }

  Future<void> dropSockets() async {
    for (final socket in List<WebSocket>.of(sockets)) {
      await socket.close();
    }
    sockets.clear();
  }

  Future<void> close() async {
    await dropSockets();
    await server.close(force: true);
  }
}
