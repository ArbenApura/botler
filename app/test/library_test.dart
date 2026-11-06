// THE LIBRARY, A NOTEBOOK'S PAGE TREE AND THE READER: WHAT EACH SHOWS, THE STATES (LOADING FAILED, EMPTY, OFFLINE COPY, OLDER SERVER, PAGE GONE), PIN AND
// RENAME AND DELETE, A CHANGE MADE OFFLINE KEPT IN THE OUTBOX, THE CONTENTS DRAWER JUMPING TO A HEADING, AND THE EDITOR SAVING THROUGH THE PAGE VERBS.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/outbox.dart';
import 'package:botler/core/page_cache.dart';
import 'package:botler/core/reminders.dart';
import 'package:botler/features/notebooks/library_screen.dart';
import 'package:botler/features/notebooks/library_widgets.dart';
import 'package:botler/features/notebooks/notebook_pages_screen.dart';
import 'package:botler/features/notebooks/page_reader.dart';
import 'package:botler/features/notebooks/page_tree.dart';
import 'package:botler/state/library.dart';
import 'package:botler/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'library_fake.dart';

// -- FUNCTIONS -- //

/// A page of many sections, long enough that most of it is not built at once.
FakeLibrary longManual({int sections = 60}) => FakeLibrary(
  books: <FakeNotebook>[FakeNotebook('nb-1', 'Manual')],
  pages: <FakePage>[
    FakePage(
      'p-1',
      'nb-1',
      'Everything',
      text: [
        for (var i = 1; i <= sections; i++)
          '## Section $i\n\nFirst paragraph of section $i with a few words to fill a line.\n\nSecond paragraph of section $i with a few words to fill a line.',
      ].join('\n\n'),
    ),
  ],
);

/// A screen with one button that opens a page in the reader, so the reader has a screen under it to go back to.
class _Launcher extends StatelessWidget {
  const _Launcher(this.pageId);

  final String pageId;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => openPage(context, pageId),
        child: const Text('launch'),
      ),
    ),
  );
}

