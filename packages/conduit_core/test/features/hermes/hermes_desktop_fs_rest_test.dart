import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/models/hermes_config.dart';
import 'package:conduit_core/features/hermes/services/hermes_dashboard_bridge.dart';
import 'package:conduit_core/features/hermes/services/hermes_desktop_api_service.dart';
import 'package:test/test.dart';

final class _RecordingBridge implements HermesDashboardBridge {
  _RecordingBridge(this.reply);

  final ({int status, String body}) Function(String method, Uri url, String? body) reply;
  final List<({String method, Uri url, String? body})> requests = [];

  @override
  Future<({int status, String body})> request(String method, Uri url, {String? body}) async {
    requests.add((method: method, url: url, body: body));
    return reply(method, url, body);
  }

  @override
  Future<void> reload() async {}

  @override
  Future<void> close() async {}
}

HermesDesktopApiService _service(_RecordingBridge bridge) => HermesDesktopApiService(
  config: const HermesConfig(
    enabled: true,
    baseUrl: 'https://hermes.example',
    mode: HermesBackendMode.desktopGateway,
    desktopAuthKind: HermesDesktopAuthKind.dashboardCookie,
    desktopProfile: 'work',
  ),
  dashboardBridgeFactory: ({required root, required accessHeaders}) => bridge,
);

void main() {
  test('lists a directory with the profile and the encoded path', () async {
    final bridge = _RecordingBridge((method, url, body) => (
      status: 200,
      body: '{"entries":[{"name":"src","path":"/repo/src","isDirectory":true},'
          '{"name":"README.md","path":"/repo/README.md","isDirectory":false}]}',
    ));
    final service = _service(bridge);
    addTearDown(service.close);

    final listing = await service.fsList('/repo');
    check(listing!.entries.map((e) => e.name)).deepEquals(['src', 'README.md']);
    final request = bridge.requests.single;
    check(request.method).equals('GET');
    check(request.url.path).equals('/api/fs/list');
    check(request.url.queryParameters['path']).equals('/repo');
    check(request.url.queryParameters['profile']).equals('work');
  });

  test('reads text and keeps the server flags', () async {
    final bridge = _RecordingBridge((method, url, body) => (
      status: 200,
      body: '{"path":"/repo/a.dart","text":"void main() {}","byteSize":14,'
          '"language":"dart","mimeType":"text/plain","binary":false,"truncated":true}',
    ));
    final service = _service(bridge);
    addTearDown(service.close);

    final file = await service.fsReadText('/repo/a.dart');
    check(file!.text).equals('void main() {}');
    check(file.language).equals('dart');
    check(file.truncated).isTrue();
    check(bridge.requests.single.url.path).equals('/api/fs/read-text');
  });

  test('writes text as a POST body and returns the server byte size', () async {
    final bridge = _RecordingBridge((method, url, body) => (
      status: 200,
      body: '{"ok":true,"path":"/repo/a.dart","byteSize":18}',
    ));
    final service = _service(bridge);
    addTearDown(service.close);

    final size = await service.fsWriteText(path: '/repo/a.dart', content: 'void main() {}\n');
    check(size).equals(18);
    final request = bridge.requests.single;
    check(request.method).equals('POST');
    check(request.url.path).equals('/api/fs/write-text');
    expect(request.body, contains('"path":"/repo/a.dart"'));
    expect(request.body, contains('"content":"void main() {}'));
  });

  test('reads default cwd and git root', () async {
    final bridge = _RecordingBridge((method, url, body) => (
      status: 200,
      body: url.path.endsWith('default-cwd')
          ? '{"cwd":"/home/hermes/repos","branch":""}'
          : '{"root":"/home/hermes/repos/conduit_xtra"}',
    ));
    final service = _service(bridge);
    addTearDown(service.close);

    final defaults = await service.fsDefaults();
    check(defaults!.cwd).equals('/home/hermes/repos');
    check(defaults.branch).isNull();
    check(await service.fsGitRoot('/home/hermes/repos/conduit_xtra/lib'))
        .equals('/home/hermes/repos/conduit_xtra');
  });
}
