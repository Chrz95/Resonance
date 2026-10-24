import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'api.dart';

typedef PublicLookup = Future<dynamic> Function(Uri uri, {bool missingOk});

Uri? safeArtworkUri(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443) ||
      !(uri.host == 'mzstatic.com' || uri.host.endsWith('.mzstatic.com')))
    return null;
  return uri;
}

String sourceNameKey(Object? value) =>
    '$value'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u00c0-\uffff]'), '');

class AlternateSources {
  AlternateSources({required this.lookup, required this.client});
  final PublicLookup lookup;
  final http.Client client;

  Future<Map<String, dynamic>> find(Map candidate) async {
    final title = candidate['title'] as String? ?? '';
    final artist = candidate['artist'] as String? ?? '';
    final album = candidate['album'] as String? ?? '';
    if (title.trim().isEmpty || artist.trim().isEmpty)
      throw ApiException('This candidate needs a title and artist.');
    final options = <Map<String, dynamic>>[];
    final warnings = <String>[];
    if (candidate['kind'] == 'cover') {
      final data = await lookup(
        Uri.https('itunes.apple.com', '/search', {
          'term': '$artist $title',
          'media': 'music',
          'entity': 'song',
          'limit': '20',
        }),
      );
      if (data is! Map || data['results'] is! List)
        throw ApiException('iTunes returned an invalid response.');
      final seen = <int>{};
      for (final raw in data['results'] as List) {
        if (raw is! Map ||
            sourceNameKey(raw['artistName']) != sourceNameKey(artist))
          continue;
        final id = raw['collectionId'];
        final image = safeArtworkUri(raw['artworkUrl100']);
        if (id is! int || id <= 0 || image == null || !seen.add(id)) continue;
        options.add({
          'collection_id': id,
          'source': 'iTunes',
          'title': raw['trackName'] ?? '',
          'artist': raw['artistName'] ?? '',
          'album': raw['collectionName'] ?? '',
          'preview_url': image.toString(),
          'source_url': 'https://music.apple.com/album/$id',
        });
      }
      options.sort(
        (a, b) => (sourceNameKey(a['album']) == sourceNameKey(album) ? 0 : 1)
            .compareTo(
              sourceNameKey(b['album']) == sourceNameKey(album) ? 0 : 1,
            ),
      );
      return {'options': options.take(8).toList(), 'warnings': warnings};
    }
    if (candidate['kind'] != 'lyrics')
      throw ApiException('Unknown alternate source type.');
    try {
      final uri = Uri(
        scheme: 'https',
        host: 'api.lyrics.ovh',
        pathSegments: ['v1', artist, title],
      );
      final data = await lookup(uri, missingOk: true);
      final text = data is Map ? data['lyrics'] : null;
      if (text is String && text.trim().isNotEmpty && text.length <= 200000)
        options.add({
          'source': 'lyrics.ovh',
          'title': title,
          'artist': artist,
          'album': album,
          'lyrics': text,
          'synced_lyrics': '',
          'source_url': uri.toString(),
        });
    } catch (e) {
      warnings.add('$e');
    }
    try {
      final data = await lookup(
        Uri.https('lrclib.net', '/api/search', {
          'track_name': title,
          'artist_name': artist,
        }),
      );
      for (final item in data is List ? data : []) {
        if (item is! Map ||
            sourceNameKey(item['artistName']) != sourceNameKey(artist) ||
            sourceNameKey(item['trackName']) != sourceNameKey(title))
          continue;
        final plain = item['plainLyrics'] ?? '',
            timed = item['syncedLyrics'] ?? '';
        if (plain is! String ||
            timed is! String ||
            (plain.trim().isEmpty && timed.trim().isEmpty) ||
            plain.length > 200000 ||
            timed.length > 200000 ||
            item['id'] is! int)
          continue;
        options.add({
          'source': 'LRCLIB search',
          'title': item['trackName'],
          'artist': item['artistName'],
          'album': item['albumName'] ?? '',
          'lyrics': plain,
          'synced_lyrics': timed,
          'source_url': 'https://lrclib.net/api/get/${item['id']}',
        });
        if (options.length >= 9) break;
      }
    } catch (e) {
      warnings.add('$e');
    }
    return {'options': options, 'warnings': warnings};
  }

  Future<Map<String, dynamic>> cover(int id) async {
    if (id <= 0) throw ApiException('Invalid album identifier.');
    final data = await lookup(
      Uri.https('itunes.apple.com', '/lookup', {'id': '$id'}),
    );
    Uri? image;
    for (final item
        in data is Map && data['results'] is List
            ? data['results'] as List
            : []) {
      if (item is Map && item['collectionId'] == id) {
        image = safeArtworkUri(item['artworkUrl100']);
        if (image != null) break;
      }
    }
    if (image == null)
      throw ApiException('No artwork was supplied for this album.');
    final large = image.toString().replaceFirst('/100x100bb', '/600x600bb');
    for (final url in {large, image.toString()}) {
      final request = http.Request('GET', Uri.parse(url))
        ..followRedirects = false;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 35));
      if (response.statusCode == 404) {
        await response.stream.drain<void>();
        continue;
      }
      if (response.statusCode != 200 ||
          !(response.headers['content-type'] ?? '').toLowerCase().startsWith(
            'image/',
          )) {
        await response.stream.drain<void>();
        throw ApiException('Could not download this artwork.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 35),
      )) {
        bytes.add(chunk);
        if (bytes.length > 5 * 1024 * 1024)
          throw ApiException('Cover exceeds 5 MiB.');
      }
      return {
        'cover_base64': base64Encode(bytes.takeBytes()),
        'source': 'iTunes',
        'source_url': 'https://music.apple.com/album/$id',
      };
    }
    throw ApiException('This artwork is no longer available.');
  }
}
