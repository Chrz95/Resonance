import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resonance/android_engine.dart';
import 'package:resonance/models.dart';
import 'package:resonance/public_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.resonance/audio-test');
  final calls = <String>[];
  final requests = <http.Request>[];
  late AndroidEngine engine;
  setUp(() {
    calls.clear();
    requests.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'getSettings':
              return {'acoustid_key': '', 'user_agent': ''};
            case 'saveSettings':
              return null;
            case 'import':
              return {
                'id': 'local-1',
                'filename': 'song.mp3',
                'duration': 180.0,
                'size': 100,
                'tags': {for (final key in tagNames) key: ''},
                'cover': Uint8List.fromList([1, 2, 3]),
              };
            case 'fingerprint':
              return 'AQAA-local-fingerprint';
            case 'delete':
              return null;
            default:
              throw PlatformException(code: 'UNEXPECTED', message: call.method);
          }
        });
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.host == 'musicbrainz.org')
        return http.Response(
          jsonEncode({
            'recordings': [
              {
                'id': 'ab4d36ac-ed70-4e6b-8528-8012ab81dd42',
                'title': 'Song',
                'score': 99,
                'artist-credit': [
                  {'name': 'Artist'},
                ],
                'releases': [],
              },
            ],
          }),
          200,
        );
      if (request.url.host == 'lrclib.net')
        return http.Response(
          jsonEncode({
            'id': 1,
            'plainLyrics': 'A line',
            'syncedLyrics': '[00:01] A line',
          }),
          200,
        );
      if (request.url.host == 'api.acoustid.org')
        return http.Response(jsonEncode({'status': 'ok', 'results': []}), 200);
      throw StateError('Unexpected host: ${request.url.host}');
    });
    engine = AndroidEngine(
      channel: channel,
      services: PublicMusicServices(client: client),
    );
  });
  tearDown(() {
    engine.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'local import and fingerprint work without server or Internet',
    () async {
      await engine.loadSettings();
      final track = await engine.upload('/phone/song.mp3', 'song.mp3');
      expect(track['cover_base64'], base64Encode([1, 2, 3]));
      final health = await engine.json('/health');
      expect(health['on_device'], isTrue);
      final result = await engine.json(
        '/tracks/local-1/identify',
        method: 'POST',
      );
      expect(result['signature'], hasLength(64));
      expect(requests, isEmpty);
      expect(calls, containsAll(['import', 'fingerprint']));
      await engine.json('/tracks/local-1', method: 'DELETE');
      expect(calls.last, 'delete');
    },
  );

  test(
    'lookups go straight to free services without any desktop host',
    () async {
      await engine.saveSettings('free-key', 'mailto:developer@example.org');
      await engine.upload('/phone/song.mp3', 'song.mp3');
      final search = await engine.json('/search', query: {'q': 'Artist Song'});
      expect((search['candidates'] as List).first['title'], 'Song');
      await engine.json('/search', query: {'q': 'Artist Song'});
      expect(
        requests.where((r) => r.url.host == 'musicbrainz.org'),
        hasLength(1),
      );
      final tags = {for (final key in tagNames) key: ''}
        ..['title'] = 'Song'
        ..['artist'] = 'Artist';
      final lyrics = await engine.json(
        '/tracks/local-1/lyrics',
        method: 'POST',
        body: tags,
      );
      expect(lyrics['lyrics'], 'A line');
      await engine.json('/tracks/local-1/identify', method: 'POST');
      expect(
        requests.map((r) => r.url.host),
        containsAll(['musicbrainz.org', 'lrclib.net', 'api.acoustid.org']),
      );
      expect(requests.every((r) => r.url.scheme == 'https'), isTrue);
      expect(
        requests.every((r) => !r.headers.containsKey('Authorization')),
        isTrue,
      );
      final acoustid = requests.last;
      expect(acoustid.body, contains('fingerprint='));
    },
  );

  test(
    'saving a manual draft uses local writer and Android document picker',
    () async {
      final directory = await Directory.systemTemp.createTemp('resonance-test');
      addTearDown(() => directory.delete(recursive: true));
      final output = File('${directory.path}/tagged.mp3');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = call.arguments as Map;
            if (call.method == 'import')
              return {
                'id': 'local-1',
                'filename': 'song.mp3',
                'duration': 180.0,
                'size': 10,
                'tags': {for (final key in tagNames) key: ''},
                'cover': Uint8List(0),
              };
            if (call.method == 'export') {
              expect((args['tags'] as Map)['title'], 'Typed by hand');
              expect((args['tags'] as Map)['lyrics'], 'My lyrics');
              expect(args['cover'], orderedEquals([1, 2]));
              await output.writeAsBytes([1, 2, 3]);
              return output.path;
            }
            if (call.method == 'saveFile') {
              expect(args['filename'], 'my-song.mp3');
              return true;
            }
            throw StateError(call.method);
          });
      await engine.upload('/phone/song.mp3', 'song.mp3');
      final tags = {for (final key in tagNames) key: ''}
        ..['title'] = 'Typed by hand'
        ..['lyrics'] = 'My lyrics';
      expect(
        await engine.saveExport('local-1', {
          'tags': tags,
          'cover_action': 'replace',
          'cover_base64': base64Encode([1, 2]),
        }, 'my-song.mp3'),
        isTrue,
      );
      expect(await output.exists(), isFalse);
      expect(requests, isEmpty);
    },
  );

  test(
    'overwrite forwards remembered document URI and retains fallback URI',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'overwrite-uri-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final output = File('${directory.path}/prepared.mp3');
      const uri = 'content://documents/original-song';
      String? sentUri;
      var overwritten = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = call.arguments as Map;
            if (call.method == 'import')
              return {
                'id': 'local-1',
                'filename': 'song.mp3',
                'duration': 180.0,
                'size': 10,
                'tags': {for (final key in tagNames) key: ''},
                'cover': Uint8List(0),
              };
            if (call.method == 'export') {
              await output.writeAsBytes([1, 2, 3]);
              return output.path;
            }
            if (call.method == 'overwriteFile') {
              expect(args['original_uri'], sentUri);
              expect(args['expected_digest'], 'a' * 64);
              overwritten++;
              return {'digest': 'b' * 64, 'original_uri': uri};
            }
            throw StateError('Unexpected call: ${call.method}');
          });
      await engine.upload('/cached/song.mp3', 'song.mp3');
      for (final originalUri in <String?>[uri, null]) {
        sentUri = originalUri;
        final result = await engine.overwriteExport(
          'local-1',
          {
            'tags': {for (final key in tagNames) key: ''},
            'cover_action': 'keep',
          },
          'song.mp3',
          'a' * 64,
          originalUri: originalUri,
        );
        expect(result?['original_uri'], uri);
        expect(result?['digest'], 'b' * 64);
        expect(await output.exists(), isFalse);
      }
      expect(overwritten, 2);
      expect(requests, isEmpty);
    },
  );

  test('provider cooldowns are honored', () async {
    final service = PublicMusicServices(
      client: MockClient((request) async {
        return http.Response('', 429, headers: {'retry-after': '120'});
      }),
    );
    addTearDown(service.close);
    service.userAgent = 'ResonanceTests/1.1 (test@example.org)';
    await expectLater(
      service.search('Artist'),
      throwsA(predicate((e) => '$e'.contains('120 seconds'))),
    );
    await expectLater(
      service.search('Artist'),
      throwsA(predicate((e) => '$e'.contains('cooldown'))),
    );
  });
}
