import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:conduit/platform/conduit_platform_apis.g.dart';
import 'package:conduit/core/services/background_streaming_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds typed platform lease payloads', () {
    final startedAt = DateTime.fromMillisecondsSinceEpoch(123456);

    final leases = buildBackgroundStreamLeasesForTesting(
      const ['voice-call'],
      requiresMicrophone: true,
      kind: BackgroundStreamKind.voice,
      startedAt: startedAt,
    );

    expect(leases, hasLength(1));
    final lease = leases.single.toPlatform();
    expect(lease.id, 'voice-call');
    expect(lease.kind, PlatformBackgroundStreamKind.voice);
    expect(lease.requiresMicrophone, isTrue);
    expect(lease.startedAtMillis, 123456);
  });

  test('a socket keepalive becomes a lease of its own', () {
    // It used to be filtered out here, so asking the platform to keep the process
    // alive for a socket started nothing at all — the whole reason a locked phone
    // stopped receiving turns.
    final leases = buildBackgroundStreamLeasesForTesting(
      const [BackgroundStreamingHandler.socketKeepaliveId, 'chat-stream-1'],
      requiresMicrophone: true,
      kind: BackgroundStreamKind.chat,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1),
    );

    expect(leases.map((lease) => lease.id), [
      BackgroundStreamingHandler.socketKeepaliveId,
      'chat-stream-1',
    ]);
    final keepalive = leases.first;
    expect(keepalive.kind, BackgroundStreamKind.socket);
    expect(
      keepalive.requiresMicrophone,
      isFalse,
      reason: 'a socket lease must never claim the microphone',
    );
    expect(leases.last.kind, BackgroundStreamKind.chat);
    expect(leases.last.requiresMicrophone, isTrue);
  });

  test('a socket-only request still produces one lease', () {
    final leases = buildBackgroundStreamLeasesForTesting(
      const [BackgroundStreamingHandler.socketKeepaliveId],
      requiresMicrophone: false,
      kind: BackgroundStreamKind.chat,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1),
    );

    expect(leases, hasLength(1));
    expect(leases.single.kind, BackgroundStreamKind.socket);
  });

  test('only a reply being written counts as a reply in progress', () {
    final handler = BackgroundStreamingHandler.instance;
    addTearDown(() => handler.debugSetActiveLeases(const []));
    final startedAt = DateTime.fromMillisecondsSinceEpoch(1);
    // How read-aloud and a note recording hold the app open.
    final readAloud = buildBackgroundStreamLeasesForTesting(
      const ['tts-server-1'],
      requiresMicrophone: false,
      kind: BackgroundStreamKind.chat,
      startedAt: startedAt,
    );
    final recording = buildBackgroundStreamLeasesForTesting(
      const ['note-recording'],
      requiresMicrophone: true,
      kind: BackgroundStreamKind.voice,
      startedAt: startedAt,
    );

    handler.debugSetActiveLeases([...readAloud, ...recording]);
    check(handler.hasActiveStreams).isTrue();
    check(handler.hasActiveReplyStreams).isFalse();

    handler.debugSetActiveLeases([
      ...readAloud,
      ...buildBackgroundStreamLeasesForTesting(
        const ['chat-stream-assistant-1'],
        requiresMicrophone: false,
        kind: BackgroundStreamKind.chat,
        startedAt: startedAt,
        isReply: true,
      ),
    ]);
    check(handler.hasActiveReplyStreams).isTrue();
  });

  test(
    'forwards native service failures with their exact stream owners',
    () async {
      List<String>? failedStreamIds;
      await BackgroundStreamingHandler.instance.initialize(
        serviceFailedCallback: (_, _, streamIds) {
          failedStreamIds = streamIds;
        },
      );

      BackgroundStreamingHandler.instance.serviceFailed(
        PlatformServiceFailureEvent(
          error: 'service stopped',
          errorType: 'native',
          streamIds: const <String>['chat-stream-assistant-1'],
        ),
      );

      check(failedStreamIds)
          .isNotNull()
          .deepEquals(const <String>['chat-stream-assistant-1']);
    },
  );
}
