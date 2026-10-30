// THE PURE PARTS AROUND A PAGE: THE LINE DIFF, THE LINE NUMBERS OF READER BLOCKS, FINDING THE SEARCHED WORDS, LOOKING UP A [[LINK]], THE MARKDOWN THE
// TOOLBAR WRITES, THE EXPORT TEXT, MOVING A PAGE IN THE OUTLINE, AND TIME WORDS. No widgets and no network.

// -- DEP-MODULES -- //
import 'package:botler/core/library.dart';
import 'package:botler/core/library_extras.dart';
import 'package:botler/core/line_diff.dart';
import 'package:botler/features/memory/markdown_edit.dart';
import 'package:botler/features/notebooks/notebook_export.dart';
import 'package:botler/features/notebooks/page_links.dart';
import 'package:botler/features/notebooks/reader_blocks.dart';
import 'package:botler/features/notebooks/reader_links.dart';
import 'package:botler/features/notebooks/term_highlight.dart';
import 'package:botler/state/library_extras.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// -- FUNCTIONS -- //

LibraryPage page(
  String id,
  String title, {
  String book = 'nb-1',
  String? parent,
  int version = 1,
  String by = 'user',
}) => LibraryPage(
  id: id,
  notebookId: book,
  title: title,
  parentPageId: parent,
  version: version,
  updatedBy: by,
);

Library sample() => Library(
  notebooks: <LibraryNotebook>[
    LibraryNotebook(
      id: 'nb-1',
      title: 'Home manual',
      pages: <LibraryPage>[
        page('p-1', 'Wi-Fi'),
        page('p-2', 'Router', parent: 'p-1'),
        page('p-3', 'Boiler'),
        page('p-5', 'A/B'),
      ],
    ),
    LibraryNotebook(
      id: 'nb-2',
      title: 'Trip to Japan',
      pages: <LibraryPage>[
        page('p-4', 'Flights', book: 'nb-2'),
        page('p-6', 'Boiler', book: 'nb-2'),
      ],
    ),
  ],
);

TextEditingValue at(String text, int a, [int? b]) => TextEditingValue(
  text: text,
  selection: TextSelection(baseOffset: a, extentOffset: b ?? a),
);

