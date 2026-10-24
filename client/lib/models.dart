import 'dart:convert';
import 'dart:typed_data';

const tagNames = <String>[
  'title',
  'artist',
  'album',
  'album_artist',
  'date',
  'genre',
  'track_number',
  'disc_number',
  'recording_id',
  'release_id',
  'lyrics',
  'synced_lyrics',
];

class TrackDraft {
  TrackDraft.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      filename = json['filename'] as String,
      duration = (json['duration'] as num).toDouble(),
      size = json['size'] as int,
      original = Map<String, String>.from(json['tags'] as Map),
      tags = Map<String, String>.from(json['tags'] as Map),
      originalCover = json['cover_base64'] == null
          ? null
          : base64Decode(json['cover_base64'] as String) {
    cover = originalCover;
  }

  final String id;
  final String filename;
  final double duration;
  final int size;
  String? sourcePath;
  String? sourceDigest;
  bool sourceMissing = false;
  final Map<String, String> original;
  Map<String, String> tags;
  final Uint8List? originalCover;
  Uint8List? cover;
  String coverAction = 'keep';
  String signature = '';
  List<Map<String, dynamic>> candidates = [];
  Map<String, dynamic>? selectedCandidate;
  List<String> notices = [];
  List<String> sources = [];
  int revision = 0;
  bool exported = false;

  String get title => tags['title']!.isEmpty ? filename : tags['title']!;
  String get time =>
      '${duration ~/ 60}:${(duration.toInt() % 60).toString().padLeft(2, '0')}';
  int get changes =>
      tagNames.where((key) => tags[key] != original[key]).length +
      (coverAction == 'keep' ? 0 : 1);
  String get exportName {
    final dot = filename.lastIndexOf('.');
    return '${filename.substring(0, dot)} - tagged${filename.substring(dot)}';
  }

  void reset() {
    tags = Map.of(original);
    cover = originalCover;
    coverAction = 'keep';
    notices = [];
    sources = [];
    selectedCandidate = null;
    exported = false;
    revision++;
  }

  Map<String, dynamic> exportBody() => {
    'tags': tags,
    'cover_action': coverAction,
    if (coverAction == 'replace' && cover != null)
      'cover_base64': base64Encode(cover!),
  };

  /// No backend token or transient server identifier is serialized here.
  Map<String, dynamic> sessionJson() => {
    'id': id,
    'filename': filename,
    'duration': duration,
    'size': size,
    'original': Map<String, String>.of(original),
    'tags': Map<String, String>.of(tags),
    'source_digest': sourceDigest,
    'cover_action': coverAction,
    'signature': signature,
    'candidates': jsonDecode(jsonEncode(candidates)),
    'selected_candidate': selectedCandidate == null
        ? null
        : jsonDecode(jsonEncode(selectedCandidate)),
    'notices': List<String>.of(notices),
    'sources': List<String>.of(sources),
    'exported': exported,
  };

  static TrackDraft restore(
    Map<String, dynamic> data, {
    Uint8List? originalImage,
    Uint8List? editedImage,
  }) {
    final draft = TrackDraft.fromJson({
      'id': data['id'],
      'filename': data['filename'],
      'duration': data['duration'],
      'size': data['size'],
      'tags': data['original'],
      'cover_base64': originalImage == null
          ? null
          : base64Encode(originalImage),
    });
    if (!draft.duration.isFinite ||
        draft.duration < 0 ||
        draft.size <= 0 ||
        draft.size > 120 * 1024 * 1024)
      throw const FormatException('Invalid saved audio properties.');
    draft.tags = Map<String, String>.from(data['tags'] as Map);
    for (final key in tagNames) {
      if (!draft.tags.containsKey(key) || !draft.original.containsKey(key))
        throw const FormatException('Incomplete saved tag draft.');
    }
    draft.sourceDigest = data['source_digest'] as String?;
    if (draft.sourceDigest == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(draft.sourceDigest!))
      throw const FormatException('Invalid saved audio checksum.');
    draft.coverAction = data['cover_action'] as String? ?? 'keep';
    if (!['keep', 'replace', 'remove'].contains(draft.coverAction))
      throw const FormatException('Invalid saved artwork action.');
    draft.cover = draft.coverAction == 'keep'
        ? draft.originalCover
        : draft.coverAction == 'replace'
        ? editedImage
        : null;
    if (draft.coverAction == 'replace' && editedImage == null)
      throw const FormatException('Saved replacement cover is missing.');
    draft.signature = data['signature'] as String? ?? '';
    draft.candidates = (data['candidates'] as List? ?? [])
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    for (final candidate in draft.candidates)
      candidate['availability_loading'] = false;
    final chosen = data['selected_candidate'];
    if (chosen is Map) {
      draft.selectedCandidate = draft.candidates
          .cast<Map<String, dynamic>?>()
          .firstWhere(
            (c) =>
                c?['recording_id'] == chosen['recording_id'] &&
                c?['release_id'] == chosen['release_id'],
            orElse: () => Map<String, dynamic>.from(chosen),
          );
    }
    draft.notices = (data['notices'] as List? ?? []).cast<String>();
    draft.sources = (data['sources'] as List? ?? []).cast<String>();
    draft.exported = data['exported'] == true;
    return draft;
  }
}
