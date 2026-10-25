import 'dart:async';

enum RecognitionStatus {
  idle,
  queued,
  running,
  matched,
  noMatch,
  failed,
  canceled,
  interrupted,
}

class RecognitionRecord {
  RecognitionStatus status = RecognitionStatus.idle;
  String error = '';
  bool selected = false;
  int attempts = 0;
  bool get retryable => {
    RecognitionStatus.failed,
    RecognitionStatus.canceled,
    RecognitionStatus.interrupted,
  }.contains(status);
  Map<String, dynamic> toJson() => {
    'status': status.name,
    'error': error,
    'selected': selected,
    'attempts': attempts,
  };
  static RecognitionRecord restore(Object? value) {
    final r = RecognitionRecord();
    if (value is! Map) return r;
    r.status = RecognitionStatus.values.firstWhere(
      (v) => v.name == value['status'],
      orElse: () => RecognitionStatus.idle,
    );
    r.selected = value['selected'] == true;
    r.attempts = value['attempts'] is int
        ? (value['attempts'] as int).clamp(0, 1000000).toInt()
        : 0;
    r.error = value['error'] is String ? value['error'] as String : '';
    if ({
      RecognitionStatus.running,
      RecognitionStatus.queued,
    }.contains(r.status)) {
      r.status = RecognitionStatus.interrupted;
      r.error =
          'Recognition was interrupted. Retry unfinished songs to continue.';
    }
    return r;
  }
}

class RecognitionJob {
  const RecognitionJob({
    required this.id,
    required this.label,
    required this.record,
    required this.identify,
  });
  final String id, label;
  final RecognitionRecord record;
  final Future<bool> Function() identify;
}

/// Pause and cancel take effect after the current native/HTTP operation settles.
class RecognitionQueue {
  RecognitionQueue({required this.changed});
  final void Function() changed;
  List<RecognitionJob> _jobs = [];
  RecognitionJob? current;
  bool active = false,
      paused = false,
      pauseRequested = false,
      cancelRequested = false,
      _disposed = false;
  Completer<void>? _pause;
  int get total => _jobs.length;
  int count(RecognitionStatus status) =>
      _jobs.where((j) => j.record.status == status).length;
  int get settled =>
      total -
      count(RecognitionStatus.queued) -
      count(RecognitionStatus.running);
  double get progress => total == 0 ? 0 : settled / total;
  void _emit() {
    if (!_disposed) changed();
  }

  Future<void> start(Iterable<RecognitionJob> jobs) async {
    if (_disposed) throw StateError('Recognition queue is closed.');
    if (active) throw StateError('A recognition batch is already running.');
    final ids = <String>{};
    final plan = jobs.where((job) => ids.add(job.id)).toList(growable: false);
    if (plan.length > 50)
      throw ArgumentError('A batch can contain at most 50 songs.');
    _jobs = plan;
    active = true;
    paused = pauseRequested = cancelRequested = false;
    for (final j in _jobs) {
      j.record.status = RecognitionStatus.queued;
      j.record.error = '';
    }
    _emit();
    try {
      for (final j in _jobs) {
        if (_disposed || cancelRequested) break;
        if (j.record.status != RecognitionStatus.queued) continue;
        if (pauseRequested) {
          paused = true;
          _pause = Completer<void>();
          _emit();
          await _pause!.future;
          _pause = null;
          paused = false;
          if (_disposed || cancelRequested) break;
        }
        if (j.record.status != RecognitionStatus.queued) continue;
        current = j;
        j.record.status = RecognitionStatus.running;
        j.record.attempts++;
        _emit();
        if (_disposed) break;
        try {
          final matched = await j.identify();
          if (!_disposed) {
            j.record.status = matched
                ? RecognitionStatus.matched
                : RecognitionStatus.noMatch;
            j.record.error = '';
          }
        } catch (e) {
          if (!_disposed) {
            j.record.status = RecognitionStatus.failed;
            j.record.error = e.toString();
          }
        }
        current = null;
        _emit();
      }
    } finally {
      active = paused = pauseRequested = false;
      current = null;
      _emit();
    }
  }

  void pause() {
    if (!active || cancelRequested || pauseRequested) return;
    pauseRequested = true;
    _emit();
  }

  void resume() {
    if (!active || cancelRequested) return;
    pauseRequested = false;
    if (_pause != null && !_pause!.isCompleted) _pause!.complete();
    _emit();
  }

  void skip(String id) {
    if (!active) return;
    for (final j in _jobs) {
      if (j.id == id && j.record.status == RecognitionStatus.queued) {
        j.record.status = RecognitionStatus.canceled;
        j.record.error = 'Skipped in the recognition queue.';
        _emit();
        return;
      }
    }
  }

  void cancel() {
    if (!active || cancelRequested) return;
    cancelRequested = true;
    for (final j in _jobs) {
      if (j.record.status == RecognitionStatus.queued) {
        j.record.status = RecognitionStatus.canceled;
        j.record.error = 'Canceled before recognition started.';
      }
    }
    if (_pause != null && !_pause!.isCompleted) _pause!.complete();
    _emit();
  }

  void reset() {
    if (active) throw StateError('Cannot reset an active recognition batch.');
    _jobs = [];
    cancelRequested = false;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final j in _jobs) {
      if ({
        RecognitionStatus.queued,
        RecognitionStatus.running,
      }.contains(j.record.status)) {
        j.record.status = RecognitionStatus.interrupted;
        j.record.error =
            'Recognition was interrupted. Retry unfinished songs to continue.';
      }
    }
    if (_pause != null && !_pause!.isCompleted) _pause!.complete();
  }
}
