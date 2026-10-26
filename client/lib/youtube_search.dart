import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import 'api.dart';

class YoutubeSearchVideo {
  const YoutubeSearchVideo({
    required this.id,
    required this.title,
    required this.author,
    this.duration,
    this.live = false,
  });
  final String id;
  final String title;
  final String author;
  final double? duration;
  final bool live;
  Uri get url => Uri.https('www.youtube.com', '/watch', {'v': id});
}

class YoutubeSuggestion {
  const YoutubeSuggestion(this.video, this.score, this.reasons);
  final YoutubeSearchVideo video;

  /// A relative heuristic, never an identification confidence percentage.
  final double score;
  final List<String> reasons;
}

String _words(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

double _coverage(String wanted, String actual) {
  final words = _words(wanted).split(' ').where((s) => s.isNotEmpty).toSet();
  if (words.isEmpty) return 0;
  final found = _words(actual).split(' ').toSet();
  return words.where(found.contains).length / words.length;
}

List<YoutubeSuggestion> rankYoutubeCovers(
  List<YoutubeSearchVideo> videos, {
  required String title,
  required String artist,
  double? duration,
}) {
  final ranked = <({int index, YoutubeSuggestion suggestion})>[];
  final seen = <String>{};
  for (final (index, video) in videos.take(40).indexed) {
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(video.id) ||
        video.title.trim().isEmpty ||
        video.live ||
        !seen.add(video.id))
      continue;
    final reasons = <String>[];
    final titleMatch = _coverage(title, video.title);
    final artistMatch = _coverage(artist, '${video.author} ${video.title}');
    var score = titleMatch * 65 + artistMatch * 25;
    // Prefer the exact song name once artist and presentation labels are removed.
    final ignored = <String>{
      ..._words(artist).split(' '),
      'official',
      'audio',
      'video',
      'lyrics',
      'lyric',
      'hd',
      'hq',
      '4k',
    };
    String core(String value) => _words(value)
        .split(' ')
        .where((word) => word.isNotEmpty && !ignored.contains(word))
        .join(' ');
    final wantedCore = core(title);
    if (wantedCore.isNotEmpty && core(video.title) == wantedCore) score += 10;
    if (titleMatch == 1) reasons.add('Title matches');
    if (artistMatch == 1) reasons.add('Artist matches');
    final text = _words(video.title);
    final channel = _words(video.author);
    if (text.contains('official audio') ||
        text.contains('album cover') ||
        text.contains('cover art') ||
        channel.endsWith(' topic')) {
      score += 8;
      reasons.add('Audio / artwork clue');
    } else if (text.contains('official')) {
      score += 3;
      reasons.add('Official in title');
    }
    // Do not penalize a version explicitly named in the imported song title.
    final requestedWords = _words(title).split(' ').toSet();
    final actualWords = text.split(' ').toSet();
    for (final version in [
      'karaoke',
      'cover',
      'remix',
      'live',
      'reaction',
      'tutorial',
      'nightcore',
    ]) {
      if (actualWords.contains(version) &&
          !requestedWords.contains(version) &&
          !(version == 'cover' &&
              (text.contains('album cover') || text.contains('cover art')))) {
        score -= 15;
      }
    }
    final seconds = video.duration;
    if (duration != null &&
        duration.isFinite &&
        duration > 0 &&
        seconds != null &&
        seconds.isFinite &&
        seconds > 0) {
      final difference = (duration - seconds).abs();
      if (difference <= 12) {
        score += 8;
        reasons.add('Similar duration');
      } else if (difference > duration * .35 && difference > 30) {
        score -= 12;
      }
    }
    ranked.add((
      index: index,
      suggestion: YoutubeSuggestion(video, score, reasons),
    ));
  }
  ranked.sort((a, b) {
    final byScore = b.suggestion.score.compareTo(a.suggestion.score);
    return byScore != 0 ? byScore : a.index.compareTo(b.index);
  });
  return ranked.take(8).map((entry) => entry.suggestion).toList();
}

typedef YoutubeVideoLookup =
    Future<List<YoutubeSearchVideo>> Function(String query);

/// Uses the public search parser from youtube_explode_dart, never media streams.
class YoutubeCoverSearch {
  YoutubeCoverSearch({YoutubeVideoLookup? lookup}) : _lookup = lookup;
  final YoutubeVideoLookup? _lookup;
  yt.YoutubeExplode? _active;
  bool _closed = false;

  void close() {
    _closed = true;
    _active?.close();
    _active = null;
  }

  Future<List<YoutubeSuggestion>> search({
    required String title,
    required String artist,
    String? query,
    double? duration,
  }) async {
    final text = (query ?? '$artist $title').trim();
    if (text.isEmpty)
      throw ApiException('Enter a song title to search YouTube.');
    if (text.length > 300)
      throw ApiException('Keep the search below 300 characters.');
    if (_closed) throw ApiException('YouTube search was cancelled.');
    try {
      final List<YoutubeSearchVideo> videos;
      if (_lookup != null) {
        videos = await _lookup(text).timeout(const Duration(seconds: 30));
      } else {
        final client = yt.YoutubeExplode();
        _active = client;
        try {
          final found = await client.search
              .search(text)
              .timeout(const Duration(seconds: 30));
          videos = found
              .take(40)
              .map(
                (video) => YoutubeSearchVideo(
                  id: video.id.value,
                  title: video.title,
                  author: video.author,
                  duration: video.duration == null
                      ? null
                      : video.duration!.inMilliseconds / 1000,
                  live: video.isLive,
                ),
              )
              .toList();
        } finally {
          if (identical(_active, client)) {
            client.close();
            _active = null;
          }
        }
      }
      if (_closed) throw ApiException('YouTube search was cancelled.');
      return rankYoutubeCovers(
        videos,
        title: title,
        artist: artist,
        duration: duration,
      );
    } on TimeoutException {
      throw ApiException(
        'YouTube search timed out. Retry or paste a video link below.',
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        'YouTube search is unavailable or blocked. Retry, open YouTube, or paste a video link below.',
      );
    }
  }
}
