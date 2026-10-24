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
}
