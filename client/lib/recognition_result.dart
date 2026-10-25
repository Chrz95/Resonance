import 'api.dart';
import 'models.dart';

/// Leaves edited tags, lyrics, artwork and the previously chosen match intact.
bool updateRecognitionCandidates(
  TrackDraft track,
  Map<String, dynamic> result,
) {
  final signature = result['signature'] as String;
  final warnings = List<String>.from(result['warnings'] as List);
  if (result['lookup_performed'] == false) {
    track.signature = signature;
    track.notices = warnings;
    throw ApiException(
      warnings.isEmpty
          ? 'Configure the free AcoustID application key before matching songs.'
          : warnings.join(' '),
    );
  }
  final candidates = (result['candidates'] as List)
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
  track.signature = signature;
  track.candidates = candidates;
  track.notices = warnings;
  return candidates.isNotEmpty;
}
