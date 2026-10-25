import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonance/batch_controls.dart';
import 'package:resonance/models.dart';
import 'package:resonance/recognition_queue.dart';

TrackDraft draft(String id) => TrackDraft.fromJson({
  'id': id,
  'filename': '$id.mp3',
  'duration': 180.0,
  'size': 3,
  'tags': {for (final key in tagNames) key: ''},
});
void main() {
  testWidgets(
    'retry scope uses checked songs and recognize all uses the session',
    (tester) async {
      final a = draft('a'), b = draft('b');
      a.recognition
        ..selected = true
        ..status = RecognitionStatus.failed;
      b.recognition.status = RecognitionStatus.failed;
      List<TrackDraft>? requested;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BatchControls(
              tracks: [a, b],
              queue: RecognitionQueue(changed: () {}),
              blocked: false,
              recognize: (t) => requested = t,
              selectAll: (_) {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('Retry failed (1)'));
      expect(requested, [a]);
      await tester.tap(find.text('Recognize all (2)'));
      expect(requested, [a, b]);
    },
  );
  testWidgets('narrow controls expose cancel while a song is active', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final a = draft('a'), b = draft('b');
    final gate = Completer<bool>();
    late StateSetter render;
    final q = RecognitionQueue(changed: () => render(() {}));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (c, update) {
                render = update;
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: BatchControls(
                    tracks: [a, b],
                    queue: q,
                    blocked: q.active,
                    recognize: (_) {},
                    selectAll: (_) {},
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    final work = q.start([
      RecognitionJob(
        id: a.id,
        label: a.filename,
        record: a.recognition,
        identify: () => gate.future,
      ),
      RecognitionJob(
        id: b.id,
        label: b.filename,
        record: b.recognition,
        identify: () async => true,
      ),
    ]);
    await tester.pump();
    await tester.tap(find.text('Cancel remaining'));
    await tester.pump();
    expect(find.text('Stopping…'), findsOneWidget);
    gate.complete(true);
    await work;
    await tester.pump();
    expect(find.text('Retry unfinished (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    q.dispose();
  });
}
