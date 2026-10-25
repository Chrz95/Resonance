import 'package:flutter/material.dart';
import 'models.dart';
import 'recognition_queue.dart';

class RecognitionStatusChip extends StatelessWidget {
  const RecognitionStatusChip(this.record, {super.key});
  final RecognitionRecord record;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final label = switch (record.status) {
      RecognitionStatus.idle => 'Not checked',
      RecognitionStatus.queued => 'Queued',
      RecognitionStatus.running => 'Recognizing…',
      RecognitionStatus.matched => 'Matches ready',
      RecognitionStatus.noMatch => 'No match',
      RecognitionStatus.failed => 'Failed',
      RecognitionStatus.canceled => 'Canceled',
      RecognitionStatus.interrupted => 'Interrupted',
    };
    final color = switch (record.status) {
      RecognitionStatus.failed => c.error,
      RecognitionStatus.matched => c.secondary,
      RecognitionStatus.running => c.primary,
      _ => c.onSurfaceVariant,
    };
    return Tooltip(
      message: record.error.isEmpty ? label : record.error,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class BatchControls extends StatelessWidget {
  const BatchControls({
    super.key,
    required this.tracks,
    required this.queue,
    required this.blocked,
    required this.recognize,
    required this.selectAll,
  });
  final List<TrackDraft> tracks;
  final RecognitionQueue queue;
  final bool blocked;
  final void Function(List<TrackDraft>) recognize;
  final void Function(bool) selectAll;
  @override
  Widget build(BuildContext context) {
    final selected = tracks.where((t) => t.recognition.selected).toList();
    final scope = selected.isEmpty ? tracks : selected;
    final failed = scope
        .where((t) => t.recognition.status == RecognitionStatus.failed)
        .toList();
    final unfinished = scope.where((t) => t.recognition.retryable).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        if (!queue.active)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: blocked || selected.isEmpty
                    ? null
                    : () => recognize(selected),
                icon: const Icon(Icons.playlist_play),
                label: Text('Recognize selected (${selected.length})'),
              ),
              OutlinedButton(
                onPressed: blocked || tracks.isEmpty
                    ? null
                    : () => recognize(List.of(tracks)),
                child: Text('Recognize all (${tracks.length})'),
              ),
              OutlinedButton.icon(
                onPressed: blocked || failed.isEmpty
                    ? null
                    : () => recognize(failed),
                icon: const Icon(Icons.refresh),
                label: Text('Retry failed (${failed.length})'),
              ),
              if (unfinished.length > failed.length)
                OutlinedButton(
                  onPressed: blocked ? null : () => recognize(unfinished),
                  child: Text('Retry unfinished (${unfinished.length})'),
                ),
              TextButton(
                onPressed: blocked
                    ? null
                    : () => selectAll(selected.length != tracks.length),
                child: Text(
                  selected.length == tracks.length
                      ? 'Clear selection'
                      : 'Select all',
                ),
              ),
            ],
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: queue.cancelRequested
                    ? null
                    : queue.pauseRequested
                    ? queue.resume
                    : queue.pause,
                icon: Icon(
                  queue.pauseRequested ? Icons.play_arrow : Icons.pause,
                ),
                label: Text(
                  queue.pauseRequested ? 'Resume queue' : 'Pause queue',
                ),
              ),
              OutlinedButton.icon(
                onPressed: queue.cancelRequested ? null : queue.cancel,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(
                  queue.cancelRequested ? 'Stopping…' : 'Cancel remaining',
                ),
              ),
            ],
          ),
        const SizedBox(height: 10),
        Text(
          queue.active
              ? queue.cancelRequested
                    ? 'The current song will finish; remaining songs are canceled.'
                    : queue.paused
                    ? 'Queue paused. Resume or cancel the remaining songs.'
                    : queue.pauseRequested
                    ? 'The queue will pause after the current song.'
                    : 'Songs are recognized one at a time. Pause or cancel takes effect after the current song.'
              : 'Check songs for a batch. Retry uses checked songs when any are selected. Review matches before saving each copy.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (queue.total > 0) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: queue.progress,
            semanticsLabel: 'Recognition batch progress',
          ),
          const SizedBox(height: 8),
          Text(
            '${queue.active ? 'Batch' : 'Last batch'}: ${queue.settled}/${queue.total} finished or skipped · ${queue.count(RecognitionStatus.matched)} matched · ${queue.count(RecognitionStatus.noMatch)} no match · ${queue.count(RecognitionStatus.failed)} failed · ${queue.count(RecognitionStatus.canceled)} canceled',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (queue.current != null)
            Text(
              'Current: ${queue.current!.label}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ],
    );
  }
}
