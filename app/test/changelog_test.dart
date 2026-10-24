// THE CHANGELOG RULES: WHICH BUILDS ARE UNSEEN, THE FIRST-RUN DECISION, AND THE SHIPPED FILE ITSELF.

// -- DEP-MODULES -- //
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'package:botler/core/changelog.dart';

// -- FUNCTIONS -- //

ChangelogEntry _e(int code, {List<String>? fil}) => ChangelogEntry(
  versionCode: code,
  versionName: '1.0.$code',
  en: <String>['en $code'],
  fil: fil ?? <String>['fil $code'],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseChangelog', () {
    test('reads entries newest first and trims lines', () {
      final list = parseChangelog(
        '[{"versionCode":2,"versionName":"1.0.1","en":[" a "],"fil":["b"]},'
        '{"versionCode":5,"versionName":"1.0.4","en":["c"],"fil":[]}]',
      );
      expect(list.map((e) => e.versionCode), <int>[5, 2]);
      expect(list.last.en, <String>['a']);
    });

    test('a bad file or bad entries give an empty or shorter list', () {
      expect(parseChangelog('not json'), isEmpty);
      expect(parseChangelog('{"a":1}'), isEmpty);
      expect(
        parseChangelog(
          '[{"versionCode":0,"en":["x"]},{"versionCode":3,"en":[]},{"versionCode":4,"en":["ok"]}]',
        ).map((e) => e.versionCode),
        <int>[4],
      );
    });
  });

  group('lines', () {
    test('Filipino falls back to English when it is empty', () {
      expect(_e(3).lines('fil'), <String>['fil 3']);
      expect(_e(3, fil: <String>[]).lines('fil'), <String>['en 3']);
      expect(_e(3).lines('en'), <String>['en 3']);
    });
  });

  group('selectUnseen', () {
    final all = <ChangelogEntry>[
      for (final c in <int>[9, 8, 7, 6, 5, 4, 3]) _e(c),
    ];

    test('one new build', () {
      expect(selectUnseen(all, 7, 8).map((e) => e.versionCode), <int>[8]);
    });

    test('skipped builds come newest first', () {
      expect(selectUnseen(all, 5, 8).map((e) => e.versionCode), <int>[8, 7, 6]);
    });

    test('more than five skipped keeps the newest five', () {
      expect(selectUnseen(all, 0, 9).map((e) => e.versionCode), <int>[
        9,
        8,
        7,
        6,
        5,
      ]);
    });

    test('a build above the installed one is not announced', () {
      expect(selectUnseen(all, 5, 6).map((e) => e.versionCode), <int>[6]);
    });

    test('nothing when seen is the installed build or higher, or installed is unknown', () {
      expect(selectUnseen(all, 8, 8), isEmpty);
      expect(selectUnseen(all, 9, 8), isEmpty);
      expect(selectUnseen(all, 0, 0), isEmpty);
    });

    test('a missing intermediate entry is simply absent', () {
      final gap = <ChangelogEntry>[_e(8), _e(6)];
      expect(selectUnseen(gap, 5, 8).map((e) => e.versionCode), <int>[8, 6]);
    });
  });

  group('selectFor', () {
    test('the exact build, or null', () {
      final all = <ChangelogEntry>[_e(8), _e(6)];
      expect(selectFor(all, 6)?.versionCode, 6);
      expect(selectFor(all, 7), isNull);
    });
  });

  group('decideFirstRun', () {
    Future<SharedPreferences> prefs(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      return SharedPreferences.getInstance();
    }

    test('a fresh install counts the current build as seen', () async {
      final p = await prefs(<String, Object>{});
      await decideFirstRun(p, 8);
      expect(seenCode(p), 8);
    });

    test(
      'an upgrade from a build with in-app update shows this build',
      () async {
        final p = await prefs(<String, Object>{'update.lastCheck': 1});
        await decideFirstRun(p, 8);
        expect(seenCode(p), 0);
      },
    );

    test('an existing value is never changed', () async {
      final p = await prefs(<String, Object>{
        'changelog.seen': 6,
        'update.lastCheck': 1,
      });
      await decideFirstRun(p, 8);
      expect(seenCode(p), 6);
    });

    test('an unknown installed build writes nothing', () async {
      final p = await prefs(<String, Object>{});
      await decideFirstRun(p, 0);
      expect(seenCode(p), isNull);
    });
  });

  group('the shipped changelog.json', () {
    test('is registered as an asset and loads', () async {
      expect(await loadChangelog(), isNotEmpty);
    });

    test(
      'has an entry with English and Filipino lines for the pubspec build',
      () async {
        final pub = File('pubspec.yaml').readAsStringSync();
        final code = int.parse(
          RegExp(
            r'^version:\s*\d+\.\d+\.\d+\+(\d+)\s*$',
            multiLine: true,
          ).firstMatch(pub)!.group(1)!,
        );
        final entry = selectFor(await loadChangelog(), code);
        expect(entry, isNotNull, reason: 'add an entry for build $code');
        final name = RegExp(
          r'^version:\s*(\d+\.\d+\.\d+)\+',
          multiLine: true,
        ).firstMatch(pub)!.group(1);
        expect(entry!.versionName, name);
        expect(entry.en, isNotEmpty);
        expect(entry.fil, isNotEmpty);
      },
    );
  });
}
