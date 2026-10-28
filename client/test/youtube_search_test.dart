import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resonance/api.dart';
import 'package:resonance/youtube_cover.dart';
import 'package:resonance/youtube_cover_picker.dart';
import 'package:resonance/youtube_search.dart';

YoutubeSearchVideo video(
  String id,
  String title, {
  String author = 'Artist',
  double? duration = 200,
  bool live = false,
}) => YoutubeSearchVideo(
  id: id,
  title: title,
  author: author,
  duration: duration,
  live: live,
);

// Widget tests exercise selection state; real image decoding is covered by
// youtube_cover_test.dart outside the widget test's fake asynchronous clock.
class PickerCovers extends YoutubeCovers {
  PickerCovers({required super.client});
  @override
  Future<YoutubeCover> load(String input) async => YoutubeCover(
    bytes: File('test/fixtures/youtube-maxres.jpg').readAsBytesSync(),
    title: 'Song',
    author: 'Artist',
    videoUrl: Uri.parse('https://www.youtube.com/watch?v=aaaaaaaaaaa'),
    width: 1280,
    height: 720,
  );
}

void main() {
  test(
    'matching official audio outranks wrong songs, covers and long versions',
    () {
      final ranked = rankYoutubeCovers(
        [
          video('aaaaaaaaaaa', 'Other song - Official Audio'),
          video('bbbbbbbbbbb', 'Song karaoke'),
          video('ccccccccccc', 'Song official audio', author: 'Artist - Topic'),
          video('ddddddddddd', 'Song live 2 hours', duration: 7200),
          video('eeeeeeeeeee', 'Song', author: 'Other artist'),
        ],
        title: 'Song',
        artist: 'Artist',
        duration: 200,
      );
      expect(ranked.first.video.id, 'ccccccccccc');
      expect(
        ranked.first.reasons,
        containsAll(['Title matches', 'Artist matches', 'Similar duration']),
      );
    },
  );

  test('requested remix is not penalized for its version', () {
    final ranked = rankYoutubeCovers(
      [
        video('aaaaaaaaaaa', 'Song official audio'),
        video('bbbbbbbbbbb', 'Song Remix official audio'),
      ],
      title: 'Song Remix',
      artist: 'Artist',
    );
    expect(ranked.first.video.id, 'bbbbbbbbbbb');
  });

  test(
    'filters invalid/duplicate/live entries, caps results and preserves ties',
    () {
      final ranked = rankYoutubeCovers(
        [
          video('invalid', 'Song'),
          video('aaaaaaaaaaa', 'Song', live: true),
          video('bbbbbbbbbbb', 'Song'),
          video('bbbbbbbbbbb', 'Song duplicate'),
          video('ccccccccccc', 'Song'),
          for (var i = 0; i < 20; i++)
            video('videoid00${i.toString().padLeft(2, '0')}', 'Song'),
        ],
        title: 'Song',
        artist: 'Artist',
      );
      expect(ranked, hasLength(8));
      expect(ranked[0].video.id, 'bbbbbbbbbbb');
      expect(ranked[1].video.id, 'ccccccccccc');
      expect(ranked.map((r) => r.video.id).toSet(), hasLength(8));
    },
  );

  test(
    'Unicode title and artist match; unknown/nonfinite duration is harmless',
    () {
      final ranked = rankYoutubeCovers(
        [
          video('aaaaaaaaaaa', 'Other'),
          video(
            'bbbbbbbbbbb',
            'Jóga – Official Audio',
            author: 'Björk',
            duration: double.nan,
          ),
        ],
        title: 'Jóga',
        artist: 'Björk',
        duration: double.nan,
      );
      expect(ranked.first.video.id, 'bbbbbbbbbbb');
      expect(
        ranked.first.reasons,
        containsAll(['Title matches', 'Artist matches']),
      );
    },
  );

  test(
    'search builds artist/title query and accepts explicit query refinements',
    () async {
      final queries = <String>[];
      final search = YoutubeCoverSearch(
        lookup: (query) async {
          queries.add(query);
          return [video('aaaaaaaaaaa', 'Song')];
        },
      );
      addTearDown(search.close);
      await search.search(title: 'Song', artist: 'Artist');
      await search.search(
        title: 'Song',
        artist: 'Artist',
        query: 'Artist Song album cover',
      );
      expect(queries, ['Artist Song', 'Artist Song album cover']);
    },
  );

  test('empty/oversized queries do not reach provider', () async {
    final search = YoutubeCoverSearch(
      lookup: (_) async {
        fail('Invalid search reached provider');
      },
    );
    addTearDown(search.close);
    await expectLater(
      search.search(title: '', artist: ''),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      search.search(title: 'x' * 301, artist: ''),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'search failures are actionable and cancelled results cannot be used',
    () async {
      final failed = YoutubeCoverSearch(
        lookup: (_) async => throw StateError('blocked'),
      );
      addTearDown(failed.close);
      await expectLater(
        failed.search(title: 'Song', artist: ''),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('paste a video link'),
          ),
        ),
      );
      final pending = Completer<List<YoutubeSearchVideo>>();
      final search = YoutubeCoverSearch(lookup: (_) => pending.future);
      final result = search.search(title: 'Song', artist: '');
      search.close();
      pending.complete([video('aaaaaaaaaaa', 'Song')]);
      await expectLater(result, throwsA(isA<ApiException>()));
    },
  );

  YoutubeCovers covers() => PickerCovers(
    client: MockClient((request) async {
      if (request.url.path == '/oembed') {
        return http.Response(
          jsonEncode({
            'title': 'Song',
            'author_name': 'Artist',
            'thumbnail_url': 'https://i.ytimg.com/vi/aaaaaaaaaaa/hqdefault.jpg',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response.bytes(
        File('test/fixtures/youtube-maxres.jpg').readAsBytesSync(),
        200,
        headers: {'content-type': 'image/jpeg'},
      );
    }),
  );

  testWidgets(
    'opening searches automatically and shows ranked thumbnail choices',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: YoutubeCoverPicker(
              query: 'Artist Song',
              title: 'Song',
              artist: 'Artist',
              searchFactory: () => YoutubeCoverSearch(
                lookup: (query) async {
                  expect(query, 'Artist Song');
                  calls++;
                  return [video('aaaaaaaaaaa', 'Song official audio')];
                },
              ),
              coverFactory: covers,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('1. Song official audio'), findsOneWidget);
      expect(find.text('Preview this cover'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use cover'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Preview this cover'));
      await tester.tap(find.text('Preview this cover'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use cover'),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Save image'),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('1280 × 720 pixels'), findsOneWidget);
      await tester.ensureVisible(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, 'Different search');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use cover'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('a replaced search ignores stale results', (tester) async {
    final pending = Completer<List<YoutubeSearchVideo>>();
    final queries = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: YoutubeCoverPicker(
            query: 'Song',
            searchFactory: () => YoutubeCoverSearch(
              lookup: (query) async {
                queries.add(query);
                return queries.length == 1
                    ? pending.future
                    : [video('bbbbbbbbbbb', 'New Song')];
              },
            ),
            coverFactory: covers,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(queries, ['Song']);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Find covers'),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField).first, 'New Song');
    // onChanged enables the button through setState. Rebuild before tapping;
    // otherwise the tap still reaches the previous disabled button widget.
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Find covers'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Find covers'));
    await tester.pumpAndSettle();
    expect(queries, ['Song', 'New Song']);
    expect(find.text('1. New Song'), findsOneWidget);

    // Complete the superseded request only after the replacement is visible.
    pending.complete([video('aaaaaaaaaaa', 'Stale Song')]);
    await tester.pumpAndSettle();
    expect(find.textContaining('Stale Song'), findsNothing);
    expect(find.text('1. New Song'), findsOneWidget);
    expect(queries, ['Song', 'New Song']);
  });
}
