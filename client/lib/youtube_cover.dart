import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api.dart';

/// Accept only video links, never fetch a user-supplied host or URL.
String? youtubeVideoId(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
    return null;
  }
  final segments = uri.pathSegments;
  String? id;
  if (uri.host == 'youtu.be' && segments.length == 1) {
    id = segments.single;
  } else if (const {
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
  }.contains(uri.host)) {
    if (uri.path == '/watch') {
      id = uri.queryParameters['v'];
    } else if (segments.length == 2 &&
        const {'shorts', 'embed', 'live'}.contains(segments.first)) {
      id = segments[1];
    }
  }
  return id != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ? id : null;
}

Uri youtubeSearchUri(String query) =>
    Uri.https('www.youtube.com', '/results', {'search_query': query.trim()});

class YoutubeCover {
  const YoutubeCover({
    required this.bytes,
    required this.title,
    required this.author,
    required this.videoUrl,
  });
  final Uint8List bytes;
  final String title;
  final String author;
  final Uri videoUrl;
}

/// Direct client shared by Windows (including backend mode) and Android.
/// No API key, audio upload, backend change or scraping is involved.
class YoutubeCovers {
  YoutubeCovers({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  void close() => _client.close();

  Future<Uint8List> _get(Uri uri, int limit, String mime) async {
    final response = await _client
        .send(http.Request('GET', uri)..followRedirects = false)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200 ||
        !(response.headers['content-type'] ?? '').toLowerCase().startsWith(
          mime,
        )) {
      throw ApiException(
        'YouTube could not supply this thumbnail. Check the video link or try another video.',
      );
    }
    if ((response.contentLength ?? 0) > limit) {
      throw ApiException('YouTube response exceeds the size limit.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > limit) {
        throw ApiException('YouTube response exceeds the size limit.');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  Future<YoutubeCover> load(String input) async {
    final id = youtubeVideoId(input);
    if (id == null) {
      throw ApiException(
        'Paste a valid YouTube video link (watch, youtu.be, Music or Shorts).',
      );
    }
    final video = Uri.https('www.youtube.com', '/watch', {'v': id});
    // One deadline covers headers and body; close() cancels outstanding I/O
    // when the dialog is dismissed or a request fails.
    return (() async {
      final raw = await _get(
        Uri.https('www.youtube.com', '/oembed', {
          'url': video.toString(),
          'format': 'json',
        }),
        64 * 1024,
        'application/json',
      );
      final metadata = jsonDecode(utf8.decode(raw));
      if (metadata is! Map || metadata['title'] is! String) {
        throw ApiException('YouTube returned invalid video information.');
      }
      final image = Uri.tryParse('${metadata['thumbnail_url']}');
      if (image == null ||
          image.scheme != 'https' ||
          image.host != 'i.ytimg.com' ||
          image.userInfo.isNotEmpty ||
          (image.hasPort && image.port != 443) ||
          image.hasQuery ||
          image.hasFragment ||
          !RegExp('^/vi/$id/[A-Za-z0-9_-]+\\.jpg\$').hasMatch(image.path)) {
        throw ApiException(
          'YouTube returned an unsupported thumbnail address.',
        );
      }
      final bytes = await _get(image, 5 * 1024 * 1024, 'image/jpeg');
      return YoutubeCover(
        bytes: bytes,
        title: metadata['title'] as String,
        author: metadata['author_name'] is String
            ? metadata['author_name'] as String
            : '',
        videoUrl: video,
      );
    })().timeout(const Duration(seconds: 40));
  }
}
