import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/models/hermes_yaml_diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identical documents have no changes', () {
    final diff = diffYamlDocuments('a: 1\nb: 2\n', 'a: 1\nb: 2');
    check(diff.isEmpty).isTrue();
    check(diff.added).equals(0);
    check(diff.removed).equals(0);
  });

  test('an added line counts once and shows a context line', () {
    final diff = diffYamlDocuments('a: 1\nb: 2\n', 'a: 1\nb: 2\nc: 3\n');
    check(diff.added).equals(1);
    check(diff.removed).equals(0);
    check(diff.isEmpty).isFalse();
    final added = diff.lines.where((l) => l.kind == HermesDiffKind.added);
    check(added.map((l) => l.text)).deepEquals(['c: 3']);
  });

  test('a removed line is reported separately from an addition', () {
    final diff = diffYamlDocuments('a: 1\nb: 2\n', 'a: 1\n');
    check(diff.removed).equals(1);
    check(diff.added).equals(0);
    check(diff.lines.where((l) => l.kind == HermesDiffKind.removed).map((l) => l.text))
        .deepEquals(['b: 2']);
  });

  test('a changed value reads as one removal and one addition', () {
    final diff = diffYamlDocuments('model: a\n', 'model: b\n');
    check(diff.added).equals(1);
    check(diff.removed).equals(1);
  });

  test('long unchanged stretches collapse into a gap marker', () {
    final before = List.generate(40, (i) => 'k$i: $i').join('\n');
    final after = '$before\nnew: 1';
    final diff = diffYamlDocuments(before, after, context: 1);
    check(diff.lines.any((l) => l.isGap)).isTrue();
    check(diff.lines.where((l) => l.kind == HermesDiffKind.context).length)
        .isLessThan(10);
  });

  test('huge documents fall back to a coarse comparison', () {
    final before = List.generate(900, (i) => 'k$i: $i').join('\n');
    final diff = diffYamlDocuments(before, before);
    check(diff.truncated).isTrue();
    check(diff.isEmpty).isTrue();
  });

  test('canonical form ignores comments, order and quoting', () {
    final a = canonicalYaml('a: 1\nb: two\n# note\n');
    final b = canonicalYaml("b: 'two'\na: 1\n");
    check(a).isNotNull();
    check(a).equals(b);
  });

  test('canonical form detects a real value change', () {
    check(canonicalYaml('a: 1\n') == canonicalYaml('a: 2\n')).isFalse();
  });

  test('canonical form rejects non-mappings and bad YAML', () {
    check(canonicalYaml('- a\n- b\n')).isNull();
    check(canonicalYaml('a: [1,\n')).isNull();
    check(canonicalYaml('')).isNull();
  });

  test('CRLF and trailing newlines do not register as changes', () {
    final diff = diffYamlDocuments('a: 1\r\nb: 2\r\n', 'a: 1\nb: 2\n\n');
    check(diff.isEmpty).isTrue();
  });
}
