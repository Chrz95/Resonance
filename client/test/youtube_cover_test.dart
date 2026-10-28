import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resonance/api.dart';
import 'package:resonance/youtube_cover.dart';
import 'package:resonance/youtube_cover_picker.dart';

const id = 'jNQXAC9IVRw';
const imageUrl = 'https://i.ytimg.com/vi/$id/hqdefault.jpg';

http.Response metadata({String thumbnail = imageUrl}) => http.Response(
  jsonEncode({
    'title': 'A song',
    'author_name': 'Artist',
    'thumbnail_url': thumbnail,
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Uint8List fixture(String size) =>
    File('test/fixtures/youtube-$size.jpg').readAsBytesSync();

void main() {
  test(
    'video links normalize to the same ID without fetching supplied URLs',
    () {
      for (final url in [
        'https://www.youtube.com/watch?v=$id&t=30',
        'https://youtu.be/$id?si=share',
        'https://music.youtube.com/watch?v=$id',
        'https://m.youtube.com/watch?v=$id',
        'https://youtube.com/shorts/$id',
        'https://youtube.com/embed/$id',
        'https://youtube.com/live/$id',
        'http://youtube.com/watch?v=$id',
      ]) {
        expect(youtubeVideoId(url), id, reason: url);
      }
      for (final url in [
        'https://youtube.com.evil.test/watch?v=$id',
        'https://youtube.com@evil.test/watch?v=$id',
        'https://user@youtube.com/watch?v=$id',
        'https://youtube.com:123/watch?v=$id',
        'https://127.0.0.1/watch?v=$id',
        'https://youtube.com/playlist?list=$id',
        'https://youtu.be/$id/more',
        'https://youtube.com/watch?v=short',
        'https://youtube.com/watch?v=../../file',
        'file:///tmp/song',
        'not a link',
      ]) {
        expect(youtubeVideoId(url), isNull, reason: url);
      }
    },
  );

  test('search query preserves Unicode and punctuation', () {
    final uri = youtubeSearchUri('  Björk & Artist - Song?  ');
    expect(uri.host, 'www.youtube.com');
    expect(uri.queryParameters['search_query'], 'Björk & Artist - Song?');
  });

  test(
    'selected thumbnail uses bounded direct HTTPS without backend credentials',
    () async {
      final seen = <Uri>[];
      final client = MockClient((request) async {
        seen.add(request.url);
        expect(request.followRedirects, isFalse);
        expect(request.headers.containsKey('Authorization'), isFalse);
        if (request.url.host == 'www.youtube.com') {
          expect(request.url.path, '/oembed');
          expect(
            request.url.queryParameters['url'],
            'https://www.youtube.com/watch?v=$id',
          );
          return metadata();
        }
        expect(
          request.url.toString(),
          'https://i.ytimg.com/vi/$id/maxresdefault.jpg',
        );
        return http.Response.bytes(
          fixture('maxres'),
          200,
          headers: {'content-type': 'image/jpeg'},
        );
      });
      final service = YoutubeCovers(client: client);
      addTearDown(service.close);
      final cover = await service.load('https://youtu.be/$id');
      expect(cover.title, 'A song');
      expect(cover.author, 'Artist');
      expect((cover.width, cover.height), (1280, 720));
      expect(cover.bytes, fixture('maxres'));
      expect(seen, hasLength(2));
    },
  );

  test(
    'missing maximum resolution falls back to standard resolution',
    () async {
      final seen = <String>[];
      final service = YoutubeCovers(
        client: MockClient((request) async {
          if (request.url.path == '/oembed') return metadata();
          seen.add(request.url.pathSegments.last);
          if (seen.last == 'maxresdefault.jpg') return http.Response('', 404);
          return http.Response.bytes(
            fixture('standard'),
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );
      addTearDown(service.close);
      final cover = await service.load('https://youtu.be/$id');
      expect(seen, ['maxresdefault.jpg', 'sddefault.jpg']);
      expect((cover.width, cover.height), (640, 480));
      expect(cover.bytes, fixture('standard'));
    },
  );

  test(
    'tiny HTTP-200 placeholders and invalid images fall back to high resolution',
    () async {
      final seen = <String>[];
      final service = YoutubeCovers(
        client: MockClient((request) async {
          if (request.url.path == '/oembed') return metadata();
          seen.add(request.url.pathSegments.last);
          return http.Response.bytes(
            seen.last == 'maxresdefault.jpg'
                ? fixture('placeholder')
                : seen.last == 'sddefault.jpg'
                ? [255, 216, 255, 217]
                : fixture('high'),
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );
      addTearDown(service.close);
      final cover = await service.load('https://youtu.be/$id');
      expect(seen, ['maxresdefault.jpg', 'sddefault.jpg', 'hqdefault.jpg']);
      expect((cover.width, cover.height), (480, 360));
    },
  );

  test(
    'all unavailable variants fail and duplicate oEmbed URLs are not retried',
    () async {
      final seen = <String>[];
      final service = YoutubeCovers(
        client: MockClient((request) async {
          if (request.url.path == '/oembed') return metadata();
          seen.add(request.url.pathSegments.last);
          return http.Response('', 404);
        }),
      );
      addTearDown(service.close);
      await expectLater(
        service.load('https://youtu.be/$id'),
        throwsA(isA<ApiException>()),
      );
      expect(seen, ['maxresdefault.jpg', 'sddefault.jpg', 'hqdefault.jpg']);
    },
  );

  test('rate limiting stops resolution retries', () async {
    var imageCalls = 0;
    final service = YoutubeCovers(
      client: MockClient((request) async {
        if (request.url.path == '/oembed') return metadata();
        imageCalls++;
        return http.Response('', 429);
      }),
    );
    addTearDown(service.close);
    await expectLater(
      service.load('https://youtu.be/$id'),
      throwsA(isA<ApiException>()),
    );
    expect(imageCalls, 1);
  });

  test('invalid link makes no HTTP request', () async {
    final service = YoutubeCovers(
      client: MockClient((_) async {
        fail('Invalid input must not reach the network');
      }),
    );
    addTearDown(service.close);
    await expectLater(
      service.load('https://evil.test/watch?v=$id'),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'metadata cannot redirect image downloads to other hosts or videos',
    () async {
      for (final url in [
        'http://i.ytimg.com/vi/$id/hqdefault.jpg',
        'https://i.ytimg.com.evil.test/vi/$id/hqdefault.jpg',
        'https://127.0.0.1/secret.jpg',
        'https://user@i.ytimg.com/vi/$id/hqdefault.jpg',
        'https://i.ytimg.com:444/vi/$id/hqdefault.jpg',
        'https://i.ytimg.com/vi/aaaaaaaaaaa/hqdefault.jpg',
        'https://i.ytimg.com/vi/$id/hqdefault.jpg?redirect=1',
      ]) {
        var calls = 0;
        final service = YoutubeCovers(
          client: MockClient((_) async {
            calls++;
            return metadata(thumbnail: url);
          }),
        );
        try {
          await expectLater(
            service.load('https://youtu.be/$id'),
            throwsA(isA<ApiException>()),
          );
          expect(calls, 1);
        } finally {
          service.close();
        }
      }
    },
  );

  test('rejects private/unavailable videos and malformed metadata', () async {
    for (final response in [
      http.Response('private', 401),
      http.Response('gone', 404),
      http.Response('', 302, headers: {'location': 'https://evil.test'}),
      http.Response('{}', 200, headers: {'content-type': 'application/json'}),
      http.Response('[]', 200, headers: {'content-type': 'application/json'}),
      http.Response('html', 200, headers: {'content-type': 'text/html'}),
    ]) {
      final service = YoutubeCovers(client: MockClient((_) async => response));
      try {
        await expectLater(
          service.load('https://youtu.be/$id'),
          throwsA(isA<ApiException>()),
        );
      } finally {
        service.close();
      }
    }
  });

  test(
    'rejects redirects, non-images, oversized metadata and thumbnails',
    () async {
      for (final response in [
        http.Response('', 302, headers: {'location': 'https://evil.test'}),
        http.Response('html', 200, headers: {'content-type': 'text/html'}),
        http.Response.bytes(
          Uint8List(5 * 1024 * 1024 + 1),
          200,
          headers: {'content-type': 'image/jpeg'},
        ),
      ]) {
        final service = YoutubeCovers(
          client: MockClient(
            (request) async =>
                request.url.path == '/oembed' ? metadata() : response,
          ),
        );
        try {
          await expectLater(
            service.load('https://youtu.be/$id'),
            throwsA(isA<ApiException>()),
          );
        } finally {
          service.close();
        }
      }
      final service = YoutubeCovers(
        client: MockClient(
          (_) async => http.Response(
            ' ' * (64 * 1024 + 1),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(service.close);
      await expectLater(
        service.load('https://youtu.be/$id'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  testWidgets('picker requires a successful preview before Use or Save', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: YoutubeCoverPicker(query: 'Artist Song', autoSearch: false),
        ),
      ),
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Use cover'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Save image'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byType(TextField).last,
      'https://evil.test/song',
    );
    await tester.tap(find.text('Preview thumbnail'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Paste a valid YouTube video link'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Use cover'))
          .onPressed,
      isNull,
    );
  });
}
