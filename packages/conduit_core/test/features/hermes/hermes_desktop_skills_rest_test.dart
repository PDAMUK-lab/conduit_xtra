import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/models/hermes_config.dart';
import 'package:conduit_core/features/hermes/models/hermes_skill.dart';
import 'package:conduit_core/features/hermes/services/hermes_dashboard_bridge.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:test/test.dart';

final class _RecordingBridge implements HermesDashboardBridge {
  _RecordingBridge(this.reply);

  final ({int status, String body}) Function(String method, Uri url) reply;
  final List<({String method, Uri url, String? body})> requests = [];

  @override
  Future<({int status, String body})> request(
    String method,
    Uri url, {
    String? body,
  }) async {
    requests.add((method: method, url: url, body: body));
    return reply(method, url);
  }

  @override
  Future<void> reload() async {}

  @override
  Future<void> close() async {}
}

HermesDesktopApiService _service(_RecordingBridge bridge) =>
    HermesDesktopApiService(
      config: const HermesConfig(
        enabled: true,
        baseUrl: 'https://hermes.example',
        mode: HermesBackendMode.desktopGateway,
        desktopAuthKind: HermesDesktopAuthKind.dashboardCookie,
        desktopProfile: 'work',
      ),
      dashboardBridgeFactory: ({required root, required accessHeaders}) =>
          bridge,
    );

void main() {
  test('lists skills from the dashboard contract', () async {
    final bridge = _RecordingBridge(
      (method, url) => (
        status: 200,
        body:
            '[{"name":"audit","description":"Review.","category":null,'
            '"enabled":true,"usage":58,"provenance":"agent"},'
            '{"name":"code-wiki","description":"Docs.","category":"software-development",'
            '"enabled":false,"usage":3,"provenance":"agent"}]',
      ),
    );
    final service = _service(bridge);
    addTearDown(service.close);

    final skills = await service.dashboardSkills();
    check(skills.map((skill) => skill.name)).deepEquals(['audit', 'code-wiki']);
    check(skills.last.enabled).isFalse();
    check(skills.last.category).equals('software-development');
    check(bridge.requests.single.method).equals('GET');
    check(bridge.requests.single.url.path).equals('/api/skills');
    // Profile scoping rides every dashboard skills call.
    check(bridge.requests.single.url.queryParameters['profile']).equals('work');
  });

  test('reads one skill and sends its name as a query parameter', () async {
    final bridge = _RecordingBridge(
      (method, url) => (
        status: 200,
        body: '{"name":"audit","content":"---\\nname: audit\\n---\\n# Audit"}',
      ),
    );
    final service = _service(bridge);
    addTearDown(service.close);

    final content = await service.skillContent('audit');
    check(content).equals('---\nname: audit\n---\n# Audit');
    final request = bridge.requests.single;
    check(request.url.path).equals('/api/skills/content');
    check(request.url.queryParameters['name']).equals('audit');
    check(request.url.queryParameters['profile']).equals('work');
  });

  test('saves content and toggles a skill with the dashboard bodies', () async {
    final bridge = _RecordingBridge(
      (method, url) => (status: 200, body: '{"success":true}'),
    );
    final service = _service(bridge);
    addTearDown(service.close);

    await service.updateSkillContent(name: 'audit', content: '# New');
    await service.setSkillEnabled(name: 'audit', enabled: false);

    check(bridge.requests[0].method).equals('PUT');
    check(bridge.requests[0].url.path).equals('/api/skills/content');
    expect(bridge.requests[0].body, contains('"name":"audit"'));
    expect(bridge.requests[0].body, contains('"content":"# New"'));

    check(bridge.requests[1].method).equals('PUT');
    check(bridge.requests[1].url.path).equals('/api/skills/toggle');
    expect(bridge.requests[1].body, contains('"enabled":false'));
  });

  test('creates a skill and omits an empty category', () async {
    final bridge = _RecordingBridge(
      (method, url) => (status: 200, body: '{"success":true}'),
    );
    final service = _service(bridge);
    addTearDown(service.close);

    await service.createSkill(name: 'new-skill', content: '# New');
    check(bridge.requests.single.method).equals('POST');
    check(bridge.requests.single.url.path).equals('/api/skills');
    expect(bridge.requests.single.body, isNot(contains('category')));

    await service.createSkill(
      name: 'new-skill',
      content: '# New',
      category: 'devops',
    );
    expect(bridge.requests.last.body, contains('"category":"devops"'));
  });

  test('reads memory status and switches the provider', () async {
    final bridge = _RecordingBridge((method, url) {
      if (method == 'GET') {
        return (
          status: 200,
          body:
              '{"active":"hermesmemory","providers":[{"name":"hermesmemory",'
              '"status":"ready","available":true,"configured":true}],'
              '"builtin_files":{"memory":120,"user":80}}',
        );
      }
      return (status: 200, body: '{"ok":true,"active":"builtin"}');
    });
    final service = _service(bridge);
    addTearDown(service.close);

    final status = await service.memoryStatus();
    check(status['active']).equals('hermesmemory');
    final providers = status['providers'] as List;
    check(providers).length.equals(1);
    check(bridge.requests.single.url.path).equals('/api/memory');

    await service.setMemoryProvider('builtin');
    check(bridge.requests.last.method).equals('PUT');
    check(bridge.requests.last.url.path).equals('/api/memory/provider');
    expect(bridge.requests.last.body, contains('"provider":"builtin"'));
  });

  test('a skill parser sees a bare array, not a wrapped object', () async {
    final skills = HermesSkill.listFromJson([]);
    check(skills).isEmpty();
  });
}
