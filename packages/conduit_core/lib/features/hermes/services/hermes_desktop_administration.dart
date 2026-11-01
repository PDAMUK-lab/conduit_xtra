part of 'hermes_desktop_api_service.dart';

final class _HermesDesktopAdministration {
  const _HermesDesktopAdministration(this._owner);

  final HermesDesktopApiService _owner;

  Future<List<HermesDesktopModelOption>> configuredModels() async {
    await _owner._ensureConnected();
    final result = _owner._object(
      await _owner._rpc.request<Object?>(
        'model.options',
        params: const {'explicit_only': true},
      ),
    );
    return parseHermesDesktopConfiguredModels(result)
        .map(HermesDesktopModelOption.fromJson)
        .where((model) => model.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> listSkills() async {
    await _owner._ensureConnected();
    final installed = _owner._object(
      await _owner._rpc.request<Object?>(
        'skills.manage',
        params: const {'action': 'list'},
      ),
    );
    final commands = await listCommands();
    final descriptions = <String, String>{};
    for (final command in commands) {
      descriptions[command['name']?.toString() ?? ''] =
          command['description']?.toString() ?? '';
    }
    final rows = installed['skills'];
    if (rows is! List) return const [];
    return rows
        .take(256)
        .map<Map<String, dynamic>>((row) {
          final map = row is Map ? Map<String, dynamic>.from(row) : null;
          final name = (map?['name'] ?? row).toString().replaceFirst(
            RegExp(r'^/'),
            '',
          );
          return {
            'name': name,
            'description':
                map?['description']?.toString() ?? descriptions[name] ?? '',
          };
        })
        .where((row) => (row['name'] as String).isNotEmpty)
        .toList();
  }

  Future<List<Map<String, dynamic>>> listCommands() async {
    await _owner._ensureConnected();
    final result = _owner._object(
      await _owner._rpc.request<Object?>('commands.catalog'),
    );
    final rows =
        result['pairs'] ??
        result['commands'] ??
        result['all'] ??
        result['items'];
    if (rows is! List) return const [];
    return rows
        .take(1000)
        .map<Map<String, dynamic>>((row) {
          if (row is List && row.isNotEmpty) {
            return {
              'name': row.first.toString().replaceFirst(RegExp(r'^/'), ''),
              'description': row.length > 1 ? row[1].toString() : '',
            };
          }
          return row is Map ? Map<String, dynamic>.from(row) : const {};
        })
        .where((row) => row.isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>> reloadSkills() async {
    await _owner._ensureConnected();
    return _owner._object(await _owner._rpc.request<Object?>('skills.reload'));
  }

  Future<List<Map<String, dynamic>>> listToolsets() async {
    await _owner._ensureConnected();
    final result = _owner._object(
      await _owner._rpc.request<Object?>('tools.list'),
    );
    return _owner._objects(result['sections'] ?? result['toolsets']);
  }

  Future<void> configureTools(
    List<String> names, {
    required bool enabled,
  }) async {
    await _owner._ensureConnected();
    await _owner._rpc.request<Object?>(
      'tools.configure',
      params: {'action': enabled ? 'enable' : 'disable', 'names': names},
    );
  }

  Future<List<HermesMcpServer>> mcpServers() async => _owner
      ._objects((await mcpRequest('mcp.servers.list'))['servers'])
      .map(HermesMcpServer.fromJson)
      .where((server) => server.name.isNotEmpty)
      .toList(growable: false);

  Future<List<HermesMcpCatalogEntry>> mcpCatalog() async {
    final rows = (await mcpRequest('mcp.catalog'))['servers'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map(HermesMcpCatalogEntry.fromJson)
        .where((entry) => entry.name.isNotEmpty && !entry.installed)
        .toList(growable: false);
  }

  Future<void> addMcpServer({
    required String name,
    String? url,
    String? command,
    List<String> arguments = const [],
    String? bearerToken,
    HermesMcpToolFilter? toolFilter,
  }) async {
    await mcpRequest(
      'mcp.servers.add',
      params: {
        'name': name,
        'config': hermesMcpServerConfig(
          url: url,
          command: command,
          arguments: arguments,
          toolFilter: toolFilter,
        ),
        if (bearerToken?.isNotEmpty == true) 'bearer_token': bearerToken,
      },
    );
    await reloadMcp();
  }

  Future<void> addMcpPreset(String name) async {
    await mcpRequest('mcp.servers.add', params: {'name': name, 'preset': name});
    await reloadMcp();
  }

  Future<HermesMcpTestResult> testMcpServer(String name) async =>
      HermesMcpTestResult.fromJson(
        await mcpRequest('mcp.servers.test', params: {'name': name}),
      );

  Future<void> setMcpApiKey(String name, String value) async {
    await mcpRequest(
      'mcp.servers.set_api_key',
      params: {'name': name, 'value': value},
    );
    await reloadMcp();
  }

  Future<void> removeMcpServer(String name) async {
    await mcpRequest('mcp.servers.remove', params: {'name': name});
    await reloadMcp();
  }

  Future<bool> authenticateMcpServer(String name) async {
    final result = await _completeMcpOAuth(name);
    if (result == null) return false;
    await reloadMcp();
    return true;
  }

  Future<Map<String, dynamic>?> _completeMcpOAuth(String name) async {
    final started = await mcpRequest(
      'mcp.servers.oauth.start',
      params: {'name': name},
    );
    final flowId = validateHermesOpaqueIdentifier(started['session_id']);
    final authUrl = parseHermesOAuthUrl(started['auth_url']);
    if (flowId == null ||
        authUrl == null ||
        !await _owner._openExternalUrl.open(authUrl)) {
      return null;
    }
    for (var attempt = 0; attempt < 60; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final status = (await mcpRequest(
        'mcp.servers.oauth.poll',
        params: {'name': name, 'session_id': flowId},
      ));
      if (_owner._closed) return null;
      final state = status['status']?.toString();
      if (const {'approved', 'authorized', 'complete'}.contains(state)) {
        return status;
      }
      if (const {'error', 'failed', 'expired'}.contains(state)) return null;
    }
    return null;
  }

  Future<Map<String, dynamic>> mcpRequest(
    String method, {
    Map<String, dynamic> params = const {},
  }) async {
    await _owner._ensureConnected();
    try {
      return _owner._object(
        await _owner._rpc.request<Object?>(method, params: params),
      );
    } on HermesDesktopRpcException catch (error) {
      if (error.code != -32601) rethrow;
      if (method.startsWith('mcp.servers.')) {
        _owner._supportsMcpRpcLifecycle = false;
      }
      return _mcpRestFallback(method, params);
    }
  }

  Future<Map<String, dynamic>> _mcpRestFallback(
    String method,
    Map<String, dynamic> params,
  ) async {
    final name = params['name']?.toString() ?? '';
    final encodedName = Uri.encodeComponent(name);
    switch (method) {
      case 'mcp.servers.list':
        return _owner._object(
          await _owner._requestJson('GET', '/api/mcp/servers'),
        );
      case 'mcp.catalog':
        final result = _owner._object(
          await _owner._requestJson('GET', '/api/mcp/catalog'),
        );
        return {...result, 'servers': result['entries'] ?? const []};
      case 'mcp.servers.add':
        final preset = params['preset']?.toString();
        if (preset != null && preset.isNotEmpty) {
          return _owner._object(
            await _owner._requestJson(
              'POST',
              '/api/mcp/catalog/install',
              body: {'name': preset, 'enable': true},
            ),
          );
        }
        final config = _owner._object(params['config']);
        return _owner._object(
          await _owner._requestJson(
            'POST',
            '/api/mcp/servers',
            body: {
              'name': name,
              ...config,
              if (params['bearer_token'] != null)
                'bearer_token': params['bearer_token'],
            },
          ),
        );
      case 'mcp.servers.test':
        return _owner._object(
          await _owner._requestJson(
            'POST',
            '/api/mcp/servers/$encodedName/test',
          ),
        );
      case 'mcp.servers.remove':
        return _owner._object(
          await _owner._requestJson('DELETE', '/api/mcp/servers/$encodedName'),
        );
      case 'mcp.servers.oauth.start':
        final result = _owner._object(
          await _owner._requestJson(
            'POST',
            '/api/mcp/servers/$encodedName/auth',
          ),
        );
        return {
          ...result,
          'session_id': result['flow_id'],
          'auth_url': result['authorization_url'],
        };
      case 'mcp.servers.oauth.poll':
        final flowId = Uri.encodeComponent(
          params['session_id']?.toString() ?? '',
        );
        return _owner._object(
          await _owner._requestJson('GET', '/api/mcp/oauth/flows/$flowId'),
        );
      default:
        throw StateError(
          'Upgrade Hermes Desktop Gateway to use this MCP operation.',
        );
    }
  }

  Future<void> setMcpServerEnabled(String name, bool enabled) async {
    await _owner._requestJson(
      'PUT',
      '/api/mcp/servers/${Uri.encodeComponent(name)}/enabled',
      body: {'enabled': enabled},
    );
    await reloadMcp();
  }

  Future<void> reloadMcp({String? runtimeId}) async {
    await _owner._ensureConnected();
    final runtimeIds = <String>{};
    if (runtimeId != null) {
      runtimeIds.add(runtimeId);
    } else {
      for (final storedId
          in _owner._bindings.values
              .map((binding) => binding.storedId)
              .toSet()) {
        runtimeIds.add((await _owner._resume(storedId)).runtimeId);
      }
    }
    for (final id in runtimeIds) {
      await _owner._rpc.request<Object?>(
        'reload.mcp',
        // Bound sessions can include bot chats, which live in another profile.
        params: {
          'confirm': true,
          'session_id': id,
          ..._owner._runtimeScope(id),
        },
      );
    }
  }

  Future<Map<String, dynamic>> capabilities() async {
    Future<bool> supported(Future<Object?> Function() probe) async {
      try {
        await probe();
        return true;
      } on HermesDesktopRpcException catch (error) {
        if (error.code == -32601) return false;
        return false;
      } on DioException catch (error) {
        if (error.response?.statusCode == 404) return false;
        return false;
      } catch (_) {
        return false;
      }
    }

    await _owner._ensureConnected();
    final support = await Future.wait<bool>([
      supported(
        () => _owner._rpc.request<Object?>(
          'skills.manage',
          params: const {'action': 'list'},
        ),
      ),
      supported(() => _owner._rpc.request<Object?>('tools.list')),
      supported(
        () => _owner._requestJson('GET', '/api/cron/jobs', query: {'limit': 1}),
      ),
    ]);
    final [skills, toolsets, jobs] = support;
    return {
      'run_approval': true,
      'skills': skills,
      'toolsets': toolsets,
      'jobs': jobs,
      'jobs_admin': jobs,
      'sessions': true,
      'desktop_gateway': true,
      'desktop_uploads': _owner._desktopContract >= 2,
      'authoritative_running': _owner._authoritativeRunning,
    };
  }

  Future<List<Map<String, dynamic>>> listJobs() async =>
      _owner._objects(await _owner._requestJson('GET', '/api/cron/jobs'));

  Future<Map<String, dynamic>> createJob({
    required String name,
    required String prompt,
    required String schedule,
  }) async => _owner._object(
    await _owner._requestJson(
      'POST',
      '/api/cron/jobs',
      body: {
        'name': name,
        'prompt': prompt,
        'schedule': schedule,
        'deliver': 'local',
      },
    ),
  );

  Future<void> updateJob(
    String id, {
    String? name,
    String? prompt,
    String? schedule,
    bool? enabled,
  }) async {
    await _owner._requestJson(
      'PUT',
      '/api/cron/jobs/${Uri.encodeComponent(id)}',
      body: {
        'updates': {
          'name': ?name,
          'prompt': ?prompt,
          'schedule': ?schedule,
          'enabled': ?enabled,
        },
      },
    );
  }

  Future<void> mutateJob(String id, String method, String suffix) async {
    await _owner._requestJson(
      method,
      '/api/cron/jobs/${Uri.encodeComponent(id)}$suffix',
    );
  }

  Future<List<Map<String, dynamic>>> listJobRuns(String id) async =>
      _owner._objects(
        await _owner._requestJson(
          'GET',
          '/api/cron/jobs/${Uri.encodeComponent(id)}/runs',
          query: {'limit': 20},
        ),
        'runs',
      );
  Future<void> respondToMcpSetup({
    required String runtimeId,
    required String requestId,
    required bool approved,
    required String? server,
    required String? action,
  }) async {
    final safeServer = validateHermesBoundedString(server, maxCharacters: 128);
    final safeAction = const {'authorize', 'enable', 'install'}.contains(action)
        ? action
        : null;
    if (safeServer == null || safeAction == null) {
      throw StateError('Hermes returned an invalid MCP setup request.');
    }
    Map<String, dynamic> outcome = {'server': safeServer, 'status': 'declined'};
    if (approved) {
      try {
        switch (safeAction) {
          case 'install':
            await mcpRequest(
              'mcp.servers.add',
              params: {'name': safeServer, 'preset': safeServer},
            );
            outcome = {'server': safeServer, 'status': 'installed'};
          case 'enable':
            await setMcpServerEnabled(safeServer, true);
            outcome = {'server': safeServer, 'status': 'enabled'};
          case 'authorize':
            final approvedResult = await _completeMcpOAuth(safeServer);
            if (approvedResult == null) {
              throw TimeoutException('MCP authorization timed out.');
            }
            outcome = {
              'server': safeServer,
              'status': 'authorized',
              if (approvedResult['tools'] is List)
                'tools': (approvedResult['tools'] as List)
                    .take(1000)
                    .map((tool) => tool.toString())
                    .toList(growable: false),
            };
        }
        await reloadMcp(runtimeId: runtimeId);
      } catch (error) {
        DebugLogger.warning(
          'mcp-setup-failed',
          scope: 'hermes/mcp',
          data: {'errorType': error.runtimeType.toString()},
        );
        outcome = {
          'server': safeServer,
          'status': 'error',
          'detail': 'MCP setup failed. Open Hermes MCP settings to retry.',
        };
      }
    }
    await _owner._rpc.request<Object?>(
      'mcp.setup.respond',
      params: {
        'session_id': runtimeId,
        'request_id': requestId,
        'result': jsonEncode(outcome),
        ..._owner._runtimeScope(runtimeId),
      },
    );
    await HermesPendingDecisionStore.resolve(
      origin: _owner._origin,
      connectionId: _owner.config.connectionId,
      runtimeId: runtimeId,
      requestId: requestId,
    );
  }

  // --- Dashboard skills and memory -----------------------------------------
  //
  // The dashboard's own REST surface, not the RPC gateway: `GET /api/skills`
  // and friends are the contract the web UI uses, and they carry the enabled
  // flag, usage counts and raw SKILL.md text that the chat-facing RPC list
  // does not expose. Shapes measured against Hermes 0.22.5.

  Future<List<HermesSkill>> dashboardSkills() async {
    final data = await _owner._requestJson('GET', '/api/skills');
    return HermesSkill.listFromJson(data);
  }

  Future<String> skillContent(String name) async {
    final data = _owner._object(
      await _owner._requestJson(
        'GET',
        '/api/skills/content',
        query: {'name': name},
      ),
    );
    final content = data['content'];
    if (content is! String) {
      throw const FormatException('Invalid Hermes skill content.');
    }
    return content;
  }

  Future<void> updateSkillContent({
    required String name,
    required String content,
  }) => _owner._requestJson(
    'PUT',
    '/api/skills/content',
    body: {'name': name, 'content': content},
  );

  Future<void> setSkillEnabled({
    required String name,
    required bool enabled,
  }) => _owner._requestJson(
    'PUT',
    '/api/skills/toggle',
    body: {'name': name, 'enabled': enabled},
  );

  Future<void> createSkill({
    required String name,
    required String content,
    String? category,
  }) => _owner._requestJson(
    'POST',
    '/api/skills',
    body: {
      'name': name,
      'content': content,
      if (category != null && category.trim().isNotEmpty)
        'category': category.trim(),
    },
  );

  /// `GET /api/memory`: the active provider, every discovered provider with
  /// its readiness, and the built-in files' sizes.
  Future<Map<String, dynamic>> memoryStatus() async =>
      _owner._object(await _owner._requestJson('GET', '/api/memory'));

  Future<void> setMemoryProvider(String provider) => _owner._requestJson(
    'PUT',
    '/api/memory/provider',
    body: {'provider': provider},
  );

  // --- Toolsets (dashboard /api/tools) -------------------------------------
  //
  // Verified against hermes_cli/web_routers/tools.py: the list route returns a
  // bare array; toggle answers {ok,name,platform,enabled,post_setup_started};
  // config carries providers with env_vars/is_set; models carries the catalog
  // with current/default.

  Future<List<HermesToolsetSummary>> dashboardToolsets() async {
    final data = await _owner._requestJson('GET', '/api/tools/toolsets');
    return HermesToolsetSummary.listFromJson(data);
  }

  Future<void> setToolsetEnabled({
    required String name,
    required bool enabled,
  }) => _owner._requestJson(
    'PUT',
    '/api/tools/toolsets/${Uri.encodeComponent(name)}',
    body: {'enabled': enabled},
  );

  Future<HermesToolsetConfig?> toolsetConfig(String name) async {
    final data = await _owner._requestJson(
      'GET',
      '/api/tools/toolsets/${Uri.encodeComponent(name)}/config',
    );
    return HermesToolsetConfig.fromJson(data);
  }

  Future<HermesToolsetModels?> toolsetModels(String name) async {
    final data = await _owner._requestJson(
      'GET',
      '/api/tools/toolsets/${Uri.encodeComponent(name)}/models',
    );
    return HermesToolsetModels.fromJson(data);
  }

  Future<void> setToolsetModel({
    required String name,
    required String model,
  }) => _owner._requestJson(
    'PUT',
    '/api/tools/toolsets/${Uri.encodeComponent(name)}/model',
    body: {'model': model},
  );

  Future<void> setToolsetProvider({
    required String name,
    required String provider,
  }) => _owner._requestJson(
    'PUT',
    '/api/tools/toolsets/${Uri.encodeComponent(name)}/provider',
    body: {'provider': provider},
  );

  // --- Memory Wiki (dashboard plugin) --------------------------------------
  //
  // The plugin mounts its router at /api/plugins/memory-wiki (manifest `api`),
  // built from local session history: subjects, daily logs, the persistent
  // memory entries, and a read-only provider archive. Shapes measured from
  // memory-wiki 1.1.0's router and core module.

  static const String _wikiBase = '/api/plugins/memory-wiki';

  // --- Filesystem browser ---------------------------------------------------
  //
  // The dashboard's own fs routes. `list` returns only name/path/isDirectory;
  // `read-text` previews at most 512 KB and flags binary/truncated; `write-text`
  // caps at 8 MB, requires the parent to exist, and does NOT detect conflicts —
  // so the editor re-reads before saving.

  Future<HermesFsDefaults?> fsDefaults() async {
    final data = await _owner._requestJson('GET', '/api/fs/default-cwd');
    return HermesFsDefaults.fromJson(data);
  }

  Future<HermesFsListing?> fsList(String path) async {
    final data = await _owner._requestJson(
      'GET',
      '/api/fs/list',
      query: {'path': path},
    );
    return HermesFsListing.fromJson(data);
  }

  Future<HermesFsTextFile?> fsReadText(String path) async {
    final data = await _owner._requestJson(
      'GET',
      '/api/fs/read-text',
      query: {'path': path},
    );
    return HermesFsTextFile.fromJson(data);
  }

  Future<int> fsWriteText({
    required String path,
    required String content,
  }) async {
    final data = _owner._object(
      await _owner._requestJson(
        'POST',
        '/api/fs/write-text',
        body: {'path': path, 'content': content},
      ),
    );
    final size = data['byteSize'];
    return size is num ? size.toInt() : content.length;
  }

  Future<String?> fsGitRoot(String path) async {
    final data = _owner._object(
      await _owner._requestJson(
        'GET',
        '/api/fs/git-root',
        query: {'path': path},
      ),
    );
    return validateHermesBoundedString(data['root'], maxCharacters: 4096);
  }

  Future<HermesMemoryWikiOverview?> memoryWikiOverview({
    int subjectLimit = 50,
    int dayLimit = 30,
  }) async {
    final data = await _owner._requestJson(
      'GET',
      '$_wikiBase/overview',
      query: {'subject_limit': subjectLimit, 'day_limit': dayLimit},
    );
    return HermesMemoryWikiOverview.fromJson(data);
  }

  Future<List<HermesWikiSubject>> memoryWikiSubjects({
    String query = '',
    int limit = 100,
  }) async {
    final data = _owner._object(
      await _owner._requestJson(
        'GET',
        '$_wikiBase/subjects',
        query: {'q': query, 'limit': limit},
      ),
    );
    return HermesWikiSubject.listFromJson(data['subjects']);
  }

  Future<HermesWikiSubject?> memoryWikiSubject(String slug) async {
    final data = _owner._object(
      await _owner._requestJson(
        'GET',
        '$_wikiBase/subjects/${Uri.encodeComponent(slug)}',
      ),
    );
    final subject = data['subject'];
    return subject is Map
        ? HermesWikiSubject.fromJson(Map<String, dynamic>.from(subject))
        : null;
  }

  Future<List<HermesWikiDay>> memoryWikiDays({int limit = 60}) async {
    final data = _owner._object(
      await _owner._requestJson(
        'GET',
        '$_wikiBase/days',
        query: {'limit': limit},
      ),
    );
    return HermesWikiDay.listFromJson(data['daily_logs']);
  }

  Future<HermesWikiDay?> memoryWikiDay(String date) async {
    final data = _owner._object(
      await _owner._requestJson(
        'GET',
        '$_wikiBase/days/${Uri.encodeComponent(date)}',
      ),
    );
    final day = data['daily_log'];
    return day is Map
        ? HermesWikiDay.fromJson(Map<String, dynamic>.from(day))
        : null;
  }

  Future<HermesMemoryArchive?> memoryWikiArchive({
    int limit = 25,
    String? status,
    String? target,
    String query = '',
  }) async {
    final data = await _owner._requestJson(
      'GET',
      '$_wikiBase/archive',
      query: {
        'limit': limit,
        if (status != null && status.isNotEmpty) 'status': status,
        if (target != null && target.isNotEmpty) 'target': target,
        if (query.isNotEmpty) 'q': query,
      },
    );
    return HermesMemoryArchive.fromJson(data);
  }
}
