import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resonance/availability_badges.dart';
import 'package:resonance/candidate_availability.dart';
import 'package:resonance/engine.dart';
import 'package:resonance/public_services.dart';

class FakeEngine implements MusicEngine {
  FakeEngine(this.respond);
  final Future<Map<String, dynamic>> Function(String, Object?) respond;
  @override
  Future<Map<String, dynamic>> json(
    String path, {
    String method = 'GET',
    Object? body,
    Map<String, String>? query,
  }) => respond(path, body);
  @override
  Future<Map<String, dynamic>> upload(String path, String filename) =>
      throw UnimplementedError();
  @override
  Future<Uint8List> export(String id, Map<String, dynamic> body) =>
      throw UnimplementedError();
  @override
  void close() {}
}

void main() {
  testWidgets(
    'candidate badges distinguish available, missing, checking and unknown',
    (tester) async {
      for (final (candidate, lyrics, cover)
          in <(Map<String, dynamic>, String, String)>[
            ({'has_lyrics': true, 'has_cover': false}, 'Lyrics ✓', 'No cover'),
            ({'has_lyrics': false, 'has_cover': true}, 'No lyrics', 'Cover ✓'),
            ({}, 'Lyrics ?', 'Cover ?'),
            ({'availability_loading': true}, 'Lyrics …', 'Cover …'),
          ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AvailabilityBadges(candidate: candidate)),
          ),
        );
        expect(find.text(lyrics), findsOneWidget);
        expect(find.text(cover), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  test(
    'results update per candidate and service failure does not mean absent',
    () async {
      final entries = <Map<String, dynamic>>[
        {'title': 'Song', 'artist': 'Artist', 'release_id': 'release-one'},
        {'title': 'Song', 'artist': 'Artist', 'release_id': 'release-two'},
      ];
      var calls = 0, updates = 0;
      final engine = FakeEngine((path, body) async {
        calls++;
        if (calls == 1) return {'has_lyrics': true, 'has_cover': false};
        throw StateError('service offline');
      });
      await checkCandidateAvailability(
        engine: engine,
        trackId: 'track',
        candidates: entries,
        isActive: () => true,
        changed: () => updates++,
      );
      expect(entries[0]['has_lyrics'], isTrue);
      expect(entries[0]['has_cover'], isFalse);
      expect(entries[1]['has_lyrics'], isNull);
      expect(entries[1]['has_cover'], isNull);
      expect(
        entries.every((entry) => entry['availability_loading'] == false),
        isTrue,
      );
      expect(updates, 3);
    },
  );

  test(
    'stale background responses do not overwrite replaced results',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      var active = true;
      final entries = <Map<String, dynamic>>[
        {'title': 'Song', 'artist': 'Artist'},
      ];
      final job = checkCandidateAvailability(
        engine: FakeEngine((_, _) => pending.future),
        trackId: 'track',
        candidates: entries,
        isActive: () => active,
        changed: () {},
      );
      active = false;
      pending.complete({'has_lyrics': true, 'has_cover': true});
      await job;
      expect(entries[0]['has_lyrics'], isNull);
    },
  );

  test(
    'Android availability verifies actual lyrics and uses HEAD for release artwork',
    () async {
      final methods = <String>[];
      final services = PublicMusicServices(
        client: MockClient((request) async {
          methods.add(request.method);
          if (request.url.host == 'lrclib.net')
            return http.Response(
              '{"id":1,"plainLyrics":null,"syncedLyrics":"[00:01] Text"}',
              200,
            );
          expect(request.method, 'HEAD');
          return http.Response(
            '',
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );
      addTearDown(services.close);
      final candidate = {
        'title': 'Song',
        'artist': 'Artist',
        'release_id': 'ab4d36ac-ed70-4e6b-8528-8012ab81dd42',
      };
      final result = await services.availability(candidate, 180);
      expect(result['has_lyrics'], isTrue);
      expect(result['has_cover'], isTrue);
      await services.availability(candidate, 180);
      expect(methods, [
        'GET',
        'HEAD',
      ]); // Both checks are reused for this candidate.
    },
  );

  test('Android service errors leave each badge unknown', () async {
    final services = PublicMusicServices(
      client: MockClient((request) async => http.Response('', 503)),
    );
    addTearDown(services.close);
    final result = await services.availability({
      'title': 'Song',
      'artist': 'Artist',
      'release_id': 'ab4d36ac-ed70-4e6b-8528-8012ab81dd42',
    }, 180);
    expect(result['has_lyrics'], isNull);
    expect(result['has_cover'], isNull);
  });
}
