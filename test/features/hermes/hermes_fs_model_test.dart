import 'package:checks/checks.dart';
import 'package:conduit_core/features/hermes/models/hermes_fs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a listing: names, paths and types only', () {
    final listing = HermesFsListing.fromJson({
      'entries': [
        {'name': 'src', 'path': '/repo/src', 'isDirectory': true},
        {'name': 'README.md', 'path': '/repo/README.md', 'isDirectory': false},
      ],
    });
    check(listing).isNotNull();
    check(listing!.entries).length.equals(2);
    check(listing.entries.first.name).equals('src');
    check(listing.entries.first.isDirectory).isTrue();
    check(listing.entries.last.isDirectory).isFalse();
    check(listing.error).isNull();
  });

  test('keeps the server error word when a directory cannot be read', () {
    final listing = HermesFsListing.fromJson({
      'entries': <Map<String, dynamic>>[],
      'error': 'permission-denied',
    });
    check(listing!.entries).isEmpty();
    check(listing.error).equals('permission-denied');
  });

  test('drops entries without a name or path', () {
    final listing = HermesFsListing.fromJson({
      'entries': [
        {'name': 'ok', 'path': '/ok'},
        {'name': '', 'path': '/empty-name'},
        {'name': 'no-path'},
        'not-a-map',
      ],
    });
    check(listing!.entries.map((e) => e.name)).deepEquals(['ok']);
  });

  test('parses read-text, including binary and truncated flags', () {
    final text = HermesFsTextFile.fromJson({
      'path': '/repo/a.dart',
      'text': 'void main() {}',
      'byteSize': 14,
      'language': 'dart',
      'mimeType': 'text/plain',
      'binary': false,
      'truncated': false,
    });
    check(text).isNotNull();
    check(text!.text).equals('void main() {}');
    check(text.language).equals('dart');
    check(text.byteSize).equals(14);

    final binary = HermesFsTextFile.fromJson({
      'path': '/repo/blob.bin',
      'text': '',
      'binary': true,
    });
    check(binary!.binary).isTrue();

    final truncated = HermesFsTextFile.fromJson({
      'path': '/repo/big.log',
      'text': 'head',
      'truncated': true,
    });
    check(truncated!.truncated).isTrue();
  });

  test('read-text without a text field is null, not an empty file', () {
    check(HermesFsTextFile.fromJson({'path': '/repo/a'})).isNull();
    check(HermesFsTextFile.fromJson(null)).isNull();
  });

  test('parses default cwd and branch', () {
    final defaults = HermesFsDefaults.fromJson({
      'cwd': '/home/hermes/repos/conduit_xtra',
      'branch': 'hermes-first',
    });
    check(defaults).isNotNull();
    check(defaults!.cwd).equals('/home/hermes/repos/conduit_xtra');
    check(defaults.branch).equals('hermes-first');
    check(HermesFsDefaults.fromJson({'cwd': ''})).isNull();
  });
}
