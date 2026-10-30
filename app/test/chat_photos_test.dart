// THE PHOTO STORE OF SENT MESSAGES: COPY, FILE BY TURN, FIND AGAIN, DROP WHAT IS GONE, KEEP AT MOST THE CAP, WIPE.

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';

import 'package:botler/core/chat_photos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- FUNCTIONS -- //

Future<ChatPhotoStore> _store(Directory base, {String owner = 'a@x.y'}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return _storeOn(base, await SharedPreferences.getInstance(), owner);
}

ChatPhotoStore _storeOn(Directory base, SharedPreferences p, String owner) =>
    ChatPhotoStore(prefs: p, owner: owner, baseDir: () async => base);

File _picked(Directory dir, String name) {
  final f = File('${dir.path}${Platform.pathSeparator}$name')
    ..writeAsBytesSync(<int>[1, 2, 3]);
  return f;
}

void main() {
  late Directory base;
  late Directory picks;

  setUp(() {
    base = Directory.systemTemp.createTempSync('botler_photos_base');
    picks = Directory.systemTemp.createTempSync('botler_photos_picks');
  });

  tearDown(() {
    base.deleteSync(recursive: true);
    picks.deleteSync(recursive: true);
  });

  group('PhotoIndex', () {
    test('a repeat for the same turn replaces, not adds', () {
      final i = PhotoIndex()
        ..put('t1', <String>['a', 'b'])
        ..put('t1', <String>['c']);
      expect(i.of('t1'), <String>['c']);
      expect(i.count, 1);
    });

    test('evict drops the oldest turns first', () {
      final i = PhotoIndex()
        ..put('t1', <String>['a', 'b'])
        ..put('t2', <String>['c'])
        ..put('t3', <String>['d']);
      final gone = i.evict(2);
      expect(gone, <String>['a', 'b']);
      expect(i.of('t1'), isEmpty);
      expect(i.names, <String>{'c', 'd'});
    });

    test('encode and decode round trip, and bad text is an empty index', () {
      final i = PhotoIndex()..put('t1', <String>['a']);
      expect(PhotoIndex.decode(i.encode()).of('t1'), <String>['a']);
      expect(PhotoIndex.decode('not json').count, 0);
      expect(PhotoIndex.decode('[1,2]').count, 0);
      expect(PhotoIndex.decode(null).count, 0);
    });

    test('keepOnly forgets names that are gone', () {
      final i = PhotoIndex()
        ..put('t1', <String>['a', 'b'])
        ..put('t2', <String>['c']);
      expect(i.keepOnly((n) => n == 'a'), isTrue);
      expect(i.of('t1'), <String>['a']);
      expect(i.of('t2'), isEmpty);
    });
  });

  group('ChatPhotoStore', () {
    test(
      'stage copies, promote files it under the turn and it is found again',
      () async {
        final s = await _store(base);
        final staged = await s.stage(_picked(picks, 'one.png').path);
        expect(staged, isNotNull);
        final final0 = await s.promote('t1', <String>[staged!]);
        expect(final0, hasLength(1));
        expect(File(final0.single).existsSync(), isTrue);
        expect(File(staged).existsSync(), isFalse);
        // A fresh store on the same folder and preferences finds it
        final again = _storeOn(
          base,
          await SharedPreferences.getInstance(),
          'a@x.y',
        );
        await again.ready();
        expect(again.photosOf('t1'), final0);
        expect(again.photosOf('t2'), isEmpty);
      },
    );

    test('a file that vanished is dropped from the index', () async {
      final s = await _store(base);
      final staged = await s.stage(_picked(picks, 'one.png').path);
      final done = await s.promote('t1', <String>[staged!]);
      File(done.single).deleteSync();
      final again = _storeOn(
        base,
        await SharedPreferences.getInstance(),
        'a@x.y',
      );
      await again.ready();
      expect(again.photosOf('t1'), isEmpty);
    });

    test('stage of a missing source is null, not a crash', () async {
      final s = await _store(base);
      expect(
        await s.stage('${picks.path}${Platform.pathSeparator}none.png'),
        isNull,
      );
    });

    test('discard removes staged copies', () async {
      final s = await _store(base);
      final staged = await s.stage(_picked(picks, 'one.png').path);
      await s.discard(<String>[staged!]);
      expect(File(staged).existsSync(), isFalse);
    });

    test(
      'more than the cap evicts the oldest turn and deletes its files',
      () async {
        final s = await _store(base);
        final first = await s.promote('t0', <String>[
          (await s.stage(_picked(picks, 'p.png').path))!,
        ]);
        for (var n = 1; n <= maxStoredPhotos; n++) {
          await s.promote('t$n', <String>[
            (await s.stage(_picked(picks, 'p$n.png').path))!,
          ]);
        }
        expect(File(first.single).existsSync(), isFalse);
        expect(s.photosOf('t0'), isEmpty);
        expect(s.photosOf('t$maxStoredPhotos'), hasLength(1));
      },
    );

    test('a retry of the same turn replaces its earlier files', () async {
      final s = await _store(base);
      final a = await s.promote('t1', <String>[
        (await s.stage(_picked(picks, 'a.png').path))!,
      ]);
      final b = await s.promote('t1', <String>[
        (await s.stage(_picked(picks, 'b.png').path))!,
      ]);
      expect(File(a.single).existsSync(), isFalse);
      expect(s.photosOf('t1'), b);
    });

    test('files nothing points at are swept at start', () async {
      final s = await _store(base);
      await s.ready();
      final stray = File(
        '${base.path}${Platform.pathSeparator}chat_photos${Platform.pathSeparator}${base64Url.encode(utf8.encode('a@x.y')).replaceAll('=', '')}${Platform.pathSeparator}stray.png',
      )..writeAsBytesSync(<int>[9]);
      final again = _storeOn(
        base,
        await SharedPreferences.getInstance(),
        'a@x.y',
      );
      await again.ready();
      expect(stray.existsSync(), isFalse);
    });

    test('two openings at once build one index and lose nothing', () async {
      final s = await _store(base);
      final a = await s.stage(_picked(picks, 'a.png').path);
      final b = await s.stage(_picked(picks, 'b.png').path);
      final both = await Future.wait(<Future<List<String>>>[
        s.promote('t1', <String>[a!]),
        s.promote('t2', <String>[b!]),
      ]);
      expect(File(both[0].single).existsSync(), isTrue);
      expect(File(both[1].single).existsSync(), isTrue);
      expect(s.photosOf('t1'), both[0]);
      expect(s.photosOf('t2'), both[1]);
    });

    test(
      'a wipe while files are being filed keeps nothing and writes no index',
      () async {
        final s = await _store(base);
        final a = await s.stage(_picked(picks, 'a.png').path);
        final filing = s.promote('t1', <String>[a!]);
        await s.wipe();
        expect(await filing, isEmpty);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getKeys().where((k) => k.startsWith(photoIndexPrefix)),
          isEmpty,
        );
      },
    );

    test(
      'another owner never sees the photos, and wipe removes everything',
      () async {
        final s = await _store(base);
        final done = await s.promote('t1', <String>[
          (await s.stage(_picked(picks, 'a.png').path))!,
        ]);
        final other = _storeOn(
          base,
          await SharedPreferences.getInstance(),
          'b@x.y',
        );
        await other.ready();
        expect(other.photosOf('t1'), isEmpty);
        await s.wipe();
        expect(File(done.single).existsSync(), isFalse);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getKeys().where((k) => k.startsWith(photoIndexPrefix)),
          isEmpty,
        );
      },
    );
  });
}
