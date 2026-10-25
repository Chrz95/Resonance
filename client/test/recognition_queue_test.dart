import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonance/recognition_queue.dart';

RecognitionJob job(String id, RecognitionRecord r, Future<bool> Function() f) =>
    RecognitionJob(id: id, label: '$id.mp3', record: r, identify: f);

void main() {
  test('serial order, deduplication, matches and no-match outcomes', () async {
    final a = RecognitionRecord(), b = RecognitionRecord();
    final gate = Completer<bool>();
    final started = <String>[];
    final q = RecognitionQueue(changed: () {});
    final work = q.start([
      job('a', a, () {
        started.add('a');
        return gate.future;
      }),
      job('a', a, () async => throw StateError('Duplicate ran')),
      job('b', b, () async {
        started.add('b');
        return false;
      }),
    ]);
    expect(started, ['a']);
    expect(b.status, RecognitionStatus.queued);
    gate.complete(true);
    await work;
    expect(started, ['a', 'b']);
    expect(a.status, RecognitionStatus.matched);
    expect(b.status, RecognitionStatus.noMatch);
    expect(q.progress, 1);
  });
  test(
    'failures do not stop subsequent songs and a retry clears the error',
    () async {
      final a = RecognitionRecord(), b = RecognitionRecord();
      final q = RecognitionQueue(changed: () {});
      await q.start([
        job('a', a, () async => throw StateError('Offline')),
        job('b', b, () async => true),
      ]);
      expect(a.status, RecognitionStatus.failed);
      expect(b.status, RecognitionStatus.matched);
      await q.start([job('a', a, () async => true)]);
      expect(a.attempts, 2);
      expect(a.error, isEmpty);
      expect(a.status, RecognitionStatus.matched);
    },
  );
  test('cancel lets current work settle and cancels waiting songs', () async {
    final a = RecognitionRecord(), b = RecognitionRecord();
    final gate = Completer<bool>();
    final q = RecognitionQueue(changed: () {});
    final work = q.start([
      job('a', a, () => gate.future),
      job('b', b, () async => throw StateError('Canceled song ran')),
    ]);
    q.cancel();
    expect(a.status, RecognitionStatus.running);
    expect(b.status, RecognitionStatus.canceled);
    gate.complete(true);
    await work;
    expect(a.status, RecognitionStatus.matched);
    expect(q.settled, 2);
  });
  test('pause takes effect at a boundary and resume continues', () async {
    final gate = Completer<bool>();
    final paused = Completer<void>();
    final b = RecognitionRecord();
    late RecognitionQueue q;
    q = RecognitionQueue(
      changed: () {
        if (q.paused && !paused.isCompleted) paused.complete();
      },
    );
    final work = q.start([
      job('a', RecognitionRecord(), () => gate.future),
      job('b', b, () async => true),
    ]);
    q.pause();
    gate.complete(true);
    await paused.future;
    expect(b.status, RecognitionStatus.queued);
    q.resume();
    await work;
    expect(b.status, RecognitionStatus.matched);
  });
  test('cancel wakes a paused queue without running pending songs', () async {
    final gate = Completer<bool>();
    final paused = Completer<void>();
    final b = RecognitionRecord();
    late RecognitionQueue q;
    q = RecognitionQueue(
      changed: () {
        if (q.paused && !paused.isCompleted) paused.complete();
      },
    );
    final work = q.start([
      job('a', RecognitionRecord(), () => gate.future),
      job('b', b, () async => throw StateError('Canceled song ran')),
    ]);
    q.pause();
    gate.complete(true);
    await paused.future;
    q.cancel();
    await work;
    expect(b.status, RecognitionStatus.canceled);
    expect(q.active, false);
  });
  test('skip keeps a pending song retryable without attempting it', () async {
    final gate = Completer<bool>();
    final b = RecognitionRecord();
    final q = RecognitionQueue(changed: () {});
    final work = q.start([
      job('a', RecognitionRecord(), () => gate.future),
      job('b', b, () async => throw StateError('Skipped song ran')),
    ]);
    q.skip('b');
    gate.complete(true);
    await work;
    expect(b.status, RecognitionStatus.canceled);
    expect(b.attempts, 0);
    expect(b.retryable, true);
  });
  test('overlap and oversized plans are rejected', () async {
    final gate = Completer<bool>();
    final q = RecognitionQueue(changed: () {});
    final work = q.start([job('a', RecognitionRecord(), () => gate.future)]);
    await expectLater(q.start([]), throwsStateError);
    gate.complete(true);
    await work;
    await expectLater(
      q.start(
        List.generate(
          51,
          (i) => job('$i', RecognitionRecord(), () async => true),
        ),
      ),
      throwsArgumentError,
    );
    expect(q.total, 1);
  });
  test(
    'disposal preserves interruption and ignores late completions',
    () async {
      final gate = Completer<bool>();
      final a = RecognitionRecord(), b = RecognitionRecord();
      var changed = 0;
      final q = RecognitionQueue(changed: () => changed++);
      final work = q.start([
        job('a', a, () => gate.future),
        job('b', b, () async => true),
      ]);
      q.dispose();
      final count = changed;
      gate.complete(true);
      await work;
      expect(a.status, RecognitionStatus.interrupted);
      expect(b.status, RecognitionStatus.interrupted);
      expect(changed, count);
    },
  );
  test('serialized statuses restore pending work as interrupted', () {
    for (final state in [RecognitionStatus.queued, RecognitionStatus.running]) {
      final r = RecognitionRecord()
        ..status = state
        ..selected = true
        ..attempts = 2;
      final restored = RecognitionRecord.restore(r.toJson());
      expect(restored.status, RecognitionStatus.interrupted);
      expect(restored.selected, true);
      expect(restored.attempts, 2);
    }
    final failed = RecognitionRecord()
      ..status = RecognitionStatus.failed
      ..error = 'Offline';
    expect(RecognitionRecord.restore(failed.toJson()).error, 'Offline');
    expect(RecognitionRecord.restore(null).status, RecognitionStatus.idle);
  });
}
