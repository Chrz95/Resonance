import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonance/main.dart';
import 'package:resonance/models.dart';

void main() {
  testWidgets('welcome is usable at Android and desktop widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [const Size(360, 800), const Size(1440, 960)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        const ResonanceApp(
          enableDesktopDrop: false,
          autoConnect: false,
          persistSessions: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Choose music files'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  test('draft reset restores tags and cover without discarding candidates', () {
    final tags = {for (final key in tagNames) key: ''};
    tags['title'] = 'Original title';
    final draft = TrackDraft.fromJson({
      'id': 'track-1',
      'filename': 'song.flac',
      'duration': 184.2,
      'size': 100,
      'tags': tags,
      'cover_base64': null,
    });
    draft.tags['title'] = 'New title';
    draft.coverAction = 'remove';
    draft.candidates = [
      {'title': 'A match'},
    ];
    expect(draft.changes, 2);
    expect(draft.time, '3:04');
    expect(draft.exportName, 'song - tagged.flac');
    draft.reset();
    expect(draft.changes, 0);
    expect(draft.tags['title'], 'Original title');
    expect(draft.candidates, hasLength(1));
    expect(draft.exportBody()['cover_action'], 'keep');
  });
}
