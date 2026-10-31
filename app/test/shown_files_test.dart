// FILES A SCRIPT MAKES AND SHOWS (BTL-20261031-1334): THE EXCEL AND PDF WRITERS, THE show OPERATION, AND HOW THE CHAT SHOWS THE FILES (A PICTURE IN PLACE, OTHER FILES TO SAVE OR SHARE)

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:botler/core/file_actions.dart';
import 'package:botler/core/script/documents.dart';
import 'package:botler/core/script/host.dart';
import 'package:botler/core/script/sandbox.dart';
import 'package:botler/core/script/scratch.dart';
import 'package:botler/core/script/storage.dart';
import 'package:botler/features/chat/shown_files.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// -- TYPES -- //

class FakeActions implements FileActions {
  final List<String> saved = <String>[];
  final List<String> shared = <String>[];

  @override
  Future<bool> save(String path, String name) async {
    saved.add(name);
    return true;
  }

  @override
  Future<void> share(String path, String name) async => shared.add(name);
}

// -- FUNCTIONS -- //

Map<String, Object?> parse(String s) =>
    (jsonDecode(s) as Map<String, Object?>).cast<String, Object?>();

Uint8List png() {
  final image = img.Image(width: 40, height: 40);
  img.fill(image, color: img.ColorRgb8(10, 120, 200));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('the excel writer', () {
    test('makes a workbook that opens: parts, rows, numbers, text and a bold header', () {
      final bytes = xlsxBytes(<Object?>[
        <Object?>['Name', 'Amount'],
        <Object?>['Rent & <co>', 12500.5],
        <Object?>['Paid', true],
        <Object?>[null, 'x'],
      ], sheet: 'Bills');
      final zip = ZipDecoder().decodeBytes(bytes);
      final names = zip.files.map((f) => f.name).toSet();
      expect(
        names,
        containsAll(<String>[
          '[Content_Types].xml',
          '_rels/.rels',
          'xl/workbook.xml',
          'xl/_rels/workbook.xml.rels',
          'xl/styles.xml',
          'xl/worksheets/sheet1.xml',
        ]),
      );
      String read(String n) => utf8.decode(
        zip.files.firstWhere((f) => f.name == n).content as List<int>,
      );
      final sheet = read('xl/worksheets/sheet1.xml');
      expect(sheet, contains('<c r="A1" s="1" t="inlineStr">'));
      expect(sheet, contains('Rent &amp; &lt;co&gt;'));
      expect(sheet, contains('<c r="B2"><v>12500.5</v></c>'));
      expect(sheet, contains('t="b"><v>1</v>'));
      // An empty cell is skipped, the next one keeps its own address
      expect(sheet, contains('<c r="B4"'));
      expect(sheet, isNot(contains('r="A4"')));
      expect(read('xl/workbook.xml'), contains('name="Bills"'));
    });

    test('refuses rows that are not rows, and too many', () {
      expect(() => xlsxBytes('nope'), throwsA(isA<ScratchException>()));
      expect(() => xlsxBytes(<Object?>['a']), throwsA(isA<ScratchException>()));
      expect(
        () => xlsxBytes(List<Object?>.filled(sheetMaxRows + 1, <Object?>[1])),
        throwsA(isA<ScratchException>()),
      );
      expect(
        () =>
            xlsxBytes(<Object?>[List<Object?>.filled(sheetMaxColumns + 1, 1)]),
        throwsA(isA<ScratchException>()),
      );
    });

    test('a sheet name that Excel would refuse is made safe', () {
      final zip = ZipDecoder().decodeBytes(
        xlsxBytes(<Object?>[
          <Object?>[1],
        ], sheet: 'a/b:c*${'x' * 40}'),
      );
      final book = utf8.decode(
        zip.files.firstWhere((f) => f.name == 'xl/workbook.xml').content
            as List<int>,
      );
      final name = RegExp(r'name="([^"]*)"').firstMatch(book)!.group(1)!;
      expect(name.length, lessThanOrEqualTo(31));
      expect(name, isNot(matches(RegExp(r'[\\/?*\[\]:]'))));
    });
  });

  group('the pdf writer', () {
    test('writes a well formed file: header, objects, a cross reference at the right offset', () {
      final bytes = pdfBytes(
        'Hello (world)\nsecond line ₱500',
        title: 'Report',
      );
      final text = latin1.decode(bytes);
      expect(text, startsWith('%PDF-1.4'));
      expect(text, contains('(Report) Tj'));
      expect(text, contains(r'(Hello \(world\)) Tj'));
      expect(text, contains('PHP 500'));
      expect(text.trimRight(), endsWith('%%EOF'));
      final start = int.parse(
        RegExp(r'startxref\n(\d+)').firstMatch(text)!.group(1)!,
      );
      expect(text.substring(start, start + 4), 'xref');
      // Every object offset points at its own "n 0 obj"
      final table = RegExp(r'(\d{10}) 00000 n').allMatches(text).toList();
      for (final (i, m) in table.indexed) {
        final off = int.parse(m.group(1)!);
        expect(
          text.substring(off, off + '${i + 1} 0 obj'.length),
          '${i + 1} 0 obj',
        );
      }
    });

    test('long text wraps and runs onto more pages', () {
      final long = List<String>.generate(
        130,
        (i) => 'line $i ${'word ' * 30}',
      ).join('\n');
      final text = latin1.decode(pdfBytes(long));
      expect(RegExp('/Type /Page ').allMatches(text).length, greaterThan(2));
      expect(RegExp(r'\) Tj').allMatches(text).length, greaterThan(130));
    });

    test('too much text is refused', () {
      expect(
        () => pdfBytes('x' * (pdfMaxChars + 1)),
        throwsA(isA<ScratchException>()),
      );
    });
  });

  group('show', () {
    late Directory dir;
    late ScratchFolder scratch;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('shown');
      scratch = ScratchFolder(
        Directory('${dir.path}${Platform.pathSeparator}c'),
      );
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test(
      'lists the files shown, once each, only if they exist, at most eight',
      () {
        final h = ScriptHost(scratch: scratch);
        scratch.write('a.png', png());
        expect(parse(h.call('show', {'name': 'a.png'})), {'v': null});
        expect(parse(h.call('show', {'name': 'a.png'})), {'v': null});
        expect(
          parse(h.call('show', {'name': 'missing.pdf'}))['e'],
          contains('no file'),
        );
        expect(h.shown, <String>['a.png']);
        for (var i = 0; i < 7; i++) {
          scratch.write('f$i.txt', <int>[65]);
          h.call('show', {'name': 'f$i.txt'});
        }
        expect(h.shown, hasLength(8));
        scratch.write('one-more.txt', <int>[65]);
        expect(
          parse(h.call('show', {'name': 'one-more.txt'}))['e'],
          contains('At most 8'),
        );
      },
    );

    test('xlsx.write and pdf.write make the files in the folder', () {
      final h = ScriptHost(scratch: scratch);
      final x =
          parse(
                h.call('xlsx.write', {
                  'name': 'bills.xlsx',
                  'rows': [
                    ['a', 1],
                  ],
                }),
              )['v']!
              as Map<String, Object?>;
      expect(x['size'], scratch.read('bills.xlsx').length);
      expect(scratch.read('bills.xlsx').sublist(0, 2), <int>[0x50, 0x4b]);
      parse(h.call('pdf.write', {'name': 'r.pdf', 'text': 'hi'}));
      expect(latin1.decode(scratch.read('r.pdf').sublist(0, 5)), '%PDF-');
      expect(
        parse(
          h.call('xlsx.write', {'name': '../x.xlsx', 'rows': <Object?>[]}),
        )['e'],
        isNotNull,
      );
      expect(
        parse(h.call('xlsx.write', {'name': 'y.xlsx', 'rows': 'bad'}))['e'],
        contains('list of rows'),
      );
    });

    test('the result names the shown files with their sizes', () {
      final result = ScriptResult(
        ok: true,
        output: '',
        files: const <({String name, int size})>[(name: 'a.png', size: 123)],
        shown: const <String>['a.png'],
      );
      expect(result.toJson()['shown'], <Object?>[
        <String, Object?>{'name': 'a.png', 'size': 123},
      ]);
      expect(
        const ScriptResult(ok: true, output: '').toJson().containsKey('shown'),
        isFalse,
      );
    });
  });

  group('the chat', () {
    Future<(FakeActions, Directory, Widget)> shell(
      WidgetTester tester,
      List<({String name, int size})> files,
    ) async {
      final dir = Directory.systemTemp.createTempSync('shown_ui');
      addTearDown(() => dir.deleteSync(recursive: true));
      final storage = ScriptStorage(owner: 'a@b.c', baseDir: () async => dir);
      final scratch = await tester.runAsync(() => storage.scratchFor('chat-1'));
      await tester.runAsync(() async {
        File('${scratch!.path}${Platform.pathSeparator}pic.png')
            .writeAsBytesSync(png());
        File('${scratch.path}${Platform.pathSeparator}bills.xlsx')
            .writeAsBytesSync(<int>[1, 2, 3]);
      });
      final actions = FakeActions();
      final app = ProviderScope(
        overrides: [
          scriptStorageProvider.overrideWithValue(storage),
          fileActionsProvider.overrideWithValue(actions),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: ShownFiles(files: files, chatId: 'chat-1'),
          ),
        ),
      );
      return (actions, dir, app);
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    testWidgets(
      'a picture is shown in place, and a sheet is a line that saves or shares',
      (tester) async {
        final (actions, _, app) = await shell(
          tester,
          const <({String name, int size})>[
            (name: 'pic.png', size: 400),
            (name: 'bills.xlsx', size: 3),
          ],
        );
        await tester.pumpWidget(app);
        await settle(tester);
        expect(find.byType(Image), findsOneWidget);
        expect(find.text('bills.xlsx'), findsOneWidget);
        expect(find.text('3 B'), findsOneWidget);
        await tester.tap(find.text('bills.xlsx'));
        await settle(tester);
        expect(find.text('Save to phone'), findsOneWidget);
        await tester.tap(find.text('Save to phone'));
        await settle(tester);
        expect(actions.saved, <String>['bills.xlsx']);
        expect(find.text('Saved to your phone.'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.tap(find.text('bills.xlsx'));
        await settle(tester);
        await tester.tap(find.text('Share or open with…'));
        await settle(tester);
        expect(actions.shared, <String>['bills.xlsx']);
      },
    );

    testWidgets('tapping a picture opens it large, with save and share', (
      tester,
    ) async {
      final (actions, _, app) = await shell(
        tester,
        const <({String name, int size})>[(name: 'pic.png', size: 400)],
      );
      await tester.pumpWidget(app);
      await settle(tester);
      await tester.tap(find.byType(Image));
      await settle(tester);
      expect(find.byTooltip('Save to phone'), findsOneWidget);
      await tester.tap(find.byTooltip('Save to phone'));
      await settle(tester);
      expect(actions.saved, <String>['pic.png']);
    });

    testWidgets('a file that is no longer on the phone says so', (
      tester,
    ) async {
      final (_, _, app) = await shell(tester, const <({String name, int size})>[
        (name: 'gone.pdf', size: 10),
      ]);
      await tester.pumpWidget(app);
      await settle(tester);
      expect(find.textContaining('no longer on this phone'), findsOneWidget);
    });

    test('reads the shown list out of a stored script answer', () {
      expect(
        shownOf(<String, Object?>{
          'shown': <Object?>[
            <String, Object?>{'name': 'a.pdf', 'size': 9},
            'junk',
            <String, Object?>{'size': 1},
          ],
        }),
        [(name: 'a.pdf', size: 9)],
      );
      expect(shownOf(null), isEmpty);
      expect(shownOf(<String, Object?>{'shown': 'x'}), isEmpty);
    });

    test('kinds and sizes', () {
      expect(mimeOf('a.XLSX'), contains('spreadsheetml'));
      expect(isPictureName('a.JPG'), isTrue);
      expect(isPictureName('a.pdf'), isFalse);
      expect(sizeWords(2048), '2.0 KB');
      expect(sizeWords(5 * 1024 * 1024), '5.0 MB');
    });
  });
}
