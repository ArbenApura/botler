// [[LINKS]] AND "LINKED FROM" IN THE READER, AND THE MARKS ON LINES BOTLER ADDED SINCE THE PERSON LAST READ: A KNOWN LINK TAPS THROUGH, AN UNKNOWN ONE IS MUTED
// WORDS WITH A LABEL, CODE IS LEFT ALONE; THE BACKLINKS ROWS OPEN THEIR PAGES; THE MARKS NEED A SEEN VERSION THAT IS OLDER THAN THE PAGE, SURVIVE
// THE page_seen OF THEIR OWN OPENING, AND FALL BACK QUIETLY (NOTHING, OR "CHANGED A LOT") WHEN THEY CANNOT BE WORKED OUT.

// -- DEP-MODULES -- //
import 'package:botler/core/library_extras.dart';
import 'package:botler/features/notebooks/library_widgets.dart';
import 'package:botler/features/notebooks/notebook_pages_screen.dart';
import 'package:botler/features/notebooks/page_reader.dart';
import 'package:botler/features/notebooks/reader_view.dart';
import 'package:botler/state/library_extras.dart';
import 'package:botler/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// -- MODULES -- //
import 'library_fake.dart';

// -- FUNCTIONS -- //

FakeLibrary linked() {
  final fake = sampleLibrary();
  fake.page('p-3')!.text = 'Turn the dial.';
  fake.pages.add(
    FakePage(
      'p-7',
      'nb-1',
      'Index',
      text: 'See [[Boiler]] and [[Trip to Japan/Flights]] and [[Nothing here]].\n\nCode: `[[Boiler]]` stays.',
    ),
  );
  return fake;
}

/// A page Botler changed from version 2 to 3, read up to version 2.
FakeLibrary changed({int seen = 2, int version = 3}) {
  final fake = FakeLibrary(
    books: <FakeNotebook>[FakeNotebook('nb-1', 'Manual')],
    pages: <FakePage>[
      FakePage(
        'p-1',
        'nb-1',
        'Plan',
        text: '# Plan\n\nKeep the lid on.\n\nAdded line by Botler.\n',
        by: 'agent',
        version: version,
        seen: seen,
      ),
    ],
  );
  fake.page('p-1')!.revisions
    ..add(FakeRevision('r1', 1, '# Plan\n'))
    ..add(FakeRevision('r2', 2, '# Plan\n\nKeep the lid on.\n'));
  return fake;
}

