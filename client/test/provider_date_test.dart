import 'package:flutter_test/flutter_test.dart';
import 'package:resonance/provider_date.dart';
import 'package:resonance/public_services.dart';

void main() {
  test('provider dates retain full or partial precision', () {
    final cases = <(Object?, String)>[
      ({'day': 19, 'month': 7, 'year': 2017}, '2017-07-19'),
      ({'year': 2017}, '2017'),
      ({'year': 2017, 'month': 7}, '2017-07'),
      ({'year': 2017, 'month': 0, 'day': 0}, '2017'),
      ({'year': 2017, 'month': 2, 'day': 29}, '2017-02'),
      ({'year': 2024, 'month': 2, 'day': 29}, '2024-02-29'),
      ({'year': '2017', 'month': '7', 'day': '19'}, '2017-07-19'),
      ({'year': true}, ''),
      ({'year': 10000}, ''),
      ({'month': 7, 'day': 19}, ''),
      ({}, ''),
      (null, ''),
      ([], ''),
      (2017, ''),
      ('2017-07-19', '2017-07-19'),
      ('2017-07', '2017-07'),
      ('2017', '2017'),
    ];
    for (final (raw, expected) in cases) {
      expect(normalizeProviderDate(raw), expected, reason: '$raw');
    }
  });

  test('AcoustID candidates expose date strings to the Android interface', () {
    final services = PublicMusicServices();
    addTearDown(services.close);
    final result = services.candidates(
      [
        {
          'id': 'recording-id',
          'title': 'Song',
          'artists': [
            {'name': 'Artist'},
          ],
          'releases': [
            {
              'id': 'release-id',
              'date': {'day': 19, 'month': 7, 'year': 2017},
            },
          ],
        },
      ],
      'fingerprint',
      .98,
    );
    expect(result.single['date'], '2017-07-19');
    expect(result.single['date'], isA<String>());
  });
}
