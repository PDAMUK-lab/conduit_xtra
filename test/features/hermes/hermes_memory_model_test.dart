import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/models/hermes_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the memory status the measured dashboard returns', () {
    final status = HermesMemoryStatus.fromJson({
      'active': 'hermesmemory',
      'providers': [
        {
          'name': 'hermesmemory',
          'description': 'Tiered memory for Hermes.',
          'available': true,
          'configured': true,
          'status': 'ready',
          'setup': <String, dynamic>{},
        },
        {
          'name': 'byterover',
          'description': 'ByteRover knowledge tree.',
          'available': false,
          'configured': true,
          'status': 'unavailable',
          'setup': <String, dynamic>{},
        },
      ],
      'builtin_files': {'memory': 120, 'user': 80},
    });

    check(status).isNotNull();
    check(status!.active).equals('hermesmemory');
    check(status.providers).length.equals(2);
    check(status.providers.first.ready).isTrue();
    check(status.providers.last.ready).isFalse();
    check(status.memoryFileBytes).equals(120);
    check(status.userFileBytes).equals(80);
    check(status.hasBuiltinFiles).isTrue();
  });

  test('survives a provider without a status or a name', () {
    final status = HermesMemoryStatus.fromJson({
      'active': 'builtin',
      'providers': [
        {'description': 'no name'},
        {'name': 'plain'},
      ],
      'builtin_files': {'memory': 0, 'user': 0},
    });
    check(status!.providers.map((p) => p.name)).deepEquals(['plain']);
    check(status.providers.single.ready).isFalse();
    check(status.hasBuiltinFiles).isFalse();
  });

  test('a non-map body is null rather than a throw', () {
    check(HermesMemoryStatus.fromJson(null)).isNull();
    check(HermesMemoryStatus.fromJson('nope')).isNull();
  });
}
