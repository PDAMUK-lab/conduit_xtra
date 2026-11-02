part of 'hermes_desktop_api_service.dart';

extension _HermesDesktopLiveRuntime on HermesDesktopApiService {
  Future<void> _ensureConnected() async {
    if (_closed) throw StateError('Hermes service is closed.');
    if (_rpc.isReady) return;
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<void> _connect() async {
    _emitTurnState(HermesDesktopTurnState.reconnecting);
    final status = await statusProbe(refresh: true);
    if (_closed) throw StateError('Hermes service is closed.');
    final query = <String, String>{};
    if (status['auth_required'] == true) {
      final ticketData = await _requestJson('POST', '/api/auth/ws-ticket');
      if (_closed) throw StateError('Hermes service is closed.');
      final ticket = ticketData is Map
          ? ticketData['ticket']?.toString()
          : null;
      if (ticket == null || ticket.isEmpty) {
        throw StateError('Hermes did not issue a WebSocket ticket.');
      }
      query['ticket'] = ticket;
    } else {
      final token = config.desktopCredentials?.legacyToken;
      if (token == null || token.isEmpty) {
        throw StateError('Hermes requires a legacy session token.');
      }
      query['token'] = token;
    }
    final httpUri = _uri('/api/ws').replace(queryParameters: query);
    final wsUri = httpUri.replace(
      scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
    );
    await _rpc.connect(
      wsUri,
      headers: config.accessHeaders,
      httpClient: hermesTlsHttpClient(config),
    );
    if (_closed) {
      await _rpc.disconnect();
      return;
    }
    _disconnectSubscription ??= _rpc.disconnects.listen(
      (_) => _liveTransportDisconnected(),
    );
    _stateSubscription ??= _rpc.events.listen((event) {
      _eventBuffer.add(event);
      _recordLiveActivity(event);
      final eventStoredId = _storedIdForRuntime(event.sessionId);
      if (event.type == 'session.info') {
        // Update BOTH keys. `session.create` can omit `running`, which parks
        // the stored id at unsupportedGateway; a runtime-only update never
        // clears that, so the second turn onward fails the safety gate with
        // "Hermes run failed." until a resume repairs the state.
        final changed = _applyAuthoritativeRunning(
          event.payload['running'],
          storedId: eventStoredId,
          runtimeId: event.sessionId,
        );
        // A turn that just ended left a reply behind. Reload even when a
        // local stream is not running: the chat may be following a turn this
        // client did not start (dashboard, TUI, another phone), which is the
        // case that used to sit stale until the page was reopened.
        if (changed && eventStoredId != null) {
          _queueTranscriptChange(eventStoredId);
        }
      }
      if (event.type == 'approval.request' ||
          event.type == 'clarify.request' ||
          event.type == 'sudo.request' ||
          event.type == 'secret.request' ||
          event.type == 'mcp.setup.request') {
        unawaited(_persistPendingDecisionEvent(event));
      }
      if (event.type == 'approval.responded' ||
          event.type == 'approval.expire' ||
          event.type == 'clarify.expire' ||
          event.type == 'sudo.expire' ||
          event.type == 'secret.expire' ||
          event.type == 'mcp.setup.expire') {
        unawaited(_resolvePendingDecisionEvent(event));
      }
      // Every completion is a reason to reload, not only the first frame of a
      // burst: a viewer that is not streaming locally sees `message.start`
      // first, so keying the reload off the burst's opening frame dropped the
      // completion that followed it and the transcript never refreshed.
      final terminalEvent =
          event.type == 'message.complete' || event.type.endsWith('.request');
      // ignore: avoid_print
      if (terminalEvent || event.type == 'message.start') {
        print('HERMES_EVENT type=${event.type} stored=$eventStoredId '
            'runtime=${event.sessionId} foreground=$_foreground');
      }
      if (terminalEvent && eventStoredId != null) {
        _queueTranscriptChange(eventStoredId);
        // The app is not looking at this screen: the reply is the only thing the
        // user can act on, so hand it to the alert sink. Fired here, in the
        // handler that provably runs, not from a stream the UI may be driving.
        if (!_foreground) HermesBackgroundAlerts.replyReady(eventStoredId);
      } else if (terminalEvent &&
          event.sessionId != null &&
          event.sessionId!.isNotEmpty) {
        // A turn that ran under a runtime this client never resumed (the same
        // stored session driven from another window) arrives with an id the
        // binding map cannot resolve. Ask the gateway which stored session that
        // runtime belongs to instead of dropping the completion on the floor —
        // dropping it is why the open chat only caught up after a switch.
        // A turn this client did not start (locked phone, another window) lands
        // here, not in the branch above — so the alert must be raised here too.
        // Gated like the branch above; the unconditional form was a diagnostic.
        if (!_foreground) HermesBackgroundAlerts.replyReady(event.sessionId!);
        unawaited(_resolveRuntimeBinding(event.sessionId!));
      }
    });
    _emitTurnState(HermesDesktopTurnState.idle);
  }

  Future<void> _resolvePendingDecisionEvent(HermesDesktopEvent event) async {
    final runtimeId = validateHermesOpaqueIdentifier(event.sessionId);
    final requestId = validateHermesOpaqueIdentifier(
      event.payload['request_id'] ?? event.payload['id'],
      sensitiveValues: config.sensitiveValues,
    );
    if (runtimeId == null || requestId == null) return;
    await HermesPendingDecisionStore.resolve(
      origin: _origin,
      connectionId: config.connectionId,
      runtimeId: runtimeId,
      requestId: requestId,
    );
  }

  void _runtimeDidChangeAppLifecycleState(AppLifecyclePhase state) {
    switch (state) {
      case AppLifecyclePhase.paused:
      case AppLifecyclePhase.hidden:
      case AppLifecyclePhase.detached:
        // The OS may keep the socket alive. Reconcile on return instead of
        // closing a valid transport merely because the app backgrounded.
        _foreground = false;
        _reconciliationStale = true;
      case AppLifecyclePhase.resumed:
        _foreground = true;
        _foregroundReconciliation ??= _reconcileForeground().whenComplete(() {
          _foregroundReconciliation = null;
          // Coming back is also the moment to ask whether the turn this phone
          // was watching finished while it was away.
          unawaited(_liveWatchTick());
        });
      case AppLifecyclePhase.inactive:
        // A lock screen reports `inactive` on some devices (MIUI) and never
        // reaches `paused` while the process is kept alive by a lease — so the
        // client believed it was foregrounded through the whole lock and the
        // background alert could never fire. Measured: foreground=true in the
        // message.start line while the phone was being locked.
        _foreground = false;
        _reconciliationStale = true;
    }
    // TEMP-DIAGNOSTIC: remove once the inactive-on-lock path is confirmed.
    // ignore: avoid_print
    print('HERMES_LIFECYCLE phase=$state foreground=$_foreground');
  }

  Future<void> _reconcileForeground() async {
    if (!_reconciliationStale || _closed) return;
    _emitTurnState(HermesDesktopTurnState.synchronizing);
    final storedIds = _bindings.keys.toList(growable: false);
    try {
      await statusProbe(refresh: true);
      if (_closed) return;
      if (_rpc.isReady) {
        if (storedIds.isEmpty) {
          try {
            await _rpc.request<Object?>(
              'model.options',
              timeout: const Duration(seconds: 10),
            );
          } on HermesDesktopRpcException catch (error) {
            // A refusal with a JSON-RPC code means the gateway is answering:
            // it may refuse model inventory while running stale code after an
            // update, but the socket is healthy. Reconnecting on that would
            // mint tickets forever and never fix it.
            if (error.code == null || error.timedOut) rethrow;
          }
        } else {
          for (final storedId in storedIds) {
            await _resume(storedId, refresh: true);
            _emitTranscriptChange(storedId);
          }
        }
      } else {
        _bindings.clear();
        _bindingSocketGenerations.clear();
        _freshSessionIds.clear();
        await _ensureConnected();
        for (final storedId in storedIds) {
          await _resume(storedId);
          _emitTranscriptChange(storedId);
        }
      }
      _reconciliationStale = false;
    } catch (_) {
      await _rpc.disconnect();
      _bindings.clear();
      _bindingSocketGenerations.clear();
      _freshSessionIds.clear();
      _emitTurnState(HermesDesktopTurnState.reconnecting);
    }
  }

  /// Applies the gateway's own `running` flag to [storedId] and/or
  /// [runtimeId]; returns whether any of them actually changed, so callers can
  /// reload exactly once per real transition instead of once per frame.
  bool _applyAuthoritativeRunning(
    Object? running, {
    String? storedId,
    String? runtimeId,
  }) {
    final state = running is! bool
        ? HermesDesktopTurnState.unsupportedGateway
        : running
        ? HermesDesktopTurnState.running
        : HermesDesktopTurnState.idle;
    if (running is! bool) {
      _authoritativeRunning = false;
    } else {
      _authoritativeRunning = true;
    }
    var changed = false;
    for (final id in <String?>{storedId, runtimeId}) {
      if (id == null || id.isEmpty) continue;
      if (_sessionTurnStates[id] != state) changed = true;
      _sessionTurnStates[id] = state;
      _emitSessionTurnState(id);
    }
    _emitTurnState(state);
    return changed;
  }

  Map<String, dynamic> _object(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<Map<String, dynamic>> _objects(Object? value, [String? envelope]) {
    final source = envelope != null && value is Map ? value[envelope] : value;
    if (source is! List) return const [];
    return source
        .whereType<Map>()
        .take(10000)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<HermesSessionBinding> _resume(
    String storedId, {
    bool refresh = false,
  }) async => (await _resumeSnapshot(storedId, refresh: refresh)).binding;

  /// The profile that owns [storedId] — a Bot Mode chat's own profile, or the
  /// connection's configured one.
  ///
  /// Always explicit, never empty. The RPC transport injects the connection
  /// profile as a default, so omitting this does not mean "let the server
  /// decide": it means a request about a BOT session travels naming the
  /// CONNECTION's profile, and any handler that reads it resolves against the
  /// wrong profile's config and state.
  Map<String, dynamic> _sessionScope(String storedId) => {
    'profile': _sessionProfiles[storedId] ?? config.desktopProfile,
  };

  Future<({HermesSessionBinding binding, bool? running})> _resumeSnapshot(
    String storedId, {
    bool refresh = false,
  }) async {
    final existing = _bindings[storedId];
    if (!refresh &&
        existing != null &&
        _rpc.isReady &&
        _bindingSocketGenerations[storedId] == _rpc.socketGeneration) {
      return (binding: existing, running: null);
    }
    await _ensureConnected();
    _emitTurnState(HermesDesktopTurnState.synchronizing);
    final result = _object(
      await _rpc.request<Object?>(
        'session.resume',
        params: {
          'session_id': storedId,
          'omit_messages': true,
          ..._sessionScope(storedId),
        },
      ),
    );
    final runtime = validateHermesOpaqueIdentifier(result['session_id']);
    final stored = validateHermesOpaqueIdentifier(
      result['stored_session_id'] ?? result['session_key'] ?? storedId,
    );
    if (runtime == null || stored == null) {
      throw const FormatException('Hermes returned invalid session IDs.');
    }
    final info = _object(result['info']);
    final running = result['running'] ?? info['running'];
    _recordDesktopContract(info);
    final binding = HermesSessionBinding(storedId: stored, runtimeId: runtime);
    final profile = _sessionProfiles[storedId];
    if (profile != null) _sessionProfiles[stored] = profile;
    _bindings[storedId] = binding;
    _bindings[stored] = binding;
    _bindingSocketGenerations[storedId] = _rpc.socketGeneration;
    _bindingSocketGenerations[stored] = _rpc.socketGeneration;
    _applyAuthoritativeRunning(running, storedId: storedId, runtimeId: runtime);
    // The chat the user opened is the one the live watch has to keep honest
    // from here on, whether or not a local stream ever starts.
    _noteLiveSession(stored);
    if (stored != storedId) {
      _sessionTurnStates[stored] = turnStateFor(storedId);
      _emitSessionTurnState(stored);
    }
    await HermesPendingDecisionStore.rebindSession(
      origin: _origin,
      connectionId: config.connectionId,
      fromStoredSessionId: storedId,
      toStoredSessionId: stored,
      runtimeId: runtime,
    );
    for (final event in _eventBuffer.pending(runtime)) {
      await _persistPendingDecisionEvent(event);
    }
    await _restorePendingFromResume(result, binding);
    return (binding: binding, running: running is bool ? running : null);
  }

  Future<void> _restorePendingFromResume(
    Map<String, dynamic> result,
    HermesSessionBinding binding,
  ) async {
    final approval = _object(result['pending_approval']);
    final approvalId = validateHermesOpaqueIdentifier(
      approval['request_id'],
      sensitiveValues: config.sensitiveValues,
    );
    if (approvalId != null) {
      final command = approval['command']?.toString() ?? '';
      final description = approval['description']?.toString() ?? '';
      await HermesPendingDecisionStore.upsert(
        origin: _origin,
        connectionId: config.connectionId,
        storedSessionId: binding.storedId,
        runtimeId: binding.runtimeId,
        requestId: approvalId,
        kind: HermesPendingDesktopDecisionKind.approval,
        prompt: command.isNotEmpty ? command : description,
        choices: _desktopDecisionChoices(approval['choices']),
        sensitiveValues: config.sensitiveValues,
        profile: _sessionProfiles[binding.storedId],
      );
    }
    final clarify = _object(result['pending_clarify']);
    final clarifyId = validateHermesOpaqueIdentifier(
      clarify['request_id'],
      sensitiveValues: config.sensitiveValues,
    );
    if (clarifyId != null) {
      await HermesPendingDecisionStore.upsert(
        origin: _origin,
        connectionId: config.connectionId,
        storedSessionId: binding.storedId,
        runtimeId: binding.runtimeId,
        requestId: clarifyId,
        kind: HermesPendingDesktopDecisionKind.clarification,
        prompt: clarify['question']?.toString(),
        choices: _desktopDecisionChoices(clarify['choices']),
        multiSelect: clarify['multi_select'] == true,
        sensitiveValues: config.sensitiveValues,
        profile: _sessionProfiles[binding.storedId],
      );
    }
  }

  Future<String> _runtimeCreateSession({
    String? title,
    CancelToken? cancelToken,
  }) => createDesktopSession(
    title: title,
    options: const HermesDesktopSessionOptions(),
    cancelToken: cancelToken,
  );

  Future<String> _runtimeCreateDesktopSession({
    String? title,
    required HermesDesktopSessionOptions options,
    CancelToken? cancelToken,
    String? profile,
    bool hidden = false,
  }) async {
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    final selection = hermesDesktopSessionModelSelection(
      options.model,
      options.provider,
    );
    final reasoning = options.reasoningEffort?.trim();
    final normalized = HermesDesktopSessionOptions(
      model: selection.model,
      provider: selection.provider,
      reasoningEffort: reasoning?.isEmpty == true ? null : reasoning,
      fast: options.fast,
    );
    await _ensureConnected();
    final result = _object(
      await _rpc.request<Object?>(
        'session.create',
        params: {
          'source': 'mobile',
          'close_on_disconnect': false,
          'model': ?normalized.model,
          'provider': ?normalized.provider,
          'reasoning_effort': ?normalized.reasoningEffort,
          'fast': ?normalized.fast,
          'profile': ?profile,
          if (hidden) 'hidden': true,
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        },
      ),
    );
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    final runtime = validateHermesOpaqueIdentifier(result['session_id']);
    final stored = validateHermesOpaqueIdentifier(result['stored_session_id']);
    if (runtime == null || stored == null) {
      throw const FormatException('Hermes returned invalid session IDs.');
    }
    _bindings[stored] = HermesSessionBinding(
      storedId: stored,
      runtimeId: runtime,
    );
    _bindingSocketGenerations[stored] = _rpc.socketGeneration;
    _appliedSessionOptions[stored] = normalized.fingerprint;
    final info = _object(result['info']);
    _recordDesktopContract(info);
    final running = result['running'] ?? info['running'];
    if (running is bool) {
      _applyAuthoritativeRunning(running, storedId: stored, runtimeId: runtime);
    } else {
      _freshSessionIds.add(stored);
      _applyAuthoritativeRunning(null, storedId: stored, runtimeId: runtime);
    }
    return stored;
  }

  Future<List<Map<String, dynamic>>> _runtimeListSessions() async => _objects(
    await _requestJson(
      'GET',
      '/api/sessions',
      query: {'limit': 100, 'offset': 0, 'order': 'recent'},
    ),
    'sessions',
  );

  Future<List<Map<String, dynamic>>> _runtimeGetSessionMessages(
    String id, {
    CancelToken? cancelToken,
  }) async {
    // Hermes persists session.create lazily; resume fails until the first prompt.
    if (_freshSessionIds.contains(id) &&
        _bindings.containsKey(id) &&
        _rpc.isReady &&
        _bindingSocketGenerations[id] == _rpc.socketGeneration) {
      return const [];
    }
    // The REST transcript does not need a runtime binding, so a session that
    // the gateway refuses to resume (too large, wrong profile, transient
    // failure) can still be read. Hermes Desktop makes the same split: it
    // loads the transcript independently and treats resume as non-fatal for
    // display. Sending a prompt still resumes and surfaces that error itself.
    HermesSessionBinding? binding;
    try {
      binding = await _resume(id, refresh: true);
    } on HermesDesktopRpcException catch (error) {
      final isBotChat = _sessionProfiles.containsKey(id);
      // Timeouts and disconnects are transport failures, not gateway replies;
      // bot chats read history through the socket and need the runtime ID.
      if (error.deliveryAmbiguous || isBotChat) rethrow;
      DebugLogger.warning(
        'session-resume-failed-loading-rest',
        scope: 'hermes/desktop',
        data: {
          'code': error.code,
          'message': validateHermesBoundedString(
            error.message,
            maxCharacters: 200,
          ),
        },
      );
    }
    final runtimeId = binding?.runtimeId;
    final storedId = binding?.storedId ?? id;
    // A chat another client drives refreshes after every turn. Re-reading the
    // whole transcript costs 6–25 MB and ~1 s of local work for a 1,000–1,500
    // message session on this node, and grows with the chat — the "gets slower
    // the longer we talk" report. Only the newest page can have changed since
    // the last read, so try that first.
    if (binding != null) {
      final incremental = await _incrementalDesktopTranscript(
        id,
        cancelToken: cancelToken,
      );
      if (incremental != null) {
        _lastTranscripts[id] = incremental;
        return incremental;
      }
    }
    final hadBufferedEvent =
        runtimeId != null && _eventBuffer.take(runtimeId).isNotEmpty;
    final isBotChat = _sessionProfiles.containsKey(storedId);

    Future<List<Map<String, dynamic>>> load() async {
      if (isBotChat && runtimeId != null) {
        if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
        final messages = _objects(
          await _rpc.request<Object?>(
            'session.history',
            params: {'session_id': runtimeId, ..._sessionScope(storedId)},
          ),
          'messages',
        );
        if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
        return messages;
      }
      return loadHermesDesktopTranscriptPages(
        (offset, limit) async => _objects(
          await _requestJson(
            'GET',
            '/api/sessions/${Uri.encodeComponent(storedId)}/messages',
            query: {
              'limit': limit,
              'offset': offset,
              'order': 'oldest',
              'include_compacted': true,
              ..._sessionScope(storedId),
            },
            cancelToken: cancelToken,
          ),
          'messages',
        ),
      );
    }

    var forceReload = hadBufferedEvent;
    var messages = const <Map<String, dynamic>>[];
    for (var attempt = 0; attempt < 3; attempt++) {
      messages = await load();
      final arrivedDuringLoad =
          runtimeId != null && _eventBuffer.take(runtimeId).isNotEmpty;
      if (!forceReload && !arrivedDuringLoad) break;
      forceReload = false;
      // No re-emit here: a transcript change now comes from the event that
      // caused it (`message.complete`, a terminal `session.info`). Asking for
      // another reload from inside a reload looped forever while another
      // client's turn streamed into this session.
    }
    // A failed resume left the connection state at "synchronizing"; the
    // transcript is loaded, and no turn is known to be running.
    if (binding == null) _emitTurnState(HermesDesktopTurnState.idle);
    final usable = preferLastUsableHermesTranscript(
      _lastTranscripts[id] ?? const [],
      messages,
    );
    _lastTranscripts[id] = usable;
    return usable;
  }

  /// The newest page of [storedId], shrinking it when the REST transport
  /// refuses the payload (one tool-heavy row can exceed the cap on its own).
  Future<List<Map<String, dynamic>>> _latestDesktopTranscriptPage(
    String storedId, {
    CancelToken? cancelToken,
  }) async {
    var limit = kHermesDesktopTranscriptPageSize;
    while (true) {
      try {
        return _objects(
          await _requestJson(
            'GET',
            '/api/sessions/${Uri.encodeComponent(storedId)}/messages',
            query: {
              'limit': limit,
              'offset': 0,
              'order': 'latest',
              'include_compacted': true,
              ..._sessionScope(storedId),
            },
            cancelToken: cancelToken,
          ),
          'messages',
        );
      } on HermesResponseTooLargeException {
        if (limit <= kHermesDesktopTranscriptMinimumPageSize) rethrow;
        limit = max(
          kHermesDesktopTranscriptMinimumPageSize,
          limit ~/ 2,
        );
        DebugLogger.warning(
          'transcript-page-too-large',
          scope: 'hermes/desktop',
          data: {'limit': limit, 'order': 'latest'},
        );
      }
    }
  }

  /// Learns which stored session an unknown runtime id belongs to, then treats
  /// its completion like a local one (one transcript reload).
  Future<void> _resolveRuntimeBinding(String runtimeId) async {
    if (_closed || _resolvingRuntimes.contains(runtimeId)) return;
    if (_storedIdForRuntime(runtimeId) != null) return;
    _resolvingRuntimes.add(runtimeId);
    try {
      final rows = _objects(
        await _rpc.request<Object?>(
          'session.active_list',
          params: {'profile': config.desktopProfile},
          timeout: const Duration(seconds: 10),
        ),
        'sessions',
      );
      if (_closed) return;
      for (final row in rows) {
        final id = validateHermesOpaqueIdentifier(row['id']);
        final stored = validateHermesOpaqueIdentifier(
          row['session_key'] ?? row['stored_session_id'],
        );
        // Only the runtime that actually sent the event: binding every row in
        // turn would let the last one overwrite the id we came here to resolve.
        if (id != runtimeId || stored == null) continue;
        _bindings[stored] = HermesSessionBinding(
          storedId: stored,
          runtimeId: id!,
        );
        _bindingSocketGenerations[stored] = _rpc.socketGeneration;
        _queueTranscriptChange(stored);
        return;
      }
    } catch (_) {
      // Best-effort: the next terminal event, or a page load, repairs it.
    } finally {
      _resolvingRuntimes.remove(runtimeId);
    }
  }

  /// The newest page of [storedId], merged into the transcript already held.
  ///
  /// Returns null when the caller must do a full read: no snapshot yet, a bot
  /// chat (whose history comes from `session.history`), a gap larger than one
  /// page, or a server that does not answer `order=latest`.
  Future<List<Map<String, dynamic>>?> _incrementalDesktopTranscript(
    String storedId, {
    CancelToken? cancelToken,
  }) async {
    if (_sessionProfiles.containsKey(storedId)) return null;
    final previous = _lastTranscripts[storedId];
    if (previous == null || previous.isEmpty) return null;
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    final latest = await _latestDesktopTranscriptPage(
      storedId,
      cancelToken: cancelToken,
    );
    if (latest.isEmpty) return previous;
    final lastKnownId = previous.last['id'];
    if (lastKnownId != null && latest.last['id'] == lastKnownId) {
      // Nothing new: hand back the very same list so the page can skip the
      // conversion and the list rebuild as well as the download.
      return previous;
    }
    final known = <Object?>{for (final row in previous) row['id']};
    if (!latest.any((row) => known.contains(row['id']))) {
      // More new rows than one page: merging would drop the middle.
      return null;
    }
    final merged = List<Map<String, dynamic>>.of(previous);
    for (final row in latest) {
      if (known.contains(row['id'])) continue;
      merged.add(row);
    }
    return merged;
  }

  /// Opens [id] without waiting for its whole history.
  ///
  /// Tapping a long chat used to download every page before the screen could
  /// even switch (measured: 1,043–1,496 rows, 16–25 MB, ~1 s of local work on
  /// this node). The newest page is enough to show the chat; the rest is read
  /// in the background and arrives as a transcript change.
  Future<List<Map<String, dynamic>>> openDesktopSessionTranscript(
    String id, {
    CancelToken? cancelToken,
  }) async {
    final previous = _lastTranscripts[id];
    if (previous != null && previous.isNotEmpty) {
      return getSessionMessages(id, cancelToken: cancelToken);
    }
    try {
      final binding = await _resume(id, refresh: true);
      final storedId = binding.storedId;
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      final newest = await _latestDesktopTranscriptPage(
        storedId,
        cancelToken: cancelToken,
      );
      if (newest.isEmpty) {
        return await getSessionMessages(id, cancelToken: cancelToken);
      }
      _lastTranscripts[id] = newest;
      unawaited(_completeTranscriptInBackground(id, storedId));
      return newest;
    } catch (error) {
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      // The fast path is an optimisation, never the only way in. A session
      // another runtime still owns (resume refused), a page too large even at
      // the smallest size, or a transient transport error must not stop the
      // chat from opening — the full read tolerates a failed resume and pages
      // with shrinking limits.
      DebugLogger.warning(
        'open-fast-path-failed',
        scope: 'hermes/desktop',
        data: {'errorType': error.runtimeType.toString()},
      );
      return getSessionMessages(id, cancelToken: cancelToken);
    }
  }

  /// Reads the rest of [storedId] after [openDesktopSessionTranscript] showed
  /// its window, then asks the page to reload. Rows that arrived while the
  /// history was being read are kept, so a live reply is never dropped.
  Future<void> _completeTranscriptInBackground(
    String id,
    String storedId,
  ) async {
    try {
      final full = await loadHermesDesktopTranscriptPages(
        (offset, limit) async => _objects(
          await _requestJson(
            'GET',
            '/api/sessions/${Uri.encodeComponent(storedId)}/messages',
            query: {
              'limit': limit,
              'offset': offset,
              'order': 'oldest',
              'include_compacted': true,
              ..._sessionScope(storedId),
            },
          ),
          'messages',
        ),
      );
      if (_closed) return;
      final current = _lastTranscripts[id] ?? const <Map<String, dynamic>>[];
      if (full.length <= current.length) return;
      final known = <Object?>{for (final row in full) row['id']};
      for (final row in current) {
        if (known.contains(row['id'])) continue;
        full.add(row);
      }
      _lastTranscripts[id] = full;
      _emitTranscriptChange(id);
    } catch (error) {
      DebugLogger.warning(
        'transcript-backfill-failed',
        scope: 'hermes/desktop',
        data: {'errorType': error.runtimeType.toString()},
      );
    }
  }

  Future<List<HermesPendingDesktopDecision>> _runtimePendingDecisionsForSession(
    String storedId,
  ) async {
    // Restore the session's owning profile BEFORE resuming: after a restart
    // the in-memory map is empty, and an unrestored bot chat would resume and
    // answer under the connection profile.
    await _restorePersistedSessionProfile(storedId);
    final binding = await _resume(storedId);
    await _restorePersistedSessionProfile(binding.storedId);
    return HermesPendingDecisionStore.forSession(
      origin: _origin,
      connectionId: config.connectionId,
      storedSessionId: binding.storedId,
    );
  }

  /// Re-seeds `_sessionProfiles` from a durable pending decision, so a bot
  /// chat restored across a restart keeps its profile scope.
  Future<void> _restorePersistedSessionProfile(String storedId) async {
    if (_sessionProfiles.containsKey(storedId)) return;
    for (final decision in await HermesPendingDecisionStore.forSession(
      origin: _origin,
      connectionId: config.connectionId,
      storedSessionId: storedId,
    )) {
      final profile = decision.profile;
      if (profile != null) {
        _sessionProfiles[storedId] = profile;
        return;
      }
    }
  }

  Future<void> _runtimeRenameSession(String id, String title) async {
    final binding = await _resume(id);
    await _rpc.request<Object?>(
      'session.title',
      params: {
        'session_id': binding.runtimeId,
        'title': title,
        ..._sessionScope(binding.storedId),
      },
    );
  }

  Future<void> _runtimeDeleteSession(
    String id, {
    CancelToken? cancelToken,
  }) async {
    var binding = _bindings[id];
    if (binding != null) {
      try {
        binding = await _resume(id);
        await _rpc.request<Object?>(
          'session.close',
          params: {
            'session_id': binding.runtimeId,
            ..._sessionScope(binding.storedId),
          },
        );
      } catch (error) {
        DebugLogger.warning(
          'session-close-before-delete-failed',
          scope: 'hermes/desktop/sessions',
          data: {'errorType': error.runtimeType.toString()},
        );
      }
    }
    await _requestJson(
      'DELETE',
      '/api/sessions/${Uri.encodeComponent(binding?.storedId ?? id)}',
      query: _sessionScope(binding?.storedId ?? id),
      cancelToken: cancelToken,
    );
    if (binding != null) {
      _bindings.removeWhere((_, candidate) => identical(candidate, binding));
      _freshSessionIds.remove(binding.storedId);
      _bindingSocketGenerations.removeWhere(
        (alias, _) => !_bindings.containsKey(alias),
      );
      _lastTranscripts.remove(binding.storedId);
      _lastReplyIds.remove(binding.storedId);
      _sessionProfiles.remove(binding.storedId);
    }
    _lastTranscripts.remove(id);
    _lastReplyIds.remove(id);
    _sessionProfiles.remove(id);
    await HermesPendingDecisionStore.clearSession(
      origin: _origin,
      connectionId: config.connectionId,
      storedSessionId: binding?.storedId ?? id,
    );
  }

  bool _runtimeSessionIdsReferToSameBinding(String left, String right) =>
      left == right ||
      (_bindings[left] != null && identical(_bindings[left], _bindings[right]));

  Future<String> _runtimeForkSession(String id) async {
    final binding = await _resume(id);
    final result = _object(
      await _rpc.request<Object?>(
        'session.branch',
        params: {
          'session_id': binding.runtimeId,
          ..._sessionScope(binding.storedId),
        },
      ),
    );
    final runtime = validateHermesOpaqueIdentifier(result['session_id']);
    final stored = validateHermesOpaqueIdentifier(result['stored_session_id']);
    if (runtime == null || stored == null) {
      throw const FormatException('Hermes returned invalid branch IDs.');
    }
    _bindings[stored] = HermesSessionBinding(
      storedId: stored,
      runtimeId: runtime,
    );
    _bindingSocketGenerations[stored] = _rpc.socketGeneration;
    // A branch of a bot's chat lives in that bot's profile too; without this
    // every later call for the fork would target the configured profile.
    final profile = _sessionProfiles[binding.storedId];
    if (profile != null) _sessionProfiles[stored] = profile;
    return stored;
  }
}
