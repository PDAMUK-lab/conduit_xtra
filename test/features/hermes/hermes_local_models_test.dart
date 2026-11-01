import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/models/hermes_local_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the manager state and staged models', () {
    final status = HermesLocalModelStatus.fromJson({
      'enabled': true,
      'tag': 'b11671',
      'update_available': true,
      'runtime_installed': true,
      'runtime_backend': 'cuda',
      'server_running': true,
      'server_base_url': 'http://127.0.0.1:8080',
      'active_model_id': 'ornith9h-q4-best',
      'models': [
        {'id': 'ornith9h-q4-best', 'name': 'Ornith 9H', 'size_bytes': 5800000000},
        {'id': 'other'},
      ],
      'models_dir': '/home/hermes/.hermes/models',
    });
    check(status).isNotNull();
    check(status!.enabled).isTrue();
    check(status.runtimeBackend).equals('cuda');
    check(status.serverRunning).isTrue();
    check(status.modelCount).equals(2);
    check(status.models.first.name).equals('Ornith 9H');
    check(status.models.first.sizeBytes).equals(5800000000);
  });

  test('an externally served router is reported, not claimed', () {
    final status = HermesLocalModelStatus.fromJson({
      'enabled': false,
      'server_running': false,
      'external_server': {
        'base_url': 'http://127.0.0.1:8080/v1',
        'model': 'ornith-1.5-9b-heretic',
      },
    });
    check(status).isNotNull();
    check(status!.servedElsewhere).isTrue();
    check(status.externalServer!.baseUrl).equals('http://127.0.0.1:8080/v1');
    check(status.externalServer!.model).equals('ornith-1.5-9b-heretic');

    final managed = HermesLocalModelStatus.fromJson({
      'server_running': true,
      'external_server': null,
    });
    check(managed!.servedElsewhere).isFalse();
  });

  test('parses fleet peers, up and down', () {
    final status = HermesLocalModelStatus.fromJson({
      'peers': [
        {
          'name': 'desktop',
          'base_url': 'http://20.20.0.40:8080/v1',
          'up': false,
          'model': null,
        },
        {
          'name': 'laptop',
          'base_url': 'http://127.0.0.1:8080/v1',
          'up': true,
          'model': 'ornith-1.5-9b-heretic',
        },
        'junk',
      ],
    });
    check(status).isNotNull();
    check(status!.peers).length.equals(2);
    check(status.peers.first.up).isFalse();
    check(status.peers.first.name).equals('desktop');
    check(status.peers.last.up).isTrue();
    check(status.peers.last.model).equals('ornith-1.5-9b-heretic');
  });

  test('a disabled manager with no models still parses', () {
    final status = HermesLocalModelStatus.fromJson({
      'enabled': false,
      'server_running': false,
      'models': <Map<String, dynamic>>[],
    });
    check(status).isNotNull();
    check(status!.enabled).isFalse();
    check(status.serverRunning).isFalse();
    check(status.modelsDir).equals('');
  });

  test('parses hardware, including a missing used figure', () {
    final withUsed = HermesLocalHardware.fromJson({
      'gpu_name': 'NVIDIA GeForce GTX 1070 with Max-Q Design',
      'vram_total_bytes': 8589934592,
      'vram_usable_bytes': 7000000000,
      'vram_used_bytes': 7689207808,
      'ram_total_bytes': 16646877184,
      'ram_available_bytes': 6029570048,
      'uma': false,
      'vram_label': '8.0 GB',
    });
    check(withUsed).isNotNull();
    check(withUsed!.vramUsedBytes).equals(7689207808);
    check(withUsed.gpuName ?? '').contains('1070');

    final withoutUsed = HermesLocalHardware.fromJson({
      'vram_total_bytes': 1024,
      'vram_used_bytes': null,
    });
    check(withoutUsed!.vramUsedBytes).isNull();
    check(HermesLocalHardware.fromJson(null)).isNull();
  });
}
