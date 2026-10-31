// THE SCRIPT SANDBOX (BTL-20261031-1334): THE SCRATCH FOLDER, THE HOST OPERATIONS, AND (WHEN THE NATIVE ENGINE IS AVAILABLE) QUICKJS ITSELF
// The scratch and host tests need no engine and always run. The engine tests run when FLUTTER_QJS_NEXT_LIBRARY points at a built flutter_qjs_next
// library (a plain `flutter test` does not build plugins); they are skipped otherwise.

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:botler/core/script/host.dart';
import 'package:botler/core/script/sandbox.dart';
import 'package:botler/core/script/scratch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// -- CONSTANTS -- //

final bool hasEngine =
    (Platform.environment['FLUTTER_QJS_NEXT_LIBRARY'] ?? '').isNotEmpty;

// -- FUNCTIONS -- //

Uint8List png(int w, int h) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(10, 120, 200));
  return Uint8List.fromList(img.encodePng(image));
}

Map<String, Object?> parse(String s) =>
    (jsonDecode(s) as Map<String, Object?>).cast<String, Object?>();

void main() {
  late Directory dir;
  late ScratchFolder scratch;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('script_scratch');
    scratch = ScratchFolder(
      Directory('${dir.path}${Platform.pathSeparator}c1'),
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('the scratch folder', () {
    test('writes, reads, lists and removes flat files', () {
      scratch.write('a.txt', utf8.encode('hello'));
      scratch.write('b.csv', utf8.encode('1,2'));
      expect(utf8.decode(scratch.read('a.txt')), 'hello');
      expect(scratch.list().map((f) => f.name), <String>['a.txt', 'b.csv']);
      scratch.remove('a.txt');
      expect(scratch.list().map((f) => f.name), <String>['b.csv']);
      scratch.clear();
      expect(scratch.list(), isEmpty);
    });

    test('refuses names that could leave the folder', () {
      for (final bad in <String>[
        '../x',
        'a/b',
        r'a\b',
        '..',
        '.hidden',
        '',
        'x' * 65,
        'C:evil',
        'a..b',
      ]) {
        expect(
          () => scratch.write(bad, <int>[1]),
          throwsA(isA<ScratchException>()),
          reason: bad,
        );
      }
      expect(dir.listSync().length, 0, reason: 'nothing was created');
    });

    test('keeps to its caps', () {
      expect(
        () => scratch.write('big', Uint8List(scratchMaxFileBytes + 1)),
        throwsA(isA<ScratchException>()),
      );
      for (var i = 0; i < 2; i++) {
        scratch.write('f$i', Uint8List(scratchMaxFileBytes));
      }
      expect(
        () => scratch.write('f2', Uint8List(scratchMaxFileBytes)),
        throwsA(isA<ScratchException>()),
        reason: '50 MB together',
      );
      // Replacing a file counts its new size, not both
      scratch.write('f0', Uint8List(10));
      scratch.write('f2', Uint8List(scratchMaxFileBytes ~/ 2));
    });

    test('keeps to 200 files', () {
      for (var i = 0; i < scratchMaxFiles; i++) {
        scratch.write('n$i', <int>[1]);
      }
      expect(
        () => scratch.write('one-more', <int>[1]),
        throwsA(isA<ScratchException>()),
      );
      scratch.write('n0', <int>[2]);
    });
  });

  group('the host operations', () {
    ScriptHost host({List<String> photos = const <String>[]}) =>
        ScriptHost(scratch: scratch, photos: photos, outputChars: 50);

    test('files: write, read, list, remove, base64', () {
      final h = host();
      expect(parse(h.call('fs.write', {'name': 'a.txt', 'text': 'héllo'})), {
        'v': null,
      });
      expect(parse(h.call('fs.read', {'name': 'a.txt'}))['v'], 'héllo');
      expect(parse(h.call('fs.list', {}))['v'], [
        {'name': 'a.txt', 'size': 6},
      ]);
      expect(
        parse(
          h.call('fs.writeBase64', {
            'name': 'b.bin',
            'b64': base64Encode(<int>[1, 2, 3]),
          }),
        ),
        {'v': null},
      );
      expect(
        parse(h.call('fs.readBase64', {'name': 'b.bin'}))['v'],
        base64Encode(<int>[1, 2, 3]),
      );
      h.call('fs.remove', {'name': 'a.txt'});
      expect(
        parse(h.call('fs.read', {'name': 'a.txt'}))['e'],
        contains('no file'),
      );
    });

    test(
      'refuses an unknown operation, bad names and wrong argument types',
      () {
        final h = host();
        expect(
          parse(h.call('exec', {'cmd': 'ls'}))['e'],
          contains('no operation'),
        );
        expect(parse(h.call('fs.read', {'name': '../secret'}))['e'], isNotNull);
        expect(
          parse(h.call('fs.write', {'name': 5, 'text': 'x'}))['e'],
          isNotNull,
        );
        expect(parse(h.call('fs.write', {'name': 'a'}))['e'], isNotNull);
        expect(
          parse(h.call('fs.writeBase64', {'name': 'a', 'b64': '***'}))['e'],
          isNotNull,
        );
        expect(parse(h.call('print', null))['e'], isNotNull);
      },
    );

    test('print is capped and says so', () {
      final h = host();
      h.call('print', {'t': 'a' * 30});
      h.call('print', {'t': 'b' * 30});
      h.call('print', {'t': 'c'});
      expect(h.output, endsWith('[output cut]'));
      expect(h.output.length, lessThan(80));
      expect(h.output, isNot(contains('c\n')));
    });

    test(
      'pictures: info, resize, crop, rotate and grayscale make new files',
      () {
        scratch.write('p.png', png(200, 100));
        final h = host();
        expect(parse(h.call('image.info', {'src': 'p.png'}))['v'], {
          'width': 200,
          'height': 100,
        });
        var r =
            parse(
                  h.call('image.resize', {
                    'src': 'p.png',
                    'dst': 'small.jpg',
                    'width': 100,
                    'height': 100,
                  }),
                )['v']!
                as Map<String, Object?>;
        expect((r['width'], r['height']), (100, 50));
        r =
            parse(
                  h.call('image.resize', {
                    'src': 'p.png',
                    'dst': 'sq.png',
                    'width': 60,
                    'height': 60,
                    'fit': 'cover',
                  }),
                )['v']!
                as Map<String, Object?>;
        expect((r['width'], r['height']), (60, 60));
        r =
            parse(
                  h.call('image.crop', {
                    'src': 'p.png',
                    'dst': 'c.png',
                    'x': 10,
                    'y': 10,
                    'width': 50,
                    'height': 40,
                  }),
                )['v']!
                as Map<String, Object?>;
        expect((r['width'], r['height']), (50, 40));
        r =
            parse(
                  h.call('image.rotate', {
                    'src': 'p.png',
                    'dst': 'r.png',
                    'degrees': 90,
                  }),
                )['v']!
                as Map<String, Object?>;
        expect((r['width'], r['height']), (100, 200));
        expect(
          parse(
            h.call('image.grayscale', {'src': 'p.png', 'dst': 'g.png'}),
          )['e'],
          isNull,
        );
        // The file format follows the name
        expect(scratch.read('small.jpg').sublist(0, 2), <int>[0xff, 0xd8]);
        expect(scratch.read('c.png').sublist(1, 4), utf8.encode('PNG'));
      },
    );

    test('pictures: bad boxes, sizes and files are refused with a reason', () {
      scratch.write('p.png', png(200, 100));
      scratch.write('t.txt', utf8.encode('not a picture'));
      final h = host();
      expect(
        parse(
          h.call('image.crop', {
            'src': 'p.png',
            'dst': 'c.png',
            'x': 150,
            'y': 0,
            'width': 100,
            'height': 50,
          }),
        )['e'],
        contains('inside'),
      );
      expect(
        parse(
          h.call('image.resize', {
            'src': 'p.png',
            'dst': 'x.png',
            'width': 99999,
          }),
        )['e'],
        contains('between'),
      );
      expect(
        parse(h.call('image.resize', {'src': 'p.png', 'dst': 'x.png'}))['e'],
        contains('width'),
      );
      expect(
        parse(h.call('image.info', {'src': 't.txt'}))['e'],
        contains('not a picture'),
      );
      expect(
        parse(h.call('image.info', {'src': 'missing.png'}))['e'],
        contains('no file'),
      );
      expect(
        parse(
          h.call('image.resize', {
            'src': 'p.png',
            'dst': '../x.png',
            'width': 10,
          }),
        )['e'],
        isNotNull,
      );
    });

    test('a thin picture cannot be stretched into a huge one', () {
      scratch.write('thin.png', png(1, 4000));
      final h = host();
      // One side given: the other follows the shape, so 1 x 4000 at width 4000 would be 4000 x 16 million
      expect(
        parse(
          h.call('image.resize', {
            'src': 'thin.png',
            'dst': 'x.png',
            'width': 4000,
          }),
        )['e'],
        contains('out of range'),
      );
      expect(
        parse(
          h.call('image.resize', {
            'src': 'thin.png',
            'dst': 'x.png',
            'width': 64,
            'height': 4000,
            'fit': 'cover',
          }),
        )['e'],
        isNull,
        reason: 'a size inside the limits is still made',
      );
      // A side over the limit is refused (the sum of both sides is held to the pixel budget too)
      scratch.write('wide.png', png(300, 200));
      expect(
        parse(
          h.call('image.resize', {
            'src': 'wide.png',
            'dst': 'y.png',
            'width': 4096,
            'height': 4097,
          }),
        )['e'],
        contains('between'),
      );
      // A turn that would make a canvas beyond the limits is refused before it is made
      scratch.write('long.png', png(3000, 3000));
      expect(
        parse(
          h.call('image.rotate', {
            'src': 'long.png',
            'dst': 'z.png',
            'degrees': 45,
          }),
        )['e'],
        isNotNull,
      );
      expect(
        parse(
          h.call('image.rotate', {
            'src': 'wide.png',
            'dst': 'ok.png',
            'degrees': 30,
          }),
        )['e'],
        isNull,
      );
    });

    test('a photo of the message is copied in by number, and only those', () {
      final photo = File('${dir.path}${Platform.pathSeparator}photo1.png')
        ..writeAsBytesSync(png(80, 40));
      final h = host(photos: <String>[photo.path]);
      expect(parse(h.call('fs.photo', {'n': 1, 'name': 'in.png'}))['v'], {
        'width': 80,
        'height': 40,
        'size': photo.lengthSync(),
      });
      expect(scratch.exists('in.png'), isTrue);
      expect(
        parse(h.call('fs.photo', {'n': 2, 'name': 'x.png'}))['e'],
        contains('between 1 and 1'),
      );
      expect(
        parse(host().call('fs.photo', {'n': 1, 'name': 'x.png'}))['e'],
        contains('no photo'),
      );
      photo.deleteSync();
      expect(
        parse(h.call('fs.photo', {'n': 1, 'name': 'again.png'}))['e'],
        contains('no longer'),
      );
    });

    test('base64 text round trips', () {
      final h = host();
      final enc =
          parse(h.call('base64.encode', {'t': 'héllo'}))['v']! as String;
      expect(parse(h.call('base64.decode', {'b': enc}))['v'], 'héllo');
    });
  });

  group(
    'the engine',
    skip: hasEngine ? false : 'FLUTTER_QJS_NEXT_LIBRARY is not set',
    () {
      Future<ScriptResult> run(
        String code, {
        String input = '',
        int timeoutMs = 5000,
        int memoryBytes = scriptMemoryBytes,
        List<String> photos = const <String>[],
      }) => runScript(
        code: code,
        scratch: scratch.dir,
        input: input,
        photos: photos,
        timeoutMs: timeoutMs,
        memoryBytes: memoryBytes,
      ).result;

      test('prints, reads INPUT and does plain maths', () async {
        final r = await run(
          'print(6 * 7); console.log("a", {b: 1}); print(INPUT.toUpperCase());',
          input: 'hi',
        );
        expect(r.ok, isTrue, reason: r.error);
        expect(r.output, '42\na {"b":1}\nHI');
      });

      test('works on files and csv', () async {
        final r = await run('''
        fs.write("data.csv", "name,amount\\nrent,500000\\n\\"a,b\\",250000\\n");
        const rows = csv.parse(fs.read("data.csv"));
        let total = 0;
        for (const row of rows.slice(1)) total += parseInt(row[1], 10);
        print(rows.length, total);
        fs.write("out.csv", csv.stringify(rows));
        print(fs.list().map(f => f.name).join());
      ''');
        expect(r.ok, isTrue, reason: r.error);
        expect(r.output, '3 750000\ndata.csv,out.csv');
        expect(r.files.map((f) => f.name), <String>['data.csv', 'out.csv']);
      });

      test('resizes a picture', () async {
        scratch.write('p.png', png(300, 150));
        final r = await run(
          'const o = image.resize("p.png", "small.png", {width: 100}); print(o.width, o.height);',
        );
        expect(r.ok, isTrue, reason: r.error);
        expect(r.output, '100 50');
      });

      test('makes a sheet and a pdf and shows them', () async {
        scratch.write('p.png', png(80, 40));
        final r = await run('''
          xlsx.write("bills.xlsx", [["name", "amount"], ["rent", 500000]], {sheet: "Bills"});
          pdf.write("report.pdf", "Total: 500000", {title: "Report"});
          image.resize("p.png", "small.png", {width: 20});
          show("small.png"); show("bills.xlsx"); show("report.pdf");
          print(fs.list().length);
        ''');
        expect(r.ok, isTrue, reason: r.error);
        expect(r.shown, <String>['small.png', 'bills.xlsx', 'report.pdf']);
        expect((r.toJson()['shown']! as List<Object?>).length, 3);
        expect(scratch.read('bills.xlsx').sublist(0, 2), <int>[0x50, 0x4b]);
        // Keep a copy for a check with a real PDF reader outside the test
        final keep = Platform.environment['BOTLER_KEEP_DOCS'];
        if (keep != null && keep.isNotEmpty) {
          File('$keep/report.pdf').writeAsBytesSync(scratch.read('report.pdf'));
          File('$keep/bills.xlsx').writeAsBytesSync(scratch.read('bills.xlsx'));
        }
      });

      test(
        'has no way out: no network, no bridge, no escape from the folder',
        () async {
          final r = await run('''
        print(typeof fetch, typeof XMLHttpRequest, typeof sendMessage, typeof require, typeof process, typeof WebSocket);
        try { fs.read("../../etc/passwd"); } catch (e) { print("blocked:", e.message.length > 0); }
        try { sendMessage("fs.read", "{}"); } catch (e) { print("no bridge"); }
      ''');
          expect(r.ok, isTrue, reason: r.error);
          expect(
            r.output,
            startsWith(
              'undefined undefined undefined undefined undefined undefined',
            ),
          );
          expect(r.output, contains('blocked: true'));
          expect(r.output, contains('no bridge'));
        },
      );

      test('reports a syntax error and a thrown error', () async {
        final a = await run('print(');
        expect(a.ok, isFalse);
        expect(a.error, contains('SyntaxError'));
        final b = await run('print("before"); throw new Error("boom");');
        expect(b.ok, isFalse);
        expect(b.output, 'before');
        expect(b.error, contains('boom'));
      });

      test('stops a script that runs too long', () async {
        final r = await run('for (;;) {}', timeoutMs: 400);
        expect(r.ok, isFalse);
        expect(r.error, contains('longer than'));
      });

      test('a chain of promise jobs is held to the same clock', () async {
        final clock = Stopwatch()..start();
        final r = await run(
          'function f() { const t = Date.now(); while (Date.now() - t < 400) {} Promise.resolve().then(f); } f();',
          timeoutMs: 1000,
        );
        expect(r.ok, isFalse);
        expect(r.error, contains('longer than'));
        // Each job alone is under the clock; the chain as a whole is cut at about one clock, not run for thousands of jobs
        expect(clock.elapsedMilliseconds, lessThan(4000));
      });

      test('stops a script that uses too much memory', () async {
        final r = await run(
          'const a = []; for (;;) a.push(new Array(100000).fill(1));',
          memoryBytes: 16 * 1024 * 1024,
        );
        expect(r.ok, isFalse);
        expect(r.error, contains('memory'));
      });

      test('Stop gives up waiting at once', () async {
        final started = runScript(
          code: 'for (;;) {}',
          scratch: scratch.dir,
          timeoutMs: 1500,
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final clock = Stopwatch()..start();
        started.stop();
        final r = await started.result;
        expect(clock.elapsedMilliseconds, lessThan(300));
        expect(r.error, contains('Stopped'));
        // Let the worker end on its own clock so it does not outlive the test
        await Future<void>.delayed(const Duration(milliseconds: 1800));
      });

      test(
        'refuses code that is empty or too long without starting the engine',
        () async {
          expect((await run('   ')).error, contains('1 to 20000'));
          expect(
            (await run('x' * (scriptMaxCodeChars + 1))).error,
            contains('1 to 20000'),
          );
        },
      );
    },
  );
}