void main() {
  group('[[links]] in the reader', () {
    testWidgets('a known link opens the page, an unknown one does nothing', (
      tester,
    ) async {
      await pumpLibrary(
        tester,
        linked(),
        const PageReaderScreen(pageId: 'p-7'),
      );
      expect(find.text('Nothing here'), findsOneWidget);
      // The unknown one is muted words with a label that says so, and it is no link
      expect(semanticsLabel('No page called Nothing here'), findsOneWidget);
      await tester.tap(find.text('Nothing here'));
      await tester.pumpAndSettle();
      expect(find.byType(PageReaderScreen), findsOneWidget);
      expect(find.text('Index'), findsWidgets);
      // The known one opens its page
      tapLinkText(tester, 'Boiler');
      await tester.pumpAndSettle();
      expect(richText('Turn the dial.'), findsOneWidget);
    });

    testWidgets('Notebook/Page finds a page in another notebook', (
      tester,
    ) async {
      await pumpLibrary(
        tester,
        linked(),
        const PageReaderScreen(pageId: 'p-7'),
      );
      tapLinkText(tester, 'Trip to Japan/Flights');
      await tester.pumpAndSettle();
      expect(richText('Leave on 3 March.'), findsOneWidget);
    });

    testWidgets('a link inside a code span stays as written', (tester) async {
      await pumpLibrary(
        tester,
        linked(),
        const PageReaderScreen(pageId: 'p-7'),
      );
      expect(
        find.textContaining('[[Boiler]]', findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('"Linked from"', () {
    testWidgets('lists the pages that link here, and a row opens one', (
      tester,
    ) async {
      final fake = linked();
      await pumpLibrary(tester, fake, const PageReaderScreen(pageId: 'p-3'));
      expect(find.text('Linked from'), findsOneWidget);
      expect(find.text('Index'), findsOneWidget);
      expect(find.textContaining('See [[Boiler]]'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('backlink.p-7')));
      await tester.pumpAndSettle();
      expect(find.text('Nothing here'), findsOneWidget);
      expect(fake.of('page_backlinks').first.body['pageId'], 'p-3');
    });

    testWidgets('a page nobody links to has no such section', (tester) async {
      await pumpLibrary(
        tester,
        linked(),
        const PageReaderScreen(pageId: 'p-2'),
      );
      expect(find.text('Linked from'), findsNothing);
    });

    test(
      'without a connection the list is empty and nothing is raised',
      () async {
        final fake = linked()..offline = true;
        final container = ProviderContainer(
          overrides: [apiProvider.overrideWithValue(fake.api)],
        );
        addTearDown(container.dispose);
        expect(await container.read(backlinksProvider('p-3').future), isEmpty);
      },
    );
  });

  group('lines added since the person last read', () {
    testWidgets(
      'the block with the new line is tinted and marked, the rest is not',
      (tester) async {
        final fake = changed();
        await pumpLibrary(tester, fake, const PageReaderScreen(pageId: 'p-1'));
        expect(find.byType(ChangedBlock), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(ChangedBlock),
            matching: richText('Added line by Botler.'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(ChangedBlock),
            matching: richText('Keep the lid on.'),
          ),
          findsNothing,
        );
        // Not by colour alone: a spoken label and a legend say what the mark means
        expect(semanticsLabel('Added since you last read'), findsOneWidget);
        expect(find.textContaining('Marked on the left'), findsOneWidget);
        // The two calls that worked it out
        expect(fake.of('page_revisions'), hasLength(1));
        expect(fake.of('page_revision_get').single.body['revisionId'], 'r2');
      },
    );

    testWidgets(
      'the marks stay although opening the page moved the seen mark',
      (tester) async {
        final fake = changed();
        await pumpLibrary(tester, fake, const PageReaderScreen(pageId: 'p-1'));
        expect(fake.of('page_seen').single.body['version'], 3);
        expect(fake.page('p-1')!.seen, 3);
        expect(find.byType(ChangedBlock), findsOneWidget);
      },
    );

    testWidgets("the person's own save is not marked as added since last read", (
      tester,
    ) async {
      final fake = changed();
      await pumpLibrary(tester, fake, const PageReaderScreen(pageId: 'p-1'));
      expect(find.byType(ChangedBlock), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        '# Plan\n\nKeep the lid on.\n\nAdded line by Botler.\n\nMy own line.\n',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(fake.page('p-1')!.version, 4);
      expect(richText('My own line.'), findsOneWidget);
      expect(find.byType(ChangedBlock), findsNothing);
      expect(find.byType(UpdatedDot), findsNothing);
      expect(find.textContaining('Marked on the left'), findsNothing);
    });

    testWidgets(
      'a page read at its newest version shows nothing and asks nothing',
      (tester) async {
        final fake = changed(seen: 3);
        await pumpLibrary(tester, fake, const PageReaderScreen(pageId: 'p-1'));
        expect(find.byType(ChangedBlock), findsNothing);
        expect(fake.of('page_revisions'), isEmpty);
      },
    );

    testWidgets('a page never opened on this phone shows nothing', (
      tester,
    ) async {
      final fake = changed(seen: 0);
      await pumpLibrary(tester, fake, const PageReaderScreen(pageId: 'p-1'));
      expect(find.byType(ChangedBlock), findsNothing);
      expect(find.textContaining('changed a lot'), findsNothing);
      expect(fake.of('page_revisions'), isEmpty);
    });

    testWidgets('a version older than the kept changes says it changed a lot', (
      tester,
    ) async {
      final fake = changed(seen: 1);
      // Only the newest change is kept: version 1 is gone
      fake.revisionsKept = 1;
      await pumpLibrary(tester, fake, const PageReaderScreen(pageId: 'p-1'));
      expect(find.byType(ChangedBlock), findsNothing);
      expect(find.textContaining('changed a lot'), findsOneWidget);
      expect(fake.of('page_revision_get'), isEmpty);
    });

    test(
      'without a connection nothing is marked and nothing is raised',
      () async {
        final fake = changed()..offline = true;
        final container = ProviderContainer(
          overrides: [apiProvider.overrideWithValue(fake.api)],
        );
        addTearDown(container.dispose);
        final got = await container.read(
          pageChangesProvider(('p-1', 2, 3)).future,
        );
        expect(got.kind, ChangeKind.none);
        expect(got.marksLines, isFalse);
      },
    );

    testWidgets(
      'the reader header and the page row show the Botler dot until it is read',
      (tester) async {
        final fake = changed();
        await pumpLibrary(tester, fake, const PageReaderScreen(pageId: 'p-1'));
        expect(find.byType(UpdatedDot), findsOneWidget);
        // The tree of the notebook shows the dot on the row too (read again after opening, it has gone: seen is now 3)
        final fresh = changed();
        await pumpLibrary(
          tester,
          fresh,
          const NotebookPagesScreen(notebookId: 'nb-1'),
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('page.p-1')),
            matching: find.byType(UpdatedDot),
          ),
          findsOneWidget,
        );
      },
    );
  });
}
