import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'provider_date.dart';
import 'alternate_sources.dart';

/// Direct native-app HTTPS clients; no Resonance server is used on Android.
class PublicMusicServices {
  PublicMusicServices({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;
  late final alternateSources = AlternateSources(
    client: _client,
    lookup: (uri, {missingOk = false}) => request(uri, missingOk: missingOk),
  );
  String acoustIdKey = '';
  String userAgent = '';
  final _next = <String, DateTime>{};
  final _cache = <String, (DateTime, dynamic)>{};
  final _coverChecks = <String, (DateTime, bool)>{};
  Future<void> _queue = Future.value();

  void close() => _client.close();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<dynamic> request(
    Uri uri, {
    Map<String, String>? form,
    bool missingOk = false,
  }) => _serial(() async {
    if (uri.host == 'musicbrainz.org' && userAgent.isEmpty) {
      throw ApiException(
        'Open Online settings and add your contact email or project URL for MusicBrainz. Manual editing works offline.',
      );
    }
    final cached = _cache[uri.toString()];
    if (form == null &&
        cached != null &&
        DateTime.now().difference(cached.$1).inMinutes < 15)
      return cached.$2;
    final wait = (_next[uri.host] ?? DateTime.now()).difference(DateTime.now());
    if (wait.inSeconds > 30)
      throw ApiException('${uri.host} requested a cooldown. Try again later.');
    if (!wait.isNegative) await Future<void>.delayed(wait);
    _next[uri.host] = DateTime.now().add(
      Duration(
        milliseconds: uri.host == 'musicbrainz.org'
            ? 1100
            : uri.host == 'itunes.apple.com'
            ? 3100
            : 400,
      ),
    );
    final headers = {
      'User-Agent': userAgent.isEmpty
          ? 'Resonance/1.1 (Android on-device)'
          : userAgent,
    };
    final response =
        await (form == null
                ? _client.get(uri, headers: headers)
                : _client.post(uri, headers: headers, body: form))
            .timeout(const Duration(seconds: 35));
    if (response.statusCode == 404 && missingOk) return null;
    if ([429, 503].contains(response.statusCode)) {
      final value = response.headers['retry-after'] ?? '5';
      final seconds = int.tryParse(value);
      int retry = seconds ?? 60;
      if (seconds == null) {
        try {
          retry = HttpDate.parse(value).difference(DateTime.now()).inSeconds;
        } catch (_) {}
      }
      final delay = Duration(seconds: retry.clamp(1, 86400).toInt());
      _next[uri.host] = DateTime.now().add(delay);
      throw ApiException(
        '${uri.host} is busy. Retry after ${delay.inSeconds} seconds.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        '${uri.host} lookup failed (${response.statusCode}). Check your connection and settings.',
      );
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (form == null) {
      if (_cache.length >= 200) _cache.remove(_cache.keys.first);
      _cache[uri.toString()] = (DateTime.now(), data);
    }
    return data;
  });

  String credit(dynamic items) => (items as List? ?? []).map((dynamic item) {
    final a = item as Map;
    return '${a['name'] ?? (a['artist'] as Map?)?['name'] ?? ''}${a['joinphrase'] ?? ''}';
  }).join();

  List<Map<String, dynamic>> candidates(
    List recordings,
    String source, [
    num? score,
  ]) {
    final result = <Map<String, dynamic>>[];
    for (final raw in recordings) {
      final rec = raw as Map;
      final releases = (rec['releases'] as List? ?? []).isEmpty
          ? [{}]
          : rec['releases'] as List;
      var artist = credit(rec['artist-credit']);
      if (artist.isEmpty)
        artist = (rec['artists'] as List? ?? [])
            .map((a) => a['name'])
            .join(', ');
      for (final rawRelease in releases.take(4)) {
        final release = rawRelease as Map;
        result.add({
          'recording_id': rec['id'],
          'release_id': release['id'] ?? '',
          'title': rec['title'] ?? 'Unknown',
          'artist': artist,
          'album': release['title'] ?? '',
          'date': normalizeProviderDate(release['date']),
          'country': release['country'] ?? '',
          'duration': rec['length'] is num
              ? (rec['length'] as num) / 1000
              : rec['duration'],
          'score': score ?? (num.tryParse('${rec['score'] ?? 0}') ?? 0) / 100,
          'source': source,
        });
      }
    }
    return result.take(24).toList();
  }

  Future<Map<String, dynamic>> identify(
    String fingerprint,
    double duration,
    String hash,
  ) async {
    if (acoustIdKey.isEmpty)
      return {
        'signature': hash,
        'lookup_performed': false,
        'candidates': [],
        'warnings': [
          'Fingerprint extracted on this device. Add a free AcoustID application key in Online settings to match it, or search by name.',
        ],
      };
    final data =
        await request(
              Uri.https('api.acoustid.org', '/v2/lookup'),
              form: {
                'client': acoustIdKey,
                'duration': '${duration.round()}',
                'fingerprint': fingerprint,
                'meta': 'recordings releases',
                'format': 'json',
              },
            )
            as Map;
    if (data['status'] != 'ok')
      throw ApiException(
        'AcoustID rejected the key. Use an application key, not a personal submission key.',
      );
    final matches = (data['results'] as List? ?? []).cast<Map>().toList()
      ..sort((a, b) => (b['score'] as num).compareTo(a['score'] as num));
    final all = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final item in matches) {
      for (final c in candidates(
        item['recordings'] as List? ?? [],
        'fingerprint',
        item['score'] as num,
      )) {
        if (seen.add('${c['recording_id']}/${c['release_id']}')) all.add(c);
      }
    }
    return {
      'signature': hash,
      'lookup_performed': true,
      'candidates': all.take(24).toList(),
      'warnings': all.isEmpty
          ? ['No fingerprint match. Try a title or artist search.']
          : <String>[],
    };
  }

  Future<Map<String, dynamic>> search(String query) async {
    final data =
        await request(
              Uri.https('musicbrainz.org', '/ws/2/recording/', {
                'query': query,
                'fmt': 'json',
                'limit': '8',
              }),
            )
            as Map;
    return {
      'candidates': candidates(data['recordings'] as List? ?? [], 'metadata'),
    };
  }

  Future<Map<String, dynamic>?> lyrics(
    Map<String, String> tags,
    double duration,
  ) async {
    if (tags['title']!.isEmpty || tags['artist']!.isEmpty)
      throw ApiException('Enter a title and artist before fetching lyrics.');
    final data = await request(
      Uri.https('lrclib.net', '/api/get', {
        'track_name': tags['title']!,
        'artist_name': tags['artist']!,
        'album_name': tags['album']!,
        if (duration >= 1 && duration <= 3600)
          'duration': '${duration.round()}',
      }),
      missingOk: true,
    );
    if (data == null) return null;
    final item = data as Map;
    return {
      'lyrics': item['plainLyrics'] ?? '',
      'synced_lyrics': item['syncedLyrics'] ?? '',
      'instrumental': item['instrumental'] ?? false,
      'source': 'https://lrclib.net/api/get/${item['id']}',
    };
  }

  Future<Uint8List?> cover(String id) => _serial(() async {
    await _waitForCover();
    final req = http.Request(
      'GET',
      Uri.https('coverartarchive.org', '/release/$id/front-500'),
    );
    req.headers['User-Agent'] = userAgent;
    final response = await _client
        .send(req)
        .timeout(const Duration(seconds: 35));
    if (response.statusCode == 404) {
      await response.stream.drain<void>();
      return null;
    }
    if (response.statusCode != 200) {
      if ([429, 503].contains(response.statusCode)) {
        _coverCooldown(response);
      }
      await response.stream.drain<void>();
      throw ApiException('Artwork lookup failed. Existing image was kept.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 35),
    )) {
      bytes.add(chunk);
      if (bytes.length > 5 * 1024 * 1024)
        throw ApiException(
          'The cover exceeds 5 MiB. Existing artwork was kept.',
        );
    }
    return bytes.takeBytes();
  });

  Future<bool> coverAvailable(String id) => _serial(() async {
    final cached = _coverChecks[id];
    if (cached != null && DateTime.now().difference(cached.$1).inMinutes < 15)
      return cached.$2;
    await _waitForCover();
    final response = await _client
        .head(
          Uri.https('coverartarchive.org', '/release/$id/front-500'),
          headers: {
            'User-Agent': userAgent.isEmpty
                ? 'Resonance/1.2 (Android on-device)'
                : userAgent,
          },
        )
        .timeout(const Duration(seconds: 35));
    if ([429, 503].contains(response.statusCode)) {
      _coverCooldown(response);
      throw ApiException('Artwork service is busy; availability is unknown.');
    }
    final bool found;
    if (response.statusCode == 404) {
      found = false;
    } else if (response.statusCode == 200 &&
        (response.headers['content-type'] ?? '').toLowerCase().startsWith(
          'image/',
        )) {
      found = true;
    } else {
      throw ApiException('Artwork availability could not be confirmed.');
    }
    if (_coverChecks.length >= 300)
      _coverChecks.remove(_coverChecks.keys.first);
    _coverChecks[id] = (DateTime.now(), found);
    return found;
  });

  Future<void> _waitForCover() async {
    final wait = (_next['coverartarchive.org'] ?? DateTime.now()).difference(
      DateTime.now(),
    );
    if (wait.inSeconds > 30)
      throw ApiException(
        'Artwork service requested a cooldown. Try again later.',
      );
    if (!wait.isNegative) await Future<void>.delayed(wait);
    _next['coverartarchive.org'] = DateTime.now().add(
      const Duration(milliseconds: 400),
    );
  }

  void _coverCooldown(http.BaseResponse response) {
    final value = response.headers['retry-after'] ?? '60';
    var seconds = int.tryParse(value) ?? 60;
    if (int.tryParse(value) == null) {
      try {
        seconds = HttpDate.parse(value).difference(DateTime.now()).inSeconds;
      } catch (_) {}
    }
    _next['coverartarchive.org'] = DateTime.now().add(
      Duration(seconds: seconds < 1 ? 1 : seconds),
    );
  }

  Future<Map<String, dynamic>> availability(
    Map candidate,
    double fileDuration,
  ) async {
    final result = <String, dynamic>{
      'has_lyrics': null,
      'has_cover': null,
      'instrumental': false,
      'warnings': <String>[],
    };
    final title = candidate['title'] as String? ?? '';
    final artist = candidate['artist'] as String? ?? '';
    if (title.isNotEmpty && artist.isNotEmpty) {
      try {
        final seconds = candidate['duration'];
        final item = await lyrics(
          {
            'title': title,
            'artist': artist,
            'album': candidate['album'] as String? ?? '',
          },
          seconds is num && seconds > 0 && seconds <= 86400
              ? seconds.toDouble()
              : fileDuration,
        );
        result['has_lyrics'] =
            item != null &&
            ((item['lyrics'] as String).trim().isNotEmpty ||
                (item['synced_lyrics'] as String).trim().isNotEmpty);
        result['instrumental'] = item?['instrumental'] == true;
      } catch (e) {
        (result['warnings'] as List<String>).add('$e');
      }
    } else {
      (result['warnings'] as List<String>).add(
        'A title and artist are needed to check lyrics.',
      );
    }
    final release = candidate['release_id'] as String? ?? '';
    if (release.isEmpty) {
      result['has_cover'] = false;
    } else {
      try {
        result['has_cover'] = await coverAvailable(release);
      } catch (e) {
        (result['warnings'] as List<String>).add('$e');
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> enrich(
    Map body,
    Map<String, String> current,
    double duration,
  ) async {
    final recording = body['recording_id'] as String;
    final releaseId = body['release_id'] as String?;
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
    );
    if (!uuid.hasMatch(recording) ||
        (releaseId != null && !uuid.hasMatch(releaseId)))
      throw ApiException('Invalid MusicBrainz identifier.');
    final rec =
        await request(
              Uri.https('musicbrainz.org', '/ws/2/recording/$recording', {
                'inc': 'artist-credits+releases+genres',
                'fmt': 'json',
              }),
            )
            as Map;
    final tags = Map<String, String>.of(current);
    tags['title'] = rec['title'] as String? ?? tags['title']!;
    final artist = credit(rec['artist-credit']);
    if (artist.isNotEmpty) tags['artist'] = artist;
    tags['recording_id'] = recording;
    tags['release_id'] = '';
    final genres = (rec['genres'] as List? ?? []).cast<Map>().toList()
      ..sort((a, b) => (b['count'] as num).compareTo(a['count'] as num));
    if (genres.isNotEmpty) tags['genre'] = genres.first['name'] as String;
    final notices = <String>[];
    final sources = ['https://musicbrainz.org/recording/$recording'];
    if (releaseId != null) {
      final release =
          await request(
                Uri.https('musicbrainz.org', '/ws/2/release/$releaseId', {
                  'inc': 'recordings+artist-credits',
                  'fmt': 'json',
                }),
              )
              as Map;
      Map? selectedTrack, selectedMedium;
      for (final medium in release['media'] as List? ?? []) {
        for (final track in medium['tracks'] as List? ?? []) {
          if (track['recording']?['id'] == recording) {
            selectedTrack = track as Map;
            selectedMedium = medium as Map;
            break;
          }
        }
        if (selectedTrack != null) break;
      }
      if (selectedTrack == null)
        throw ApiException(
          'The recording is not on that release. Choose another candidate.',
        );
      final medium = selectedMedium!;
      tags['album'] = release['title'] as String? ?? '';
      tags['album_artist'] = credit(release['artist-credit']);
      tags['date'] = normalizeProviderDate(release['date']);
      tags['release_id'] = releaseId;
      tags['track_number'] =
          '${selectedTrack['position']}/${medium['track-count'] ?? (medium['tracks'] as List).length}';
      tags['disc_number'] =
          '${medium['position']}/${(release['media'] as List).length}';
      sources.add('https://musicbrainz.org/release/$releaseId');
    } else {
      notices.add('No release selected; existing album tags were kept.');
    }
    if (body['lyrics'] != false) {
      try {
        final item = await lyrics(tags, duration);
        if (item == null) {
          notices.add('No matching lyrics; existing lyrics were kept.');
        } else {
          tags['lyrics'] = item['lyrics'] as String;
          tags['synced_lyrics'] = item['synced_lyrics'] as String;
          sources.add(item['source'] as String);
          if (item['instrumental'] == true)
            notices.add('LRCLIB marks this recording as instrumental.');
        }
      } catch (e) {
        notices.add('$e');
      }
    }
    Uint8List? art;
    if (body['cover'] != false && releaseId != null) {
      try {
        art = await cover(releaseId);
        if (art == null)
          notices.add('No release cover; existing artwork was kept.');
        else
          sources.add(
            'https://coverartarchive.org/release/$releaseId/front-500',
          );
      } catch (e) {
        notices.add('$e');
      }
    }
    return {
      'tags': tags,
      'cover_base64': art == null ? null : base64Encode(art),
      'warnings': notices,
      'sources': sources,
    };
  }
}
