import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conduit_core/features/hermes/models/hermes_config.dart';
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
      socket.add(
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
            result = {
              'session_id': 'rt-1',
              'stored_session_id': 'st-1',
              'running': running,
              'info': {'running': running, 'desktop_contract': 7},
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
        socket.add(
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
      request.response.write(jsonEncode({'messages': const []}));
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
