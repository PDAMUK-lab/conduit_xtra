import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/models/hermes_ops.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an action status and its tail', () {
    final status = HermesActionStatus.fromJson({
      'name': 'doctor',
      'running': false,
      'exit_code': 0,
      'pid': 1234,
      'lines': ['line one', 'line two'],
    });
    check(status).isNotNull();
    check(status!.name).equals('doctor');
    check(status.running).isFalse();
    check(status.exitCode).equals(0);
    check(status.succeeded).isTrue();
    check(status.lines).deepEquals(['line one', 'line two']);
    check(HermesActionStatus.fromJson({'running': true})).isNull();
  });

  test('running actions are not finished', () {
    const running = HermesActionStatus(name: 'backup', running: true);
    check(running.finished).isFalse();
    check(running.succeeded).isFalse();
  });

  test('parses hooks with their consent state', () {
    final hooks = HermesHook.listFromJson({
      'hooks': [
        {
          'event': 'agent_end',
          'command': 'echo done',
          'matcher': null,
          'timeout': 5,
          'allowed': true,
          'executable': true,
        },
        {'event': 'agent_start', 'command': 'notify', 'allowed': false},
        {'event': '', 'command': 'dropped'},
      ],
      'valid_events': ['agent_end', 'agent_start'],
    });
    check(hooks).length.equals(2);
    check(hooks.first.event).equals('agent_end');
    check(hooks.first.allowed).isTrue();
    check(hooks.first.timeout).equals(5);
    check(hooks.last.allowed).isFalse();
  });

  test('parses checkpoints with total size', () {
    final checkpoints = HermesCheckpoints.fromJson({
      'sessions': [
        {'session': 'abc', 'files': 3, 'bytes': 2048},
        {'session': 'def', 'files': 1, 'bytes': 1024},
      ],
      'total_bytes': 3072,
    });
    check(checkpoints).isNotNull();
    check(checkpoints!.sessions).length.equals(2);
    check(checkpoints.totalBytes).equals(3072);
    check(checkpoints.isEmpty).isFalse();
    check(HermesCheckpoints.fromJson({'sessions': [], 'total_bytes': 0})!.isEmpty).isTrue();
  });
}
