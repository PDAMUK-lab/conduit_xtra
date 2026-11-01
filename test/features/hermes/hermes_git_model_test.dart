import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/models/hermes_git.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a working-tree status', () {
    final status = HermesGitStatus.fromJson({
      'branch': 'hermes-first',
      'defaultBranch': 'main',
      'detached': false,
      'ahead': 2,
      'behind': 1,
      'staged': 1,
      'unstaged': 2,
      'untracked': 1,
      'conflicted': 0,
      'changed': 3,
      'added': 40,
      'removed': 2,
      'files': [
        {'path': 'lib/a.dart', 'staged': true, 'unstaged': false},
        {'path': 'lib/b.dart', 'staged': false, 'unstaged': true},
        {'path': 'new.txt', 'untracked': true},
        {'path': 'merge.txt', 'conflicted': true},
      ],
    });
    check(status).isNotNull();
    check(status!.branch).equals('hermes-first');
    check(status.ahead).equals(2);
    check(status.changed).equals(3);
    check(status.clean).isFalse();
    check(status.files.map((f) => f.marker)).deepEquals(['A', 'M', '?', 'U']);
  });

  test('a clean tree has no files', () {
    final status = HermesGitStatus.fromJson({
      'branch': 'main',
      'files': <Map<String, dynamic>>[],
    });
    check(status!.clean).isTrue();
  });

  test('a non-repository body is null', () {
    check(HermesGitStatus.fromJson(null)).isNull();
    check(HermesGitStatus.fromJson('nope')).isNull();
  });

  test('parses a diff and rejects a missing one', () {
    final diff = HermesGitDiff.fromJson({'diff': '@@ -1 +1 @@\n-a\n+b'});
    check(diff).isNotNull();
    check(diff!.diff).contains('-a');
    check(HermesGitDiff.fromJson(<String, dynamic>{})).isNull();
  });
}
