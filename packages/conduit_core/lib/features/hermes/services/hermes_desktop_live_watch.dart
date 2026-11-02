part of 'hermes_desktop_api_service.dart';

/// Keeps an open chat truthful while another client runs the turn.
///
/// The gateway pushes `message.delta` / `message.complete` and the terminal
/// `session.info(running: false)` to every attached viewer, but a phone loses
/// frames for reasons no client controls: the screen sleeps, the radio moves
/// networks, the OS freezes the socket without a FIN. When the terminal frame
/// is the one that goes missing, the chat keeps its typing indicator up and
/// never loads the reply — the operator has to open the dashboard to see it.
///
/// So the socket is not trusted to be alive and the state is not trusted to be
/// current: while a chat is open in the foreground, the service reads
/// `session.active_list` on an interval — the gateway's own per-session
/// `status`, a few hundred bytes, no side effects. (A resume would do it too,
/// but it re-attaches the transport and re-emits `session.info`, waking every
/// viewer's UI; `session.info` is an event, not an RPC, and answering it by
/// method returns -32601.) A request that times out or comes back disconnected
/// proves the socket dead and triggers a reconnect plus a resume.
extension _HermesDesktopLiveWatch on HermesDesktopApiService {
  /// The session the user last opened; the one the watch keeps honest.
  void _noteLiveSession(String storedId) {
    if (_closed || storedId.isEmpty) return;
    _liveSessionId = storedId;
    _liveWatchFailures = 0;
    _startLiveWatch();
  }

  void _startLiveWatch() {
    if (_closed || _liveWatchTimer != null) return;
    _liveWatchTimer = Timer.periodic(
      liveWatchInterval,
      (_) => unawaited(_liveWatchTick()),
    );
  }

  Future<void> _liveWatchTick() async {
    final storedId = _liveSessionId;
    // ignore: avoid_print
    print('HERMES_WATCH tick stored=$storedId fg=$_foreground');
    // Runs while backgrounded too: with no socket events arriving on a locked
    // phone (MIUI reports `inactive`, never `paused`, and the lease keeps the
    // isolate alive), this poll is the only thing that learns the reply landed.
    if (_closed || storedId == null || _liveWatchInFlight) {
      return;
    }
    final binding = _bindings[storedId];
    if (binding == null) return;
    _liveWatchInFlight = true;
    try {
      if (!_rpc.isReady) {
        // The socket is already gone (its close may have raced the listener).
        // Reopen it rather than spending a refusal on "not connected".
        await _recoverLiveTransport(storedId);
        return;
      }
      final result = _object(
        await _rpc.request<Object?>(
          'session.active_list',
          params: {
            'current_session_id': binding.runtimeId,
            ..._sessionScope(storedId),
          },
        ),
      );
      if (_closed) return;
      _liveWatchFailures = 0;
      await _applyWatchActiveList(result, storedId, binding);
    } on HermesDesktopRpcException catch (error) {
      if (_closed) return;
      if (error.disconnected || error.timedOut) {
        await _recoverLiveTransport(storedId);
      } else {
        _liveWatchRefused();
      }
    } catch (_) {
      // Anything else is transient; the next tick asks again.
    } finally {
      _liveWatchInFlight = false;
    }
  }

  /// Applies a `session.active_list` row for the open session: the gateway's
  /// own `status` is the turn state, and a row that is absent means this
  /// profile has no live turn for it.
  ///
  /// `active_list` is used instead of `session.resume` because it is a few
  /// hundred bytes with no side effects — a resume re-attaches the transport
  /// and re-emits `session.info`, which woke every viewer's UI on every tick.
  Future<void> _applyWatchActiveList(
    Map<String, dynamic> result,
    String storedId,
    HermesSessionBinding binding,
  ) async {
    Map<String, dynamic>? row;
    // The same stored session can be live under several runtimes (this app, a
    // desktop window, the browser's terminal). Take the longest history across
    // them: that is what the session actually holds, and a count that grew
    // means new content arrived whichever client ran the turn.
    var messageCount = -1;
    final rows = result['sessions'];
    if (rows is List) {
      for (final item in rows) {
        if (item is! Map) continue;
        final matchesStored = item['session_key'] == storedId ||
            item['session_key'] == binding.storedId;
        if (!matchesStored && item['id'] != binding.runtimeId) continue;
        row ??= Map<String, dynamic>.from(item);
        final count = item['message_count'];
        if (count is num && count.toInt() > messageCount) {
          messageCount = count.toInt();
        }
      }
    }
    if (row == null) {
      // Absent is not idle. A gateway-owned reply, a session the registry has
      // not rebuilt yet, or an id that does not match all look the same from
      // here, and reading that as "not running" flips the chat to Ready under a
      // live turn (the operator saw exactly that). Only a sustained absence —
      // three ticks — means the gateway really has no turn for this session.
      _liveWatchAbsences++;
      if (_liveWatchAbsences < 3) return;
    } else {
      _liveWatchAbsences = 0;
    }
    final status = row?['status']?.toString() ?? '';
    final running =
        status == 'working' || status == 'starting' || status == 'waiting';
    final changed = _applyAuthoritativeRunning(
      running,
      storedId: storedId,
      runtimeId: binding.runtimeId,
    );
    if (changed) _queueTranscriptChange(storedId);
    await _probeNewestRow(storedId);
  }

