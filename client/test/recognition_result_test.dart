import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonance/api.dart';
import 'package:resonance/models.dart';
import 'package:resonance/recognition_result.dart';
import 'package:resonance/recognition_queue.dart';

TrackDraft draft() => TrackDraft.fromJson({
  'id': 'a',
  'filename': 'song.mp3',
  'duration': 180.0,
  'size': 3,
  'tags': {for (final key in tagNames) key: ''},
});
void main() {
  test(
    'draft persistence restores selection and interrupted recognition without changing tags',
    () {
      final t = draft();
      t.sourceDigest = List.filled(64, '0').join();
      t.tags['lyrics'] = 'Saved lyric';
      t.recognition
        ..status = RecognitionStatus.running
        ..selected = true
        ..attempts = 2;
      final restored = TrackDraft.restore(t.sessionJson());
      expect(restored.tags['lyrics'], 'Saved lyric');
      expect(restored.recognition.selected, true);
      expect(restored.recognition.status, RecognitionStatus.interrupted);
      expect(restored.recognition.attempts, 2);
    },
  );
  test(
    'recognition preserves edited tags, lyrics, artwork and chosen matches',
    () {
      final t = draft();
      t.tags['title'] = 'My title';
      t.tags['lyrics'] = 'My lyrics';
      t.coverAction = 'replace';
      t.cover = Uint8List.fromList([1, 2, 3]);
      t.selectedCandidate = {'recording_id': 'previous'};
      final before = jsonDecode(jsonEncode(t.exportBody()));
      expect(
        updateRecognitionCandidates(t, {
          'signature': 'new',
          'lookup_performed': true,
          'candidates': [
            {'recording_id': 'new'},
          ],
          'warnings': [],
        }),
        true,
      );
      expect(t.exportBody(), before);
      expect(t.selectedCandidate!['recording_id'], 'previous');
    },
  );
  test(
    'missing configuration retains previous candidates and the extracted signature',
    () {
      final t = draft()
        ..candidates = [
          {'recording_id': 'old'},
        ];
      expect(
        () => updateRecognitionCandidates(t, {
          'signature': 'sig',
          'lookup_performed': false,
          'candidates': [],
          'warnings': ['Add a key'],
        }),
        throwsA(isA<ApiException>()),
      );
      expect(t.signature, 'sig');
      expect(t.candidates.single['recording_id'], 'old');
    },
  );
  test('empty lookups are no-match and older responses remain supported', () {
    final t = draft();
    expect(
      updateRecognitionCandidates(t, {
        'signature': 'sig',
        'lookup_performed': true,
        'candidates': [],
        'warnings': [],
      }),
      false,
    );
    expect(
      updateRecognitionCandidates(t, {
        'signature': 'sig',
        'candidates': [
          {'recording_id': 'legacy'},
        ],
        'warnings': [],
      }),
      true,
    );
  });
}
