import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:resonance/api.dart';
import 'package:resonance/models.dart';
import 'package:resonance/overwrite_song.dart';

void main() {
  late Directory root;
  late File target;
  const original = [1, 2, 3, 4];
  late String expected;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('resonance-overwrite-test-');
    target = File('${root.path}/song.mp3');
    await target.writeAsBytes(original);
    expected = sha256.convert(original).toString();
  });
  tearDown(() async => root.delete(recursive: true));

  test('replaces bytes at the same path and supports repeated saves', () async {
    final first = await overwriteSong(
      target,
      Uint8List.fromList([5, 6]),
      expected,
    );
    expect(await target.readAsBytes(), [5, 6]);
    final second = await overwriteSong(
      target,
      Uint8List.fromList([7, 8, 9]),
      first,
    );
    expect(second, sha256.convert([7, 8, 9]).toString());
    expect(await target.readAsBytes(), [7, 8, 9]);
    expect(await root.list().length, 1);
  });
  test('rejects a changed or unrelated song before writing', () async {
    await target.writeAsBytes([9]);
    await expectLater(
      overwriteSong(target, Uint8List.fromList([5]), expected),
      throwsA(isA<ApiException>()),
    );
    expect(await target.readAsBytes(), [9]);
    expect(await root.list().length, 1);
  });
  test('partial commit failure restores the original', () async {
    await expectLater(
      overwriteSong(
        target,
        Uint8List.fromList([5]),
        expected,
        commit: (staged, destination) async {
          await destination.writeAsBytes([0]);
          throw const FileSystemException('Simulated failed replacement');
        },
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await target.readAsBytes(), original);
    expect(await root.list().length, 1);
  });
  test('failed restoration keeps a readable recovery backup', () async {
    await expectLater(
      overwriteSong(
        target,
        Uint8List.fromList([5]),
        expected,
        commit: (staged, destination) async {
          await destination.delete();
          await Directory(destination.path).create();
          throw const FileSystemException('Destination unavailable');
        },
      ),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'recovery',
          contains('original-backup'),
        ),
      ),
    );
    final backups = await root
        .list(recursive: true)
        .where(
          (entry) => entry is File && entry.path.endsWith('original-backup'),
        )
        .toList();
    expect(backups, hasLength(1));
    expect(await File(backups.single.path).readAsBytes(), original);
  });
  test(
    'session restores overwrite checksum while Reset retains the import baseline',
    () {
      final draft = TrackDraft.fromJson({
        'id': 'track',
        'filename': 'song.mp3',
        'duration': 1,
        'size': 4,
        'tags': {for (final key in tagNames) key: ''},
        'cover_base64': null,
      });
      draft.sourceDigest = expected;
      draft.overwriteDigest = sha256.convert([5, 6]).toString();
      final restored = TrackDraft.restore(draft.sessionJson());
      expect(restored.overwriteDigest, draft.overwriteDigest);
      restored.reset();
      expect(restored.overwriteDigest, draft.overwriteDigest);
      expect(restored.sourceDigest, expected);
      final old = draft.sessionJson()..remove('overwrite_digest');
      expect(TrackDraft.restore(old).overwriteDigest, isNull);
    },
  );

  test('empty output leaves the original intact', () async {
    await expectLater(
      overwriteSong(target, Uint8List(0), expected),
      throwsA(isA<ApiException>()),
    );
    expect(await target.readAsBytes(), original);
  });
}
