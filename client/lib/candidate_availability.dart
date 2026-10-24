import 'engine.dart';

/// Runs independently of the editor's busy state and ignores replaced results.
Future<void> checkCandidateAvailability({
  required MusicEngine engine,
  required String trackId,
  required List<Map<String, dynamic>> candidates,
  required bool Function() isActive,
  required void Function() changed,
}) async {
  for (final candidate in candidates) {
    candidate['availability_loading'] = true;
    candidate['has_lyrics'] = null;
    candidate['has_cover'] = null;
  }
  if (!isActive()) return;
  changed();
  for (final candidate in candidates) {
    if (!isActive()) return;
    try {
      final release = candidate['release_id'] as String? ?? '';
      final duration = candidate['duration'];
      final result = await engine.json(
        '/tracks/$trackId/availability',
        method: 'POST',
        body: {
          'title': candidate['title'] ?? '',
          'artist': candidate['artist'] ?? '',
          'album': candidate['album'] ?? '',
          if (release.isNotEmpty) 'release_id': release,
          if (duration is num && duration > 0 && duration <= 86400)
            'duration': duration,
        },
      );
      if (!isActive()) return;
      candidate['has_lyrics'] = result['has_lyrics'];
      candidate['has_cover'] = result['has_cover'];
      candidate['instrumental'] = result['instrumental'] == true;
      candidate['availability_warnings'] = result['warnings'];
    } catch (_) {
      if (!isActive()) return;
      candidate['availability_warnings'] = [
        'Could not check availability. You can still use this match.',
      ];
    }
    candidate['availability_loading'] = false;
    changed();
  }
}
