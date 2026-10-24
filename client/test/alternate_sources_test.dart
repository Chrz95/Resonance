import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resonance/alternate_picker.dart';
import 'package:resonance/alternate_sources.dart';

void main() {
  test(
    'artwork URLs cannot direct downloads to other hosts or insecure endpoints',
    () {
      expect(
        safeArtworkUri('https://is1-ssl.mzstatic.com/image.jpg'),
        isNotNull,
      );
      for (final url in [
        'http://is1-ssl.mzstatic.com/image.jpg',
        'https://127.0.0.1/private',
        'https://mzstatic.com.attacker.test/image.jpg',
        'https://user:pass@is1-ssl.mzstatic.com/image.jpg',
      ]) {
        expect(safeArtworkUri(url), isNull);
      }
    },
  );

  test(
    'alternate covers are filtered by artist and duplicate album IDs',
    () async {
      final client = MockClient((_) async => http.Response('', 404));
      addTearDown(client.close);
      final sources = AlternateSources(
        client: client,
        lookup: (uri, {missingOk = false}) async => {
          'results': [
            {
              'collectionId': 1,
              'artistName': 'Artist',
              'collectionName': 'Album',
              'trackName': 'Song',
              'artworkUrl100': 'https://is1-ssl.mzstatic.com/a.jpg',
            },
            {
              'collectionId': 1,
              'artistName': 'Artist',
              'artworkUrl100': 'https://is1-ssl.mzstatic.com/a.jpg',
            },
            {
              'collectionId': 2,
              'artistName': 'Wrong artist',
              'artworkUrl100': 'https://is1-ssl.mzstatic.com/a.jpg',
            },
          ],
        },
      );
      final result = await sources.find({
        'kind': 'cover',
        'title': 'Song',
        'artist': 'Artist',
        'album': 'Album',
      });
      expect(result['options'], hasLength(1));
    },
  );

  test(
    'alternate lyrics retain a second source when the first is unavailable',
    () async {
      final client = MockClient((_) async => http.Response('', 404));
      addTearDown(client.close);
      final sources = AlternateSources(
        client: client,
        lookup: (uri, {missingOk = false}) async {
          if (uri.host == 'api.lyrics.ovh') throw StateError('offline');
          return [
            {
              'id': 1,
              'trackName': 'Song',
              'artistName': 'Artist',
              'plainLyrics': 'Found lyrics',
            },
          ];
        },
      );
      final result = await sources.find({
        'kind': 'lyrics',
        'title': 'Song',
        'artist': 'Artist',
      });
      expect(result['options'], hasLength(1));
      expect(result['warnings'], hasLength(1));
    },
  );

  test(
    'a cover download falls back to the original size without following redirects',
    () async {
      final client = MockClient((request) async {
        expect(request.followRedirects, isFalse);
        if (request.url.path.contains('600x600')) return http.Response('', 404);
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'image/jpeg'},
        );
      });
      addTearDown(client.close);
      final sources = AlternateSources(
        client: client,
        lookup: (uri, {missingOk = false}) async => {
          'results': [
            {
              'collectionId': 1,
              'artworkUrl100': 'https://is1-ssl.mzstatic.com/100x100bb.jpg',
            },
          ],
        },
      );
      final result = await sources.cover(1);
      expect(
        base64Decode(result['cover_base64'] as String),
        orderedEquals([1, 2, 3]),
      );
    },
  );

  testWidgets(
    'alternate lyrics are previewed and download requires an explicit choice',
    (tester) async {
      Map<String, dynamic>? choice;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  choice = await pickAlternateSource(
                    context,
                    kind: 'lyrics',
                    candidate: {'title': 'Song', 'artist': 'Artist'},
                    options: [
                      {
                        'source': 'lyrics.ovh',
                        'title': 'Song',
                        'artist': 'Artist',
                        'album': 'Album',
                        'lyrics': 'Preview these lyrics',
                        'synced_lyrics': '',
                      },
                    ],
                    warnings: [],
                  );
                },
                child: const Text('Other lyrics'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Other lyrics'));
      await tester.pumpAndSettle();
      expect(find.text('Preview these lyrics'), findsOneWidget);
      expect(choice, isNull);
      await tester.ensureVisible(find.text('Save lyrics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save lyrics'));
      await tester.pumpAndSettle();
      expect(choice!['action'], 'save');
    },
  );
}
