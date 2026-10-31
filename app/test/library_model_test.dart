// THE LIBRARY MODEL: THE TREE FLATTENED FOR A LAZY LIST, THE GUESS A QUEUED MOVE MAKES, AND THE COPY KEPT ON THE PHONE (BOUNDED, WIPED).

// -- DEP-MODULES -- //
import 'package:botler/core/library.dart';
import 'package:botler/core/page_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- FUNCTIONS -- //

LibraryPage _page(
  String id, {
  String? parent,
  String book = 'nb',
  String? pin,
}) => LibraryPage(
  id: id,
  notebookId: book,
  title: 'Page $id',
  parentPageId: parent,
  pinnedAt: pin,
);

PageDoc _doc(String id, {int version = 1}) => PageDoc(
  id: id,
  notebookId: 'nb',
  notebook: 'Book',
  title: 'Page $id',
  text: 'Text of $id',
  version: version,
);

void main() {
  group('flattenTree', () {
    final pages = <LibraryPage>[
      _page('a'),
      _page('a1', parent: 'a'),
      _page('a2', parent: 'a'),
      _page('b'),
      _page('orphan', parent: 'gone'),
    ];

    test('lists pages with their depth and whether they fold', () {
      final rows = flattenTree(pages, <String>{});
      expect(rows.map((r) => r.page.id), <String>[
        'a',
        'a1',
        'a2',
        'b',
        'orphan',
      ]);
      expect(rows.map((r) => r.depth), <int>[0, 1, 1, 0, 0]);
      expect(rows.map((r) => r.hasChildren), <bool>[
        true,
        false,
        false,
        false,
        false,
      ]);
    });

    test('a folded page hides its sub-pages and says it is folded', () {
      final rows = flattenTree(pages, <String>{'a'});
      expect(rows.map((r) => r.page.id), <String>['a', 'b', 'orphan']);
      expect(rows.first.collapsed, isTrue);
    });

    test('500 pages flatten at once', () {
      final many = <LibraryPage>[
        for (var i = 0; i < 500; i++)
          _page('p$i', parent: i % 10 == 0 ? null : 'p${i - i % 10}'),
      ];
      expect(flattenTree(many, <String>{}), hasLength(500));
    });
  });

  group('Library', () {
    Library library() => Library(
      notebooks: <LibraryNotebook>[
        LibraryNotebook(
          id: 'nb',
          title: 'Book',
          pages: <LibraryPage>[
            _page('a'),
            _page('a1', parent: 'a'),
            _page('b'),
          ],
        ),
        const LibraryNotebook(id: 'other', title: 'Other'),
      ],
    );

    test('a page moved to another notebook takes its sub-pages along, last in line', () {
      final moved = library().withMoved('a', toNotebookId: 'other');
      expect(moved.notebook('nb')!.pages.map((p) => p.id), <String>['b']);
      final there = moved.notebook('other')!.pages;
      expect(there.map((p) => p.id), <String>['a', 'a1']);
      expect(there.every((p) => p.notebookId == 'other'), isTrue);
    });

    test('a page moved under another parent lands after that parent', () {
      final moved = library().withMoved('b', toParentPageId: 'a');
      expect(moved.notebook('nb')!.pages.map((p) => p.id), <String>[
        'a',
        'a1',
        'b',
      ]);
      expect(moved.page('b')!.parentPageId, 'a');
    });

    test(
      'pinned pages come newest pin first, and notebooks sort pinned first',
      () {
        final l = Library(
          notebooks: <LibraryNotebook>[
            LibraryNotebook(
              id: '1',
              title: 'Zed',
              pages: <LibraryPage>[_page('x', pin: '2026-01-01')],
            ),
            const LibraryNotebook(id: '2', title: 'Alpha'),
            const LibraryNotebook(
              id: '3',
              title: 'Mid',
              pinnedAt: '2026-02-01',
            ),
          ],
        );
        expect(l.sorted.map((n) => n.id), <String>['3', '2', '1']);
        expect(l.pinnedPages.map((p) => p.id), <String>['x']);
      },
    );

    test(
      'the Botler updated mark needs a page Botler wrote and nobody looked at',
      () {
        const seen = LibraryPage(
          id: 'a',
          notebookId: 'n',
          title: 't',
          version: 3,
          seenVersion: 3,
          updatedBy: 'agent',
        );
        const fresh = LibraryPage(
          id: 'b',
          notebookId: 'n',
          title: 't',
          version: 3,
          seenVersion: 2,
          updatedBy: 'agent',
        );
        const mine = LibraryPage(
          id: 'c',
          notebookId: 'n',
          title: 't',
          version: 3,
        );
        expect(seen.botlerUpdated, isFalse);
        expect(fresh.botlerUpdated, isTrue);
        expect(mine.botlerUpdated, isFalse);
      },
    );

    test(
      'it survives being written to the phone and read back, marked offline',
      () {
        final back = Library.fromCache(library().toJson());
        expect(back.offline, isTrue);
        expect(back.notebooks.first.pages.map((p) => p.id), <String>[
          'a',
          'a1',
          'b',
        ]);
        expect(back.cachedAt, isNotNull);
      },
    );
  });

  group('PageCache', () {
    Future<PageCache> cache() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      return PageCache(await SharedPreferences.getInstance());
    }

    test('keeps a page and gives it back marked offline', () async {
      final c = await cache();
      await c.savePage(_doc('a', version: 4));
      final back = c.page('a')!;
      expect(back.offline, isTrue);
      expect(back.text, 'Text of a');
      expect(c.cachedVersion('a'), 4);
      expect(c.page('missing'), isNull);
    });

    test(
      'holds at most $maxCachedPages pages, the one used longest ago going first',
      () async {
        final c = await cache();
        for (var i = 0; i < maxCachedPages; i++) {
          await c.savePage(_doc('p$i'));
        }
        // Saving p0 again makes it the newest
        await c.savePage(_doc('p0', version: 2));
        await c.savePage(_doc('extra'));
        expect(c.cachedIds(), hasLength(maxCachedPages));
        expect(c.page('p1'), isNull);
        expect(c.page('p0'), isNotNull);
        expect(c.page('extra'), isNotNull);
      },
    );

    test('saves made at the same moment all stay in the index', () async {
      final c = await cache();
      await Future.wait(<Future<void>>[
        for (var i = 0; i < 10; i++) c.savePage(_doc('p$i')),
      ]);
      expect(c.cachedIds().toSet(), <String>{
        for (var i = 0; i < 10; i++) 'p$i',
      });
    });

    test('forgets one page, and wipes everything of the library', () async {
      final c = await cache();
      await c.saveLibrary(const Library());
      await c.savePage(_doc('a'));
      await c.savePage(_doc('b'));
      await c.saveRecents(<RecentPage>[
        RecentPage(id: 'a', title: 't', notebook: 'n', at: DateTime(2026)),
      ]);
      await c.forgetPage('a');
      expect(c.page('a'), isNull);
      expect(c.page('b'), isNotNull);
      await c.wipe();
      expect(c.library(), isNull);
      expect(c.page('b'), isNull);
      expect(c.recents(), isEmpty);
    });

    test('recents are bounded', () async {
      final c = await cache();
      await c.saveRecents(<RecentPage>[
        for (var i = 0; i < maxRecents + 5; i++)
          RecentPage(id: '$i', title: 't', notebook: 'n', at: DateTime(2026)),
      ]);
      expect(c.recents(), hasLength(maxRecents));
    });
  });
}
