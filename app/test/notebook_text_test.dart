// THE NOTEBOOK TEXT AS THE PAGE READS IT: SECTIONS, BULLETS, AND NOTHING EVER TREATED AS MARKUP

// -- DEP-MODULES -- //
import 'package:flutter_test/flutter_test.dart';

// -- MODULES -- //
import 'package:botler/features/memory/notebook_text.dart';

// -- FUNCTIONS -- //

void main() {
  group('parseNotebook', () {
    test('turns headings into sections and bullets into lines', () {
      final s = parseNotebook(
        '# How Botler talks to you\nShort and warm.\n\n'
        '# People\n- Nena is my mother\n* Ben is my brother\n',
      );
      expect(s.map((e) => e.heading), <String>[
        'How Botler talks to you',
        'People',
      ]);
      expect(s[0].lines.single.text, 'Short and warm.');
      expect(s[0].lines.single.bullet, isFalse);
      expect(s[1].lines.map((l) => l.text), <String>[
        'Nena is my mother',
        'Ben is my brother',
      ]);
      expect(s[1].lines.every((l) => l.bullet), isTrue);
    });

    test('keeps a heading with nothing under it, and any heading level', () {
      final s = parseNotebook('## Plans\n\n### Later ###\n- one');
      expect(s.map((e) => e.heading), <String>['Plans', 'Later']);
      expect(s[0].lines, isEmpty);
      expect(s[1].lines.single.text, 'one');
    });

    test(
      'keeps text before the first heading as a section with no heading',
      () {
        final s = parseNotebook('Loose words\n# People\n- Nena');
        expect(s.first.heading, '');
        expect(s.first.lines.single.text, 'Loose words');
        expect(s.length, 2);
      },
    );

    test(
      'shows markup as plain text: a link, a tag or a table is just words',
      () {
        final s = parseNotebook(
          '# X\n[click](https://evil.example)\n<b>bold</b>\n| a | b |\n',
        );
        expect(s.single.lines.map((l) => l.text), <String>[
          '[click](https://evil.example)',
          '<b>bold</b>',
          '| a | b |',
        ]);
        expect(s.single.lines.any((l) => l.bullet), isFalse);
      },
    );

    test(
      'a dash without a space is not a bullet, and a huge line stays whole',
      () {
        final big = 'x' * 20000;
        final s = parseNotebook('# X\n-5 degrees\n$big');
        expect(s.single.lines[0].text, '-5 degrees');
        expect(s.single.lines[0].bullet, isFalse);
        expect(s.single.lines[1].text.length, 20000);
      },
    );

    test('handles no text, only blank lines, and windows line ends', () {
      expect(parseNotebook(''), isEmpty);
      expect(parseNotebook('\n \n\t\n'), isEmpty);
      final s = parseNotebook('# A\r\n- one\r\n# B\r\n- two\r\n');
      expect(s.map((e) => e.heading), <String>['A', 'B']);
      expect(s[0].lines.single.text, 'one');
    });
  });

  group('isEmptyNotebook', () {
    test('is true for the empty template and for nothing', () {
      expect(isEmptyNotebook(''), isTrue);
      expect(
        isEmptyNotebook(
          '# How Botler talks to you\n\n# About you\n\n# People\n',
        ),
        isTrue,
      );
    });

    test('is false once a line is written anywhere', () {
      expect(isEmptyNotebook('# About you\n- Likes tea\n'), isFalse);
      expect(isEmptyNotebook('Just words'), isFalse);
    });
  });
}