/// The Semantics widget that carries this label (the breadcrumb).
Finder labelled(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

Finder rich(String text) => find.text(text, findRichText: true);

Future<void> tapMore(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  group('the library', () {
    testWidgets(
      'lists the main notebook first, then pinned pages, then the notebooks',
      (tester) async {
        final fake = sampleLibrary()
          ..page('p-3')!.pinnedAt = '2026-10-30T02:00:00.000Z';
        await pumpLibrary(tester, fake, const LibraryScreen());
        expect(find.text('Main notebook'), findsOneWidget);
        expect(find.text('Pinned and recent'), findsOneWidget);
        expect(find.text('Boiler'), findsOneWidget);
        expect(find.text('3 pages'), findsOneWidget);
        expect(find.text('1 page'), findsOneWidget);
        expect(find.text('Flights and hotels'), findsOneWidget);
        double top(String text) => tester.getTopLeft(find.text(text)).dy;
        expect(top('Main notebook'), lessThan(top('Pinned and recent')));
        expect(top('Pinned and recent'), lessThan(top('Trip to Japan')));
        // Botler wrote in Home manual and nobody looked yet: one dot, on that notebook
        expect(find.byType(UpdatedDot), findsWidgets);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('notebook.nb-2')),
            matching: find.byType(UpdatedDot),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('notebook.nb-1')),
            matching: find.byType(UpdatedDot),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('search is the one primary action; the rest is in the menu', (
      tester,
    ) async {
      await pumpLibrary(tester, sampleLibrary(), const LibraryScreen());
      expect(find.text('Search your notebooks'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Ask Botler to file something'), findsOneWidget);
      expect(find.text('New notebook'), findsOneWidget);
      expect(find.text('Deleted notebooks'), findsOneWidget);
      expect(
        find.text('Copy everything (notebook and money) as text'),
        findsOneWidget,
      );
    });

    testWidgets('says to ask Botler for one when there are no notebooks', (
      tester,
    ) async {
      await pumpLibrary(tester, FakeLibrary(), const LibraryScreen());
      expect(
        find.text(
          'No notebooks yet. Ask Botler to start one for a trip, a project or a list.',
        ),
        findsOneWidget,
      );
      // The main notebook is always there
      expect(find.text('Main notebook'), findsOneWidget);
    });

    testWidgets('a failed load says so and a retry loads it', (tester) async {
      final fake = sampleLibrary()..broken = true;
      await pumpLibrary(tester, fake, const LibraryScreen());
      expect(find.text('Something went wrong'), findsOneWidget);
      fake.broken = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Home manual'), findsOneWidget);
    });

    testWidgets('with no connection it shows the copy kept on the phone', (
      tester,
    ) async {
      final fake = sampleLibrary();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await pumpLibrary(tester, fake, const LibraryScreen(), prefs: prefs);
      expect(find.textContaining('Offline copy'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      fake.offline = true;
      await pumpLibrary(tester, fake, const LibraryScreen(), prefs: prefs);
      expect(find.textContaining('Offline copy'), findsOneWidget);
      expect(find.text('Home manual'), findsOneWidget);
      expect(find.text('Trip to Japan'), findsOneWidget);
    });

    testWidgets('an older server gets a plain "update the server" message', (
      tester,
    ) async {
      final fake = sampleLibrary()..oldServer = true;
      await pumpLibrary(tester, fake, const LibraryScreen());
      expect(find.textContaining('Update the server'), findsOneWidget);
      expect(find.text('Home manual'), findsNothing);
    });

    testWidgets('lists recent pages and forgets the ones the server lost', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'library.recents.v1': jsonEncode(<Object?>[
          <String, Object?>{
            'id': 'p-4',
            'title': 'Flights',
            'notebook': 'Trip to Japan',
            'at': '2026-10-30T01:00:00.000Z',
          },
          <String, Object?>{
            'id': 'gone-1',
            'title': 'Old page',
            'notebook': 'Trip to Japan',
            'at': '2026-10-29T01:00:00.000Z',
          },
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      await pumpLibrary(
        tester,
        sampleLibrary(),
        const LibraryScreen(),
        prefs: prefs,
      );
      expect(
        find.byKey(const ValueKey<String>('shortcut.p-4')),
        findsOneWidget,
      );
      expect(find.text('Old page'), findsNothing);
      expect(PageCache(prefs).recents().map((r) => r.id), <String>['p-4']);
    });

    testWidgets('the main notebook is one tap away and keeps its own editor', (
      tester,
    ) async {
      await pumpLibrary(tester, sampleLibrary(), const LibraryScreen());
      await tester.tap(find.text('Main notebook'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Edit'), findsOneWidget);
    });

    testWidgets('a long press on a notebook offers pin, name and delete', (
      tester,
    ) async {
      final fake = sampleLibrary();
      await pumpLibrary(tester, fake, const LibraryScreen());
      await tester.longPress(find.text('Trip to Japan'));
      await tester.pumpAndSettle();
      expect(find.text('Pin'), findsOneWidget);
      expect(find.text('Name and summary'), findsOneWidget);
      expect(find.text('Delete notebook'), findsOneWidget);
      await tester.tap(find.text('Pin'));
      await tester.pumpAndSettle();
      final sent = fake.of('notebook_pin').single;
      expect(sent.body, <String, Object?>{
        'notebookId': 'nb-2',
        'pinned': true,
      });
      expect(sent.key, isNotNull);
      // Pinned notebooks come first
      expect(
        tester.getTopLeft(find.text('Trip to Japan')).dy,
        lessThan(tester.getTopLeft(find.text('Home manual')).dy),
      );
    });

    testWidgets('search finds a page and opens it', (tester) async {
      final fake = sampleLibrary();
      await pumpLibrary(tester, fake, const LibraryScreen());
      await tester.tap(find.text('Search your notebooks'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Type at least two letters'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'flights');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(fake.of('notebook_search').single.body['query'], 'flights');
      await tester.tap(find.byKey(const ValueKey<String>('result.p-4')));
      await tester.pumpAndSettle();
      expect(rich('Leave on 3 March.'), findsOneWidget);
    });
  });

  group('a notebook', () {
    testWidgets(
      'shows its pages as a tree with a primary action to open the first',
      (tester) async {
        await pumpLibrary(
          tester,
          sampleLibrary(),
          const NotebookPagesScreen(notebookId: 'nb-1'),
        );
        expect(find.text('Home manual'), findsOneWidget);
        expect(find.text('Wi-Fi'), findsOneWidget);
        expect(find.text('Router settings'), findsOneWidget);
        expect(find.text('Boiler'), findsOneWidget);
        expect(find.text('3 pages'), findsOneWidget);
        expect(find.text('How things work here'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, 'Open the first page'),
          findsOneWidget,
        );
        expect(find.byType(FilledButton), findsOneWidget);
        // A sub-page sits further in than its parent
        expect(
          tester.getTopLeft(find.text('Router settings')).dx,
          greaterThan(tester.getTopLeft(find.text('Wi-Fi')).dx),
        );
      },
    );

    testWidgets('a parent folds its sub-pages away and back', (tester) async {
      await pumpLibrary(
        tester,
        sampleLibrary(),
        const NotebookPagesScreen(notebookId: 'nb-1'),
      );
      await tester.tap(find.byKey(const ValueKey<String>('fold.p-1')));
      await tester.pumpAndSettle();
      expect(find.text('Router settings'), findsNothing);
      expect(find.text('Boiler'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('fold.p-1')));
      await tester.pumpAndSettle();
      expect(find.text('Router settings'), findsOneWidget);
    });

    testWidgets('500 pages are built row by row, not all at once', (
      tester,
    ) async {
      final fake = FakeLibrary(
        books: <FakeNotebook>[FakeNotebook('nb-1', 'Big')],
        pages: <FakePage>[
          for (var i = 0; i < 500; i++)
            FakePage('p-$i', 'nb-1', 'Page number $i'),
        ],
      );
      await pumpLibrary(
        tester,
        fake,
        const NotebookPagesScreen(notebookId: 'nb-1'),
      );
      final built = find.byType(PageTreeRow).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(40));
      await tester.scrollUntilVisible(
        find.text('Page number 499'),
        400,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 200,
      );
      expect(find.text('Page number 499'), findsOneWidget);
    });

    testWidgets('the first page opens in the reader', (tester) async {
      await pumpLibrary(
        tester,
        sampleLibrary(),
        const NotebookPagesScreen(notebookId: 'nb-1'),
      );
      await tester.tap(find.text('Open the first page'));
      await tester.pumpAndSettle();
      expect(rich('The router is in the hall.'), findsOneWidget);
    });

    testWidgets(
      'a long press offers rename, pin and delete, and pin goes to the server',
      (tester) async {
        final fake = sampleLibrary();
        await pumpLibrary(
          tester,
          fake,
          const NotebookPagesScreen(notebookId: 'nb-1'),
        );
        await tester.longPress(find.text('Boiler'));
        await tester.pumpAndSettle();
        expect(find.text('Rename'), findsOneWidget);
        expect(find.text('Pin'), findsOneWidget);
        expect(find.text('Delete page'), findsOneWidget);
        await tester.tap(find.text('Pin'));
        await tester.pumpAndSettle();
        final sent = fake.of('page_pin').single;
        expect(sent.body, <String, Object?>{'pageId': 'p-3', 'pinned': true});
        expect(sent.key, isNotNull);
        expect(sent.key!.length, greaterThanOrEqualTo(8));
        expect(find.byIcon(Icons.push_pin), findsOneWidget);
      },
    );

    testWidgets('renames a page', (tester) async {
      final fake = sampleLibrary();
      await pumpLibrary(
        tester,
        fake,
        const NotebookPagesScreen(notebookId: 'nb-1'),
      );
      await tester.longPress(find.text('Boiler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Heating');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(fake.of('page_rename').single.body, <String, Object?>{
        'pageId': 'p-3',
        'newTitle': 'Heating',
      });
      expect(find.text('Heating'), findsOneWidget);
      expect(find.text('Boiler'), findsNothing);
    });

    testWidgets('deletes a page only after a confirm', (tester) async {
      final fake = sampleLibrary();
      await pumpLibrary(
        tester,
        fake,
        const NotebookPagesScreen(notebookId: 'nb-1'),
      );
      await tester.longPress(find.text('Boiler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete page'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this page?'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(fake.of('page_delete'), isEmpty);
      await tester.longPress(find.text('Boiler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete page'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete page'));
      await tester.pumpAndSettle();
      expect(fake.of('page_delete').single.body['pageId'], 'p-3');
      expect(find.text('Boiler'), findsNothing);
    });

    testWidgets('a new page is made with a title and opens in the reader', (
      tester,
    ) async {
      final fake = sampleLibrary();
      await pumpLibrary(
        tester,
        fake,
        const NotebookPagesScreen(notebookId: 'nb-1'),
      );
      await tapMore(tester, 'New page');
      await tester.enterText(find.byType(TextField), 'Garage code');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      final sent = fake.of('page_create').single.body;
      expect(sent['notebookId'], 'nb-1');
      expect(sent['title'], 'Garage code');
      expect(find.textContaining('This page is empty'), findsOneWidget);
    });

    testWidgets('a notebook deleted while open says it is gone', (
      tester,
    ) async {
      final fake = sampleLibrary();
      final container = await pumpLibrary(
        tester,
        fake,
        const NotebookPagesScreen(notebookId: 'nb-2'),
      );
      expect(find.text('Flights'), findsOneWidget);
      fake.books.removeWhere((b) => b.id == 'nb-2');
      container.invalidate(libraryProvider);
      await tester.pumpAndSettle();
      expect(find.text('This notebook is gone'), findsOneWidget);
    });

    testWidgets('an empty notebook says so and offers no page to open', (
      tester,
    ) async {
      final fake = FakeLibrary(
        books: <FakeNotebook>[FakeNotebook('nb-1', 'Empty')],
      );
      await pumpLibrary(
        tester,
        fake,
        const NotebookPagesScreen(notebookId: 'nb-1'),
      );
      expect(find.textContaining('No pages yet'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets(
      'a pin made with no connection waits in the outbox and shows at once',
      (tester) async {
        final fake = sampleLibrary();
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        await pumpLibrary(
          tester,
          fake,
          const NotebookPagesScreen(notebookId: 'nb-1'),
          prefs: prefs,
        );
        fake.offline = true;
        await tester.longPress(find.text('Boiler'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pin'));
        await tester.pumpAndSettle();
        expect(find.textContaining('kept on your phone'), findsOneWidget);
        final waiting = Outbox(prefs).items();
        expect(waiting, hasLength(1));
        expect(waiting.single.verb, 'page_pin');
        expect(waiting.single.args, <String, Object?>{
          'pageId': 'p-3',
          'pinned': true,
        });
        // The send that failed carried the very id the outbox keeps
        expect(fake.of('page_pin').single.key, waiting.single.key);
        expect(find.byIcon(Icons.push_pin), findsOneWidget);
        expect(find.textContaining('Offline copy'), findsOneWidget);
      },
    );
  });

  group('the outbox and the pages', () {
    test(
      'a queued pin goes out under the same request id when the phone is back',
      () async {
        final fake = sampleLibrary()..offline = true;
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            prefsProvider.overrideWithValue(prefs),
            apiProvider.overrideWithValue(fake.api),
          ],
        );
        addTearDown(container.dispose);
        final result = await container
            .read(libraryActionsProvider)
            .pinPage('p-3', pinned: true);
        expect(result, WriteResult.queued);
        final key = container.read(outboxProvider).items().single.key;
        fake.offline = false;
        await flushAndSync(container);
        expect(container.read(outboxProvider).length, 0);
        expect(fake.of('page_pin').map((c) => c.key), <String?>[key, key]);
        expect(fake.page('p-3')!.pinnedAt, isNotNull);
      },
    );

    test('a queued move aimed at a deleted page is kept in the failed list and the tree is read again', () async {
      final fake = sampleLibrary();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          apiProvider.overrideWithValue(fake.api),
        ],
      );
      addTearDown(container.dispose);
      container.listen(libraryProvider, (_, _) {}, fireImmediately: true);
      await container.read(libraryProvider.future);
      expect(container.read(libraryProvider).value!.page('p-3'), isNotNull);
      await container.read(outboxProvider).add('page_move', <String, Object?>{
        'pageId': 'p-3',
        'toNotebookId': 'nb-2',
      });
      // Botler deleted the page before the move could be sent
      fake.page('p-3')!.deleted = true;
      final readsBefore = fake.of('notebook_outline').length;
      await flushAndSync(container);
      final failed = container.read(outboxProvider).failed();
      expect(failed, hasLength(1));
      expect(failed.single.verb, 'page_move');
      expect(failed.single.reason, 'The page is gone.');
      expect(container.read(outboxProvider).length, 0);
      await container.read(libraryProvider.future);
      expect(fake.of('notebook_outline').length, greaterThan(readsBefore));
      expect(container.read(libraryProvider).value!.page('p-3'), isNull);
    });

    test('a pin that fails for a reason other than the network is thrown, not queued', () async {
      final fake = sampleLibrary();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          apiProvider.overrideWithValue(fake.api),
        ],
      );
      addTearDown(container.dispose);
      await expectLater(
        container.read(libraryActionsProvider).pinPage('nope', pinned: true),
        throwsA(isA<Exception>()),
      );
      expect(container.read(outboxProvider).length, 0);
    });
  });

  group('the reader', () {
    testWidgets(
      'shows the breadcrumb, the text, and Edit as the one primary action',
      (tester) async {
        final fake = sampleLibrary();
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        await pumpLibrary(
          tester,
          fake,
          const PageReaderScreen(pageId: 'p-1'),
          prefs: prefs,
        );
        expect(rich('The router is in the hall.'), findsOneWidget);
        expect(rich('Hold the button.'), findsOneWidget);
        // The breadcrumb names the notebook and the page
        expect(find.text('Home manual'), findsOneWidget);
        expect(labelled('Page Home manual > Wi-Fi'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Edit'), findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Contents'), findsOneWidget);
        // The sub-page is listed under the text
        expect(find.text('Sub-pages'), findsOneWidget);
        expect(find.text('Router settings'), findsOneWidget);
        // Looked at: the server is told which version, fire and forget, and the page is a recent one
        expect(fake.of('page_seen').single.body, <String, Object?>{
          'pageId': 'p-1',
          'version': 2,
        });
        expect(PageCache(prefs).recents().map((r) => r.id), <String>['p-1']);
        expect(PageCache(prefs).page('p-1'), isNotNull);
      },
    );

    testWidgets('a picture in the text is never loaded', (tester) async {
      final fake = FakeLibrary(
        books: <FakeNotebook>[FakeNotebook('nb-1', 'Book')],
        pages: <FakePage>[
          FakePage(
            'p-1',
            'nb-1',
            'Pic',
            text: 'Before\n\n![x](https://evil.test/a.png)\n\nAfter',
          ),
        ],
      );
      await pumpLibrary(tester, fake, const PageReaderScreen(pageId: 'p-1'));
      expect(find.byType(Image), findsNothing);
      expect(rich('After'), findsOneWidget);
    });

    testWidgets('the contents drawer jumps to a heading far down the page', (
      tester,
    ) async {
      await pumpLibrary(
        tester,
        longManual(),
        const PageReaderScreen(pageId: 'p-1'),
      );
      // Section 50 is not built yet
      expect(rich('Section 50'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Contents'));
      await tester.pumpAndSettle();
      final drawerList = find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('contents.${50 * 3 - 3}')),
        200,
        scrollable: drawerList,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('contents.${50 * 3 - 3}')),
      );
      await tester.pumpAndSettle();
      // The drawer is closed and the heading is near the top of the reader
      expect(find.byType(Drawer), findsNothing);
      final heading = find.descendant(
        of: find.byType(ListView),
        matching: rich('Section 50'),
      );
      expect(heading, findsOneWidget);
      expect(tester.getTopLeft(heading).dy, lessThan(200));
      // And back up to the first one
      await tester.tap(find.widgetWithText(TextButton, 'Contents'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('contents.0')));
      await tester.pumpAndSettle();
      expect(rich('Section 1'), findsOneWidget);
      expect(tester.getTopLeft(rich('Section 1')).dy, lessThan(200));
    });

    testWidgets(
      'the contents still jump after the text changed under the reader',
      (tester) async {
        final fake = longManual();
        final container = await pumpLibrary(
          tester,
          fake,
          const PageReaderScreen(pageId: 'p-1'),
        );
        // Another writer changes the text and the reader reads the page again
        final page = fake.page('p-1')!;
        page
          ..text = page.text.replaceFirst(
            'First paragraph',
            'Changed paragraph',
          )
          ..version += 1;
        container.invalidate(pageProvider('p-1'));
        await tester.pumpAndSettle();
        expect(rich('Section 50'), findsNothing);
        await tester.tap(find.widgetWithText(TextButton, 'Contents'));
        await tester.pumpAndSettle();
        final drawerList = find.descendant(
          of: find.byType(Drawer),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey<String>('contents.${50 * 3 - 3}')),
          200,
          scrollable: drawerList,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('contents.${50 * 3 - 3}')),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(ListView),
            matching: rich('Section 50'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('a swipe from the right edge opens the contents too', (
      tester,
    ) async {
      await pumpLibrary(
        tester,
        longManual(sections: 3),
        const PageReaderScreen(pageId: 'p-1'),
      );
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      await tester.dragFrom(Offset(size.width - 2, 300), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.text('Section 2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a page with no headings says so in the contents', (
      tester,
    ) async {
      final fake = FakeLibrary(
        books: <FakeNotebook>[FakeNotebook('nb-1', 'Book')],
        pages: <FakePage>[
          FakePage('p-1', 'nb-1', 'Plain', text: 'Just words.'),
        ],
      );
      await pumpLibrary(tester, fake, const PageReaderScreen(pageId: 'p-1'));
      await tester.tap(find.widgetWithText(TextButton, 'Contents'));
      await tester.pumpAndSettle();
      expect(find.text('This page has no headings.'), findsOneWidget);
    });

    testWidgets(
      'with no connection it shows the saved copy, marked, and Edit waits',
      (tester) async {
        final fake = sampleLibrary();
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        await pumpLibrary(
          tester,
          fake,
          const PageReaderScreen(pageId: 'p-1'),
          prefs: prefs,
        );
        await tester.pumpWidget(const SizedBox());
        fake.offline = true;
        await pumpLibrary(
          tester,
          fake,
          const PageReaderScreen(pageId: 'p-1'),
          prefs: prefs,
        );
        expect(find.textContaining('Offline copy'), findsOneWidget);
        expect(rich('The router is in the hall.'), findsOneWidget);
        final edit = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Edit'),
        );
        expect(edit.onPressed, isNull);
      },
    );

    testWidgets(
      'a page that was never opened and has no connection cannot be shown',
      (tester) async {
        final fake = sampleLibrary()..offline = true;
        await pumpLibrary(tester, fake, const PageReaderScreen(pageId: 'p-1'));
        expect(find.text('Try again'), findsOneWidget);
      },
    );

    testWidgets(
      'a page the server no longer has says it is gone and leaves the recent list',
      (tester) async {
        final fake = sampleLibrary();
        fake.page('p-3')!.deleted = true;
        SharedPreferences.setMockInitialValues(<String, Object>{
          'library.recents.v1': jsonEncode(<Object?>[
            <String, Object?>{
              'id': 'p-3',
              'title': 'Boiler',
              'notebook': 'Home manual',
              'at': '2026-10-30T01:00:00.000Z',
            },
          ]),
        });
        final prefs = await SharedPreferences.getInstance();
        await pumpLibrary(
          tester,
          fake,
          const PageReaderScreen(pageId: 'p-3'),
          prefs: prefs,
        );
        expect(find.text('This page is gone'), findsOneWidget);
        expect(PageCache(prefs).recents(), isEmpty);
        expect(find.widgetWithText(FilledButton, 'Edit'), findsNothing);
      },
    );

    testWidgets('a page deleted by Botler while it is open says it is gone', (
      tester,
    ) async {
      final fake = sampleLibrary();
      final container = await pumpLibrary(
        tester,
        fake,
        const PageReaderScreen(pageId: 'p-3'),
      );
      expect(rich('Turn the dial.'), findsOneWidget);
      fake.page('p-3')!.deleted = true;
      container.invalidate(libraryProvider);
      await tester.pumpAndSettle();
      expect(find.text('This page is gone'), findsOneWidget);
    });

    testWidgets('an older server gets the "update the server" message', (
      tester,
    ) async {
      final fake = sampleLibrary()..oldServer = true;
      await pumpLibrary(tester, fake, const PageReaderScreen(pageId: 'p-1'));
      expect(find.textContaining('Update the server'), findsOneWidget);
    });

    testWidgets('a sub-page opens from the foot of its parent', (tester) async {
      await pumpLibrary(
        tester,
        sampleLibrary(),
        const PageReaderScreen(pageId: 'p-1'),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('shortcut.p-2')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey<String>('shortcut.p-2')));
      await tester.pumpAndSettle();
      expect(rich('Admin page.'), findsOneWidget);
      expect(
        labelled('Page Home manual > Wi-Fi > Router settings'),
        findsOneWidget,
      );
    });

    testWidgets(
      'deleting a page from the reader asks first and closes the reader',
      (tester) async {
        final fake = sampleLibrary();
        await pumpLibrary(tester, fake, const _Launcher('p-3'));
        await tester.tap(find.text('launch'));
        await tester.pumpAndSettle();
        await tapMore(tester, 'Delete page');
        expect(find.text('Delete this page?'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Delete page'));
        await tester.pumpAndSettle();
        expect(fake.of('page_delete').single.body['pageId'], 'p-3');
        expect(find.text('launch'), findsOneWidget);
      },
    );

    testWidgets('pin from the reader menu goes to the server', (tester) async {
      final fake = sampleLibrary();
      await pumpLibrary(tester, fake, const PageReaderScreen(pageId: 'p-3'));
      await tapMore(tester, 'Pin');
      expect(fake.of('page_pin').single.body, <String, Object?>{
        'pageId': 'p-3',
        'pinned': true,
      });
    });

    testWidgets('a page of the markdown text is opened to its heading', (
      tester,
    ) async {
      await pumpLibrary(
        tester,
        longManual(),
        const PageReaderScreen(pageId: 'p-1', initialHeading: 'section 40'),
      );
      final heading = find.descendant(
        of: find.byType(ListView),
        matching: rich('Section 40'),
      );
      expect(heading, findsOneWidget);
      expect(tester.getTopLeft(heading).dy, lessThan(200));
    });
  });

  group('editing a page', () {
    testWidgets('saves through page_save with the version it was opened at', (
      tester,
    ) async {
      final fake = sampleLibrary();
      await pumpLibrary(tester, fake, const PageReaderScreen(pageId: 'p-1'));
      await tester.tap(find.widgetWithText(FilledButton, 'Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        '# Wi-Fi\n\nThe router moved to the study.\n',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final sent = fake.of('page_save').single;
      expect(sent.body['pageId'], 'p-1');
      expect(sent.body['expectVersion'], 2);
      expect(sent.body['text'], '# Wi-Fi\n\nThe router moved to the study.\n');
      expect(sent.key, isNotNull);
      expect(fake.of('notebook_save'), isEmpty);
      // Back in the reader with the new text
      expect(rich('The router moved to the study.'), findsOneWidget);
    });

    testWidgets(
      'a newer version offers copy or save over it, and saving over reads the page again',
      (tester) async {
        final fake = sampleLibrary()..conflicts = 1;
        await pumpLibrary(tester, fake, const PageReaderScreen(pageId: 'p-1'));
        await tester.tap(find.widgetWithText(FilledButton, 'Edit'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'My text');
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        expect(find.text('The notebook changed'), findsOneWidget);
        await tester.tap(find.text('Save mine'));
        await tester.pumpAndSettle();
        expect(fake.of('page_get'), isNotEmpty);
        expect(fake.of('page_save').last.body['expectVersion'], 3);
        expect(fake.page('p-1')!.text, 'My text');
      },
    );

    testWidgets('a text over the page limit cannot be saved', (tester) async {
      await pumpLibrary(
        tester,
        sampleLibrary(),
        const PageReaderScreen(pageId: 'p-1'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'x' * 30001);
      await tester.pump();
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(save.onPressed, isNull);
      expect(find.text('30001 of 30000 characters'), findsOneWidget);
    });
  });
}