void main() {
  group('the line diff', () {
    test('a line the new text has and the old text lacks is added', () {
      expect(addedLines('one\ntwo\n', 'one\ntwo\nthree\n'), <int>{2});
    });

    test('a moved line is not new, and a repeated line is new once', () {
      expect(addedLines('a\nb\nc', 'c\na\nb'), isEmpty);
      expect(addedLines('a\nb', 'a\nb\na'), <int>{2});
      expect(addedLines('a\na\nb', 'a\na\na\nb'), <int>{2});
    });

    test('blank lines, trailing spaces and line ends do not count', () {
      expect(addedLines('a\r\nb', 'a  \n\n\nb\n'), isEmpty);
      expect(addedLines('', 'x'), <int>{0});
    });

    test('removed lines add nothing', () {
      expect(addedLines('a\nb\nc', 'a\nc'), isEmpty);
    });

    test('touchesAdded looks at the lines of a block only', () {
      expect(touchesAdded(<int>{4}, 3, 2), isTrue);
      expect(touchesAdded(<int>{4}, 5, 2), isFalse);
      expect(touchesAdded(<int>{}, 0, 9), isFalse);
    });
  });

  group('reader blocks know their lines', () {
    test('a block starts at its first line and spans its lines', () {
      final blocks = splitBlocks('# Title\n\nfirst\nsecond\n\n- a\n- b\n');
      expect(blocks.map((b) => b.line), <int>[0, 2, 5]);
      expect(blocks.map((b) => b.lineCount), <int>[1, 2, 2]);
    });

    test('a fenced block keeps the blank lines inside it', () {
      final blocks = splitBlocks('text\n\n```\na\n\nb\n```\n\nafter');
      expect(blocks[1].line, 2);
      expect(blocks[1].lineCount, 5);
      expect(blocks[2].line, 8);
    });
  });

  group('the words a search found', () {
    test('are marked whatever their case', () {
      final runs = splitByTerm('The Router is in the hall', 'router');
      expect(runs.map((r) => r.text), <String>[
        'The ',
        'Router',
        ' is in the hall',
      ]);
      expect(runs.map((r) => r.match), <bool>[false, true, false]);
    });

    test('every place is marked, and no term marks nothing', () {
      expect(splitByTerm('aXbxc', 'x').where((r) => r.match).length, 2);
      expect(splitByTerm('abc', ' ').single.match, isFalse);
      expect(splitByTerm('', 'a'), isEmpty);
    });
  });

  group('[[links]] are looked up in the library', () {
    final lib = sample();
    PageLink link(String page, [String? book]) =>
        PageLink(start: 0, end: 1, page: page, notebook: book);

    test('the current notebook first, ignoring case', () {
      expect(resolvePageLink(lib, link('boiler'), 'nb-1')!.id, 'p-3');
      expect(resolvePageLink(lib, link('Boiler'), 'nb-2')!.id, 'p-6');
    });

    test('another notebook only when one page has the title', () {
      expect(resolvePageLink(lib, link('Flights'), 'nb-1')!.id, 'p-4');
      expect(resolvePageLink(lib, link('Boiler'), 'nb-9'), isNull);
    });

    test('Notebook/Page names the notebook', () {
      expect(
        resolvePageLink(lib, link('Boiler', 'Trip to Japan'), 'nb-1')!.id,
        'p-6',
      );
      expect(
        resolvePageLink(lib, link('Nope', 'Trip to Japan'), 'nb-1'),
        isNull,
      );
    });

    test('a page whose own title holds a slash is found', () {
      expect(resolvePageLink(lib, link('B', 'A'), 'nb-1')!.id, 'p-5');
    });

    test('an unknown page is null', () {
      expect(resolvePageLink(lib, link('Nothing'), 'nb-1'), isNull);
    });

    test(
      'linkifyPages writes known and unknown links, and leaves code alone',
      () {
        final out = linkifyPages(
          'See [[Boiler]], [[Trip to Japan/Flights]] and [[Nothing]] but `[[Boiler]]` stays.',
          lib,
          'nb-1',
        );
        expect(
          out,
          contains(
            '[Boiler]($pageHrefPrefix'
            'p-3)',
          ),
        );
        expect(
          out,
          contains(
            '[Trip to Japan/Flights]($pageHrefPrefix'
            'p-4)',
          ),
        );
        expect(out, contains('${missingOpen}Nothing$missingClose'));
        expect(out, contains('`[[Boiler]]` stays'));
        expect(pageIdOfHref('${pageHrefPrefix}p-3'), 'p-3');
        expect(pageIdOfHref('https://x.test'), isNull);
      },
    );

    test('a fenced block is not linked, and marks in a title are escaped', () {
      expect(
        linkifyPages('```\n[[Boiler]]\n```', lib, 'nb-1'),
        '```\n[[Boiler]]\n```',
      );
      expect(
        linkifyPages('[[Nothing_here*]]', lib, 'nb-1'),
        '${missingOpen}Nothing_here*$missingClose',
      );
    });
  });

  group('the toolbar edits', () {
    test('a heading mark goes on the line and comes off again', () {
      final on = applyMarkdownEdit(at('a\nbee', 4), MarkdownEdit.heading);
      expect(on.text, 'a\n## bee');
      expect(on.selection.baseOffset, 7);
      final off = applyMarkdownEdit(on, MarkdownEdit.heading);
      expect(off.text, 'a\nbee');
    });

    test('a list item becomes a checkbox when the other button is tapped', () {
      final list = applyMarkdownEdit(at('milk', 0), MarkdownEdit.list);
      expect(list.text, '- milk');
      final box = applyMarkdownEdit(list, MarkdownEdit.checkbox);
      expect(box.text, '- [ ] milk');
    });

    test('bold wraps the selection, or waits between the stars', () {
      final wrapped = applyMarkdownEdit(
        at('a word b', 2, 6),
        MarkdownEdit.bold,
      );
      expect(wrapped.text, 'a **word** b');
      expect(wrapped.selection.start, 4);
      expect(wrapped.selection.end, 8);
      final empty = applyMarkdownEdit(at('', 0), MarkdownEdit.bold);
      expect(empty.text, '****');
      expect(empty.selection.baseOffset, 2);
    });

    test('a page link wraps the words in double brackets', () {
      final v = applyMarkdownEdit(
        at('go Boiler now', 3, 9),
        MarkdownEdit.pageLink,
      );
      expect(v.text, 'go [[Boiler]] now');
    });

    test('a link keeps the words and selects the address to type', () {
      final v = applyMarkdownEdit(at('see site', 4, 8), MarkdownEdit.link);
      expect(v.text, 'see [site](https://)');
      expect(v.text.substring(v.selection.start, v.selection.end), 'https://');
      expect(
        applyMarkdownEdit(at('', 0), MarkdownEdit.link).text,
        '[](https://)',
      );
    });

    test('a selection that is not valid still edits at the end', () {
      final v = applyMarkdownEdit(
        const TextEditingValue(text: 'ab'),
        MarkdownEdit.list,
      );
      expect(v.text, '- ab');
    });
  });

  group('the notebook as Markdown', () {
    test(
      'has the title, each page as a heading and sub-pages one level down',
      () {
        final text = notebookMarkdown('Home manual', const <ExportPage>[
          ExportPage('Wi-Fi', 0, 'The router is in the hall.\n'),
          ExportPage('Router', 1, 'Admin page.'),
          ExportPage('Empty', 0, ''),
        ]);
        expect(
          text,
          '# Home manual\n\n## Wi-Fi\n\nThe router is in the hall.\n\n### Router\n\nAdmin page.\n\n## Empty\n',
        );
      },
    );
  });

  group('moving a page in the outline', () {
    test('siblings are the pages next to it under the same parent', () {
      final lib = sample();
      expect(lib.siblings(lib.page('p-3')!).map((p) => p.id), <String>[
        'p-1',
        'p-3',
        'p-5',
      ]);
      expect(lib.siblings(lib.page('p-2')!).map((p) => p.id), <String>['p-2']);
    });

    test('a position puts the page before the sibling that is there', () {
      final lib = sample().withMoved('p-3', position: 0);
      expect(lib.notebook('nb-1')!.pages.map((p) => p.id), <String>[
        'p-3',
        'p-1',
        'p-2',
        'p-5',
      ]);
    });

    test('moving down one place', () {
      final lib = sample().withMoved('p-1', position: 1);
      expect(lib.notebook('nb-1')!.pages.map((p) => p.id), <String>[
        'p-3',
        'p-1',
        'p-2',
        'p-5',
      ]);
    });

    test('a move to another notebook goes last there', () {
      final lib = sample().withMoved('p-3', toNotebookId: 'nb-2');
      expect(lib.notebook('nb-2')!.pages.last.id, 'p-3');
      expect(lib.notebook('nb-1')!.pages.any((p) => p.id == 'p-3'), isFalse);
    });
  });

  group('time words and undo rules', () {
    final now = DateTime.utc(2026, 10, 30, 12);

    test('the largest whole unit', () {
      expect(agoOf(now.subtract(const Duration(seconds: 20)), now).unit, 'now');
      final m = agoOf(now.subtract(const Duration(minutes: 5)), now);
      expect((m.unit, m.count), ('minutes', 5));
      final h = agoOf(now.subtract(const Duration(hours: 3)), now);
      expect((h.unit, h.count), ('hours', 3));
      final d = agoOf(now.subtract(const Duration(days: 2, hours: 5)), now);
      expect((d.unit, d.count), ('days', 2));
    });

    test('days left of the 30 never go below zero', () {
      expect(daysLeftToRestore(now.subtract(const Duration(days: 5)), now), 25);
      expect(daysLeftToRestore(now.subtract(const Duration(days: 45)), now), 0);
    });

    test('a change can be undone only while it is the newest version', () {
      final entry = ActivityEntry(
        pageId: 'p-1',
        notebookId: 'nb-1',
        notebook: 'Home manual',
        page: 'Wi-Fi',
        version: 2,
        updatedAt: now,
        textChanged: true,
      );
      Library with_(int version, String by) => Library(
        notebooks: <LibraryNotebook>[
          LibraryNotebook(
            id: 'nb-1',
            title: 'Home manual',
            pages: <LibraryPage>[
              page('p-1', 'Wi-Fi', version: version, by: by),
            ],
          ),
        ],
      );
      expect(canUndoChange(entry, with_(2, 'agent')), isTrue);
      expect(canUndoChange(entry, with_(3, 'user')), isFalse);
      expect(canUndoChange(entry, with_(3, 'agent')), isFalse);
      expect(canUndoChange(entry, with_(2, 'user')), isFalse);
      expect(canUndoChange(entry, null), isFalse);
      expect(canUndoChange(entry, Library()), isFalse);
      expect(entry.created, isFalse);
      // A rename or a move by Botler is neither a creation nor a text change: view only, whatever the version
      final renamed = ActivityEntry(
        pageId: 'p-1',
        notebookId: 'nb-1',
        notebook: 'Home manual',
        page: 'Wi-Fi',
        version: 2,
        updatedAt: now,
      );
      expect(canUndoChange(renamed, with_(2, 'agent')), isFalse);
      // A page Botler made is undone (deleted) only while it is still at that version
      final made = ActivityEntry(
        pageId: 'p-1',
        notebookId: 'nb-1',
        notebook: 'Home manual',
        page: 'Wi-Fi',
        version: 1,
        updatedAt: now,
        created: true,
      );
      expect(canUndoChange(made, with_(1, 'agent')), isTrue);
      expect(canUndoChange(made, with_(2, 'agent')), isFalse);
      // The answer of an older server has neither flag
      final old = ActivityEntry.fromJson(<String, Object?>{
        'pageId': 'p-1',
        'version': 1,
      });
      expect(old.undoable, isFalse);
    });
  });
}