  /// Asks for the session's newest row and reloads when it is not the one this
  /// chat ends with.
  ///
  /// Events and `message_count` both failed in practice: a turn run under
  /// another runtime can complete without a completion frame here, and the
  /// counts are per-runtime history lengths that do not always move. One row
  /// (`limit=1`, newest) is cheap, authoritative, and cannot be missed — the
  /// only question it answers is "is what I am showing still the tail?".
  Future<void> _probeNewestRow(String storedId) async {
    final local = _lastTranscripts[storedId];
    try {
      final probe = _objects(
        await _requestJson(
          'GET',
          '/api/sessions/${Uri.encodeComponent(storedId)}/messages',
          query: {
            'limit': 1,
            'offset': 0,
            'order': 'latest',
            'include_compacted': true,
            ..._sessionScope(storedId),
          },
        ),
        'messages',
      );
      if (_closed || probe.isEmpty) return;
      final newestId = probe.last['id'];
      final knownId = local == null || local.isEmpty ? null : local.last['id'];
      // No tail at all (a chat opened before it had rows) counts as stale too.
      if (newestId == null || newestId == knownId) return;
      // ignore: avoid_print
      print('HERMES_WATCH new-tail newest=$newestId known=$knownId fg=$_foreground');
      _queueTranscriptChange(storedId);
      // A new tail while the app is not looking is exactly the case the socket
      // event was supposed to report and did not. Fire the alert from the poll
      // that provably ran, not from a frame that never arrived — once per row:
      // the transcript merge lags the probe, so an unguarded call re-alerts on
      // the same row every tick until the merge catches up.
      if (!_foreground && _alertedTailIds[storedId] != newestId) {
        _alertedTailIds[storedId] = newestId;
        HermesBackgroundAlerts.replyReady(storedId);
      }
    } catch (e) {
      // Transient network failures are expected; anything else here used to be
      // invisible, which is how a type error in the alert guard went unnoticed
      // for a whole build.
      // ignore: avoid_print
      print('HERMES_WATCH probe error: $e');
    }
  }

  /// A refusal is a gateway answer, so the socket is fine; it says nothing
  /// about the turn. Three in a row stop the poll until the chat page loads
  /// the session again, instead of hammering a session this profile cannot
  /// resume. The state is deliberately left as it was: a refusal must not
  /// clear a running turn.
  void _liveWatchRefused() {
    _liveWatchFailures++;
    DebugLogger.warning(
      'live-watch-refused',
      scope: 'hermes/desktop/watch',
      data: {'failures': _liveWatchFailures},
    );
    if (_liveWatchFailures <= 2) return;
    _liveWatchTimer?.cancel();
    _liveWatchTimer = null;
  }

  /// Reopens the socket, rebinds the open session and reloads its transcript.
  ///
  /// Backs off while the gateway stays unreachable so a phone with no network
  /// does not reconnect twice a second; the next successful resume resets it.
  Future<void> _recoverLiveTransport(String storedId) async {
    if (_closed || _recoveringLiveTransport) return;
    final last = _lastRecoveryAt;
    if (last != null && DateTime.now().difference(last) < _recoveryBackoff) {
      return;
    }
    _recoveringLiveTransport = true;
    _emitTurnState(HermesDesktopTurnState.reconnecting);
    var recovered = false;
    try {
      await _rpc.disconnect();
      _bindings.clear();
      _bindingSocketGenerations.clear();
      _freshSessionIds.clear();
      await _ensureConnected();
      if (_closed) return;
      await _resume(storedId, refresh: true);
      if (_closed) return;
      _noteLiveSession(storedId);
      _queueTranscriptChange(storedId);
      recovered = true;
    } catch (_) {
      // Still unreachable: keep the backoff so the next attempt waits longer.
    } finally {
      _recoveringLiveTransport = false;
      _lastRecoveryAt = DateTime.now();
      DebugLogger.warning(
        'live-watch-recover',
        scope: 'hermes/desktop/watch',
        data: {'recovered': recovered},
      );
      if (recovered) {
        _recoveryBackoff = Duration.zero;
      } else {
        final next = _recoveryBackoff == Duration.zero
            ? const Duration(seconds: 2)
            : _recoveryBackoff * 2;
        _recoveryBackoff = next > const Duration(seconds: 30)
            ? const Duration(seconds: 30)
            : next;
      }
    }
  }

  /// The socket closed on its own (server restart, network change, keepalive
  /// expiry). The chat page is not going to issue a request by itself, so the
  /// watch repairs it now rather than at the next user action.
  void _liveTransportDisconnected() {
    final storedId = _liveSessionId;
    if (_closed || storedId == null || !_foreground) return;
    unawaited(_recoverLiveTransport(storedId));
  }
}
