// THE READER'S BLOCKS AND HEADINGS: A PAGE SPLIT INTO TOP-LEVEL PIECES, FENCED CODE AND LISTS KEPT WHOLE, HEADINGS FOUND WITH THEIR LEVEL.

// -- DEP-MODULES -- //
import 'package:botler/features/notebooks/reader_blocks.dart';
import 'package:flutter_test/flutter_test.dart';

// -- FUNCTIONS -- //

void main() {
  group('splitBlocks', () {
    test('an empty text has no blocks', () {
      expect(splitBlocks(''), isEmpty);
      expect(splitBlocks('\n\n  \n'), isEmpty);
    });

    test('splits paragraphs at blank lines and numbers the blocks', () {
      final blocks = splitBlocks('One.\nStill one.\n\nTwo.\n\n\nThree.');
      expect(blocks.map((b) => b.markdown), <String>[
        'One.\nStill one.',
        'Two.',
        'Three.',
      ]);
      expect(blocks.map((b) => b.index), <int>[0, 1, 2]);
      expect(blocks.any((b) => b.isHeading), isFalse);
    });

    test(
      'a heading is a block of its own, even with no blank line around it',
      () {
        final blocks = splitBlocks('Intro\n## Setup\nText under it');
        expect(blocks.map((b) => b.markdown), <String>[
          'Intro',
          '## Setup',
          'Text under it',
        ]);
        expect(blocks[1].level, 2);
        expect(blocks[1].heading, 'Setup');
      },
    );

    test('a blank line inside fenced code does not split it', () {
      final blocks = splitBlocks(
        'Before\n\n```sh\nline one\n\n# not a heading\n\nline two\n```\n\nAfter',
      );
      expect(blocks, hasLength(3));
      expect(blocks[1].markdown, contains('# not a heading'));
      expect(blocks[1].isHeading, isFalse);
      expect(blocks[2].markdown, 'After');
    });

    test('a tilde fence and a longer closing fence work too', () {
      final blocks = splitBlocks(
        '~~~\na\n\nb\n~~~\n\nnext\n\n````\nx\n\ny\n````',
      );
      expect(blocks, hasLength(3));
      expect(blocks[0].markdown, '~~~\na\n\nb\n~~~');
      expect(blocks[2].markdown, '````\nx\n\ny\n````');
    });

    test('a list with blank lines between its items stays one block', () {
      final blocks = splitBlocks(
        '1. First\n\n2. Second\n\n   more of second\n\n3. Third\n\nDone.',
      );
      expect(blocks, hasLength(2));
      expect(blocks[0].markdown, startsWith('1. First'));
      expect(blocks[0].markdown, contains('3. Third'));
      expect(blocks[1].markdown, 'Done.');
    });

    test('a table and a quote are one block each', () {
      final blocks = splitBlocks(
        '| a | b |\n|---|---|\n| 1 | 2 |\n\n> quoted\n> lines',
      );
      expect(blocks, hasLength(2));
      expect(blocks[0].markdown.split('\n'), hasLength(3));
    });

    test('windows line endings split the same way', () {
      final blocks = splitBlocks('# Title\r\n\r\nText\r\n');
      expect(blocks.map((b) => b.markdown), <String>['# Title', 'Text']);
    });
  });

  group('extractHeadings', () {
    test('lists the headings in order with level and plain words', () {
      final blocks = splitBlocks(
        '# **Big** title\n\ntext\n\n## A [link](http://x.y) and `code`\n\n### Deep ###\n\n####### not a heading',
      );
      final h = extractHeadings(blocks);
      expect(h.map((b) => b.level), <int?>[1, 2, 3]);
      expect(h.map((b) => b.heading), <String?>[
        'Big title',
        'A link and code',
        'Deep',
      ]);
      // The index points at the block, so the reader can scroll to it
      expect(blocks[h[1].index].markdown, startsWith('## A '));
    });

    test('a hash inside code or without a space is not a heading', () {
      final h = extractHeadings(
        splitBlocks('#tag\n\n```\n# comment\n```\n\nplain'),
      );
      expect(h, isEmpty);
    });
  });
}
