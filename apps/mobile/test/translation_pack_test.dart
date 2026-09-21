import 'package:farmerapp_mobile/translation_pack.dart';
import 'package:test/test.dart';

/// NF-008: the review pack a native speaker gets, and the checks that stand
/// between their spreadsheet and the ARB files.
void main() {
  const english = <String, Object?>{
    '@@locale': 'en',
    'actionDone': 'Done',
    '@actionDone': <String, Object?>{'description': 'Primary button on F32'},
    'kisanAcres': '{count} acres',
    '@kisanAcres': <String, Object?>{
      'placeholders': <String, Object?>{'count': <String, Object?>{}},
    },
    'otpSubtitle': 'We sent a code to {phone}',
  };

  group('buildPack', () {
    test('one row per string, with English, current and description', () {
      final rows = buildPack(
        source: english,
        target: const <String, Object?>{
          '@@locale': 'te',
          'actionDone': 'పూర్తయింది',
        },
        usage: const <String, List<String>>{
          'actionDone': <String>['farmer/orders/pay', 'agent/store/checkout'],
        },
      );

      expect(rows.map((r) => r.key), <String>[
        'actionDone',
        'kisanAcres',
        'otpSubtitle',
      ]);
      final done = rows.first;
      expect(done.english, 'Done');
      expect(done.current, 'పూర్తయింది');
      expect(done.description, 'Primary button on F32');
      // Context is the point: "Done" on a payment screen and "Done" on a
      // photo screen are different words in Telugu.
      expect(done.screens, <String>[
        'farmer/orders/pay',
        'agent/store/checkout',
      ]);
    });

    test('ARB metadata is never offered for translation', () {
      final rows = buildPack(
        source: english,
        target: const <String, Object?>{},
      );
      expect(rows.map((r) => r.key), isNot(contains('@@locale')));
      expect(rows.map((r) => r.key), isNot(contains('@actionDone')));
    });

    test('an untranslated string comes through with an empty current cell', () {
      final rows = buildPack(
        source: english,
        target: const <String, Object?>{'actionDone': 'పూర్తయింది'},
      );
      expect(rows.firstWhere((r) => r.key == 'kisanAcres').current, '');
    });

    test('placeholders are listed so the reviewer keeps them', () {
      final rows = buildPack(
        source: english,
        target: const <String, Object?>{},
      );
      expect(
        rows.firstWhere((r) => r.key == 'kisanAcres').placeholders,
        <String>['count'],
      );
      expect(
        rows.firstWhere((r) => r.key == 'otpSubtitle').placeholders,
        <String>['phone'],
      );
      expect(rows.first.placeholders, isEmpty);
    });
  });

  group('placeholdersOf', () {
    test('finds simple, plural and select placeholders', () {
      expect(placeholdersOf('no placeholders'), isEmpty);
      expect(placeholdersOf('{count} acres'), <String>['count']);
      expect(
        placeholdersOf('{count, plural, =1{1 day} other{{count} days}}'),
        <String>['count'],
      );
      expect(placeholdersOf('{name} owes {amount}'), <String>[
        'amount',
        'name',
      ]);
    });
  });

  group('CSV round trip', () {
    test('survives commas, quotes, newlines and Indic text', () {
      const rows = <ReviewRow>[
        ReviewRow(
          key: 'weird',
          english: 'He said "hello", then left\nand waved',
          current: 'ఆయన "హలో" అన్నారు',
          screens: <String>['farmer/home'],
          description: 'A, B and C',
        ),
      ];

      final parsed = parseCsv(toCsv(rows));

      expect(parsed, hasLength(1));
      expect(parsed.single.key, 'weird');
      expect(parsed.single.english, 'He said "hello", then left\nand waved');
      expect(parsed.single.current, 'ఆయన "హలో" అన్నారు');
    });

    test('starts with a BOM so Excel shows Telugu, not mojibake', () {
      expect(toCsv(const <ReviewRow>[]), startsWith('﻿'));
    });

    test('reads a sheet back with a BOM, CRLF and reordered columns', () {
      const csv =
          '﻿reviewed,key,note\r\n'
          'కొత్త అనువాదం,actionDone,sounds formal\r\n';
      final rows = parseCsv(csv);
      expect(rows.single.key, 'actionDone');
      expect(rows.single.reviewed, 'కొత్త అనువాదం');
      expect(rows.single.note, 'sounds formal');
    });

    test('a sheet with no key column is refused, not half-read', () {
      expect(
        () => parseCsv('english,reviewed\nDone,పూర్తయింది\n'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('applyReview', () {
    const target = <String, Object?>{
      '@@locale': 'te',
      'actionDone': 'పూర్తయింది',
      'kisanAcres': '{count} ఎకరాలు',
      'otpSubtitle': 'పాత టెక్స్ట్ {phone}',
    };

    test('writes back only the rows the reviewer filled in', () {
      final result = applyReview(
        target: target,
        source: english,
        rows: const <ReviewRow>[
          ReviewRow(
            key: 'actionDone',
            english: 'Done',
            current: 'x',
            reviewed: 'అయిపోయింది',
          ),
          // Left blank: a reviewer working through 2,000 strings sends back a
          // partly filled sheet, and that has to be normal.
          ReviewRow(
            key: 'kisanAcres',
            english: '',
            current: '',
            reviewed: '  ',
          ),
        ],
      );

      expect(result.ok, isTrue);
      expect(result.changed, <String>['actionDone']);
      expect(result.updated['actionDone'], 'అయిపోయింది');
      expect(result.updated['kisanAcres'], '{count} ఎకరాలు');
      // Metadata is carried through untouched.
      expect(result.updated['@@locale'], 'te');
    });

    test('a dropped placeholder refuses the whole file', () {
      final result = applyReview(
        target: target,
        source: english,
        rows: const <ReviewRow>[
          ReviewRow(
            key: 'actionDone',
            english: '',
            current: '',
            reviewed: 'సరే',
          ),
          ReviewRow(
            key: 'kisanAcres',
            english: '',
            current: '',
            reviewed: 'ఎకరాలు', // {count} gone
          ),
        ],
      );

      expect(result.ok, isFalse);
      expect(result.problems.single, contains('count'));
      // Nothing is written, including the row that was fine: a half-applied
      // review is worse than none, because nobody can tell what shipped.
      expect(result.updated, target);
      expect(result.changed, isEmpty);
    });

    test('an invented placeholder is refused too', () {
      final result = applyReview(
        target: target,
        source: english,
        rows: const <ReviewRow>[
          ReviewRow(
            key: 'otpSubtitle',
            english: '',
            current: '',
            reviewed: '{phone} కు {code} పంపాము',
          ),
        ],
      );
      expect(result.ok, isFalse);
      expect(result.problems.single, contains('code'));
    });

    test('a key that no longer exists is reported, not silently added', () {
      final result = applyReview(
        target: target,
        source: english,
        rows: const <ReviewRow>[
          ReviewRow(
            key: 'renamedAway',
            english: '',
            current: '',
            reviewed: 'x',
          ),
        ],
      );
      expect(result.ok, isFalse);
      expect(result.problems.single, contains('renamedAway'));
    });

    test('an unchanged translation is not counted as a change', () {
      final result = applyReview(
        target: target,
        source: english,
        rows: const <ReviewRow>[
          ReviewRow(
            key: 'actionDone',
            english: '',
            current: '',
            reviewed: 'పూర్తయింది',
          ),
        ],
      );
      expect(result.ok, isTrue);
      expect(result.changed, isEmpty);
    });
  });

  test('writeArb keeps the project formatting', () {
    final out = writeArb(const <String, Object?>{'@@locale': 'te', 'a': 'b'});
    expect(out, '{\n  "@@locale": "te",\n  "a": "b"\n}\n');
  });
}
