import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
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
    required this.width,
    required this.height,
  });
  final Uint8List bytes;
  final String title;
  final String author;
  final Uri videoUrl;
  final int width;
  final int height;
}

/// Direct client shared by Windows (including backend mode) and Android.
/// No API key, audio upload or backend change is involved.
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
        statusCode: response.statusCode,
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

  Future<Uint8List> thumbnail(String id) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
      throw ApiException('Invalid video identifier.');
    }
    return _get(
      Uri.https('i.ytimg.com', '/vi/$id/mqdefault.jpg'),
      512 * 1024,
      'image/jpeg',
    ).timeout(const Duration(seconds: 15));
  }

  Future<(int, int)> _dimensions(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          final width = descriptor.width, height = descriptor.height;
          // Missing variants can return a tiny placeholder with HTTP 200.
          if (width < 320 || height < 180 || width * height > 25000000) {
            throw const FormatException('Thumbnail is too small or too large.');
          }
          final codec = await descriptor.instantiateCodec();
          try {
            final frame = await codec.getNextFrame();
            frame.image.dispose();
          } finally {
            codec.dispose();
          }
          return (width, height);
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
    } catch (_) {
      throw const FormatException(
        'Thumbnail is invalid, too small or too large.',
      );
    }
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
      // Keep compact search previews separate from the image used for export.
      // Only locally constructed paths and the validated oEmbed URL are tried.
      for (final uri in <Uri>{
        Uri.https('i.ytimg.com', '/vi/$id/maxresdefault.jpg'),
        Uri.https('i.ytimg.com', '/vi/$id/sddefault.jpg'),
        Uri.https('i.ytimg.com', '/vi/$id/hqdefault.jpg'),
        image,
      }) {
        try {
          final bytes = await _get(uri, 5 * 1024 * 1024, 'image/jpeg');
          final (width, height) = await _dimensions(bytes);
          return YoutubeCover(
            bytes: bytes,
            title: metadata['title'] as String,
            author: metadata['author_name'] is String
                ? metadata['author_name'] as String
                : '',
            videoUrl: video,
            width: width,
            height: height,
          );
        } on TimeoutException {
          rethrow;
        } on ApiException catch (e) {
          // Do not multiply requests when YouTube asks clients to back off.
          if ([429, 503].contains(e.statusCode)) rethrow;
        } on FormatException {
          // Try a smaller real image instead of a placeholder/broken file.
        }
      }
      throw ApiException(
        'No usable YouTube cover was available. Try another video.',
      );
    })().timeout(const Duration(seconds: 40));
  }
}
