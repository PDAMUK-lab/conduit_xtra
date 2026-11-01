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
    if (_closed || storedId == null || !_foreground || _liveWatchInFlight) {
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
          timeout: const Duration(seconds: 10),
        ),
      );
      if (_closed) return;
      _liveWatchFailures = 0;
      _applyWatchActiveList(result, storedId, binding);
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
  void _applyWatchActiveList(
    Map<String, dynamic> result,
    String storedId,
    HermesSessionBinding binding,
  ) {
    Map<String, dynamic>? row;
    final rows = result['sessions'];
    if (rows is List) {
      for (final item in rows) {
        if (item is! Map) continue;
        if (item['session_key'] == storedId ||
            item['session_key'] == binding.storedId ||
            item['id'] == binding.runtimeId) {
          row = Map<String, dynamic>.from(item);
          break;
        }
      }
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
