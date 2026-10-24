import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:resonance/models.dart';
import 'package:resonance/session_store.dart';

void main() {
  late Directory temporary;
  late SessionStore store;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('resonance-session-');
    store = await SessionStore.open('backend-a', supportDirectory: temporary);
  });
  tearDown(() async {
    await store.close();
    await temporary.delete(recursive: true);
  });

  Future<TrackDraft> importDraft({List<int> bytes = const [1, 2, 3, 4]}) async {
    final source = File('${temporary.path}/source.mp3');
    await source.writeAsBytes(bytes);
    final staged = await store.stageAudio(source.path, 'song.mp3');
    return TrackDraft.fromJson({
        'id': staged.id,
        'filename': 'song.mp3',
        'duration': 180.0,
        'size': bytes.length,
        'tags': {
          for (final key in tagNames) key: key == 'title' ? 'Original' : '',
        },
        'cover_base64': base64Encode([1, 2, 3]),
      })
      ..sourcePath = staged.path
      ..sourceDigest = staged.digest;
  }

  test(
    'reopens full draft with artwork, candidates and selected tab',
    () async {
      final draft = await importDraft();
      draft.tags['title'] = 'Edited';
      draft.tags['lyrics'] = 'A saved lyric';
      draft.tags['synced_lyrics'] = '[00:01.00]A saved lyric';
      draft.coverAction = 'replace';
      draft.cover = Uint8List.fromList([4, 5, 6]);
      draft.candidates = [
        {
          'recording_id': 'r',
          'release_id': 'a',
          'title': 'Candidate',
          'availability_loading': true,
        },
      ];
      draft.selectedCandidate = draft.candidates.first;
      await store.save([draft], selectedId: draft.id, tab: 2);
      await store.close();
      store = await SessionStore.open('backend-a', supportDirectory: temporary);
      final session = await store.load();
      final restored = session.tracks.single;
      expect(session.selectedId, draft.id);
      expect(session.tab, 2);
      expect(restored.original['title'], 'Original');
      expect(restored.tags, draft.tags);
      expect(restored.cover, [4, 5, 6]);
      expect(restored.originalCover, [1, 2, 3]);
      expect(restored.selectedCandidate, same(restored.candidates.single));
      expect(restored.candidates.single['availability_loading'], false);
      expect(restored.sourceMissing, false);
      expect(restored.sourceDigest, draft.sourceDigest);
    },
  );

  test('queued snapshots capture state before asynchronous writes', () async {
    final draft = await importDraft();
    draft.coverAction = 'replace';
    draft.cover = Uint8List.fromList([7, 8, 9]);
    final pending = store.save([draft]);
    draft.tags['title'] = 'Later edit';
    draft.cover![0] = 0;
    await pending;
    final restored = (await store.load()).tracks.single;
    expect(restored.tags['title'], 'Original');
    expect(restored.cover, [7, 8, 9]);
  });

  test(
    'corrupt primary recovers backup and does not replace it with corruption',
    () async {
      final draft = await importDraft();
      await store.save([draft]);
      draft.tags['title'] = 'Second revision';
      await store.save([draft]);
      final primary = File('${store.root.path}/session.json');
      await primary.writeAsString('{broken');
      final restored = await store.load();
      expect(restored.tracks.single.tags['title'], 'Original');
      expect(restored.messages.first, contains('Recovered'));
      restored.tracks.single.tags['title'] = 'Recovered and edited';
      await store.save(restored.tracks);
      await primary.writeAsString('{broken again');
      expect((await store.load()).tracks.single.tags['title'], 'Original');
    },
  );

  test('unrecoverable manifests preserve working audio', () async {
    final draft = await importDraft();
    await store.save([draft]);
    await File('${store.root.path}/session.json').writeAsString('invalid');
    await expectLater(store.load(), throwsFormatException);
    expect(await File(draft.sourcePath!).exists(), true);
  });

  test(
    'missing audio retains text and can only relink identical original',
    () async {
      final draft = await importDraft();
      draft.tags['lyrics'] = 'Preserve me';
      await store.save([draft]);
      await File(draft.sourcePath!).delete();
      final restored = (await store.load()).tracks.single;
      expect(restored.sourceMissing, true);
      expect(restored.tags['lyrics'], 'Preserve me');
      final wrong = await File(
        '${temporary.path}/wrong.mp3',
      ).writeAsBytes([4, 3, 2, 1]);
      await expectLater(
        store.relink(restored, wrong.path),
        throwsA(isA<FileSystemException>()),
      );
      await store.relink(restored, '${temporary.path}/source.mp3');
      expect(restored.sourceMissing, false);
      expect(await File(restored.sourcePath!).readAsBytes(), [1, 2, 3, 4]);
    },
  );

  test(
    'missing replacement cover preserves latest text instead of reverting draft',
    () async {
      final draft = await importDraft();
      draft.coverAction = 'replace';
      draft.cover = Uint8List.fromList([4, 5, 6]);
      draft.tags['title'] = 'Latest text';
      await store.save([draft]);
      final manifest =
          jsonDecode(
                await File('${store.root.path}/session.json').readAsString(),
              )
              as Map;
      await File(
        '${store.root.path}/assets/${manifest['tracks'][0]['edited_cover']}',
      ).delete();
      final restored = await store.load();
      expect(restored.tracks.single.tags['title'], 'Latest text');
      expect(restored.tracks.single.coverAction, 'keep');
      expect(restored.messages.join(' '), contains('Replacement artwork'));
    },
  );

  test(
    'cleanup retains in-progress imports and previous snapshot assets',
    () async {
      final first = await importDraft();
      await store.save([first]);
      final pending = await importDraft(bytes: [9, 8, 7]);
      await store.save([]);
      expect(await File(first.sourcePath!).exists(), true);
      expect(await File(pending.sourcePath!).exists(), true);
      await store.save([pending]);
      expect(await File(first.sourcePath!).exists(), false);
      expect(await File(pending.sourcePath!).exists(), true);
    },
  );

  test('backend URLs have isolated workspaces', () async {
    final draft = await importDraft();
    await store.save([draft]);
    final other = await SessionStore.open(
      'backend-b',
      supportDirectory: temporary,
    );
    try {
      expect((await other.load()).tracks, isEmpty);
    } finally {
      await other.close();
    }
  });

  test('close drains pending writes and is idempotent', () async {
    final draft = await importDraft();
    final save = store.save([draft]);
    await store.close();
    await save;
    await store.close();
    store = await SessionStore.open('backend-a', supportDirectory: temporary);
    expect((await store.load()).tracks.single.id, draft.id);
  });
}
