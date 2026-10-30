// MANAGING PAGES: MOVING (TO ANOTHER NOTEBOOK, UNDER A PAGE, UP AND DOWN) THROUGH THE PAGE SHEET, THE LIST OF DELETED PAGES WITH THEIR DAYS LEFT AND RESTORE,
// COPYING A NOTEBOOK AS MARKDOWN, AND THE PAGE EDITOR'S TOOLBAR (WHICH THE MAIN NOTEBOOK'S EDITOR DOES NOT HAVE) WITH A SAVE THAT LOSES NO TEXT OFFLINE.

// -- DEP-MODULES -- //
import 'package:botler/features/memory/notebook_editor.dart';
import 'package:botler/features/notebooks/notebook_pages_screen.dart';
import 'package:botler/features/notebooks/page_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// -- MODULES -- //
import 'library_fake.dart';

// -- FUNCTIONS -- //

Future<void> openSheet(WidgetTester tester, String page) async {
  await tester.longPress(find.text(page));
  await tester.pumpAndSettle();
}

Future<void> tapMore(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// What the app copied to the clipboard, while the test runs.
List<String> watchClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        copied.add('${args['text']}');
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

const NotebookPagesScreen homeManual = NotebookPagesScreen(notebookId: 'nb-1');

void main() {
  group('moving a page', () {
    testWidgets(
      'Move up and Move down are offered only where there is a neighbour',
      (tester) async {
        await pumpLibrary(tester, sampleLibrary(), homeManual);
        // Wi-Fi is first: it can go down, not up
        await openSheet(tester, 'Wi-Fi');
        expect(find.text('Move to...'), findsOneWidget);
        expect(find.text('Move up'), findsNothing);
        expect(find.text('Move down'), findsOneWidget);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        // Boiler is last
        await openSheet(tester, 'Boiler');
        expect(find.text('Move up'), findsOneWidget);
        expect(find.text('Move down'), findsNothing);
      },
    );

    testWidgets('Move up sends the place among its neighbours', (tester) async {
      final fake = sampleLibrary();
      await pumpLibrary(tester, fake, homeManual);
      await openSheet(tester, 'Boiler');
      await tester.tap(find.text('Move up'));
      await tester.pumpAndSettle();
      final sent = fake.of('page_move').single;
      expect(sent.body, <String, Object?>{'pageId': 'p-3', 'position': 0});
      expect(sent.key, isNotNull);
      expect(find.text('Moved.'), findsOneWidget);
    });

    testWidgets('a sub-page names its parent again so it stays under it', (
      tester,
    ) async {
      final fake = sampleLibrary();
      fake.pages.add(
        FakePage('p-8', 'nb-1', 'Second sub', parent: 'p-1', text: 'x'),
      );
      await pumpLibrary(tester, fake, homeManual);
      await openSheet(tester, 'Second sub');
      await tester.tap(find.text('Move up'));
      await tester.pumpAndSettle();
      expect(fake.of('page_move').single.body, <String, Object?>{
        'pageId': 'p-8',
        'toParentPageId': 'p-1',
        'position': 0,
      });
    });

    testWidgets('Move to another notebook, at the top level', (tester) async {
      final fake = sampleLibrary();
      await pumpLibrary(tester, fake, homeManual);
      await openSheet(tester, 'Boiler');
      await tester.tap(find.text('Move to...'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('move.book.nb-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('move.top')));
      await tester.pumpAndSettle();
      expect(fake.of('page_move').single.body, <String, Object?>{
        'pageId': 'p-3',
        'toNotebookId': 'nb-2',
      });
      expect(fake.page('p-3')!.notebookId, 'nb-2');
    });

    testWidgets('Move to puts a page under a top-level page of a notebook', (
      tester,
    ) async {
      final fake = sampleLibrary();
      await pumpLibrary(tester, fake, homeManual);
      await openSheet(tester, 'Boiler');
      await tester.tap(find.text('Move to...'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('move.book.nb-1')));
      await tester.pumpAndSettle();
      // Only the other top-level pages are offered as a parent
      expect(
        find.byKey(const ValueKey<String>('move.under.p-3')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('move.under.p-2')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey<String>('move.under.p-1')));
      await tester.pumpAndSettle();
      expect(fake.of('page_move').single.body, <String, Object?>{
        'pageId': 'p-3',
        'toParentPageId': 'p-1',
      });
    });

    testWidgets('a page with sub-pages can only go to the top level', (
      tester,
    ) async {
      final fake = sampleLibrary();
      await pumpLibrary(tester, fake, homeManual);
      await openSheet(tester, 'Wi-Fi');
      await tester.tap(find.text('Move to...'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('move.book.nb-1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('has sub-pages'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('move.under.p-3')),
        findsNothing,
      );
    });

    testWidgets('with no connection the move is kept and the tree is guessed', (
      tester,
    ) async {
      final fake = sampleLibrary();
      await pumpLibrary(tester, fake, homeManual);
      fake.offline = true;
      await openSheet(tester, 'Boiler');
      await tester.tap(find.text('Move up'));
      await tester.pumpAndSettle();
      expect(find.textContaining('kept on your phone'), findsOneWidget);
      // The saved outline now has Boiler first
      expect(
        tester.getTopLeft(find.text('Boiler')).dy,
        lessThan(tester.getTopLeft(find.text('Wi-Fi')).dy),
      );
    });
  });

  group('deleted pages', () {
    testWidgets('are listed with the days left, and Restore puts one back', (
      tester,
    ) async {
      final fake = sampleLibrary()
        ..deletedAtStamp = DateTime.now()
            .subtract(const Duration(days: 5))
            .toUtc()
            .toIso8601String();
      await pumpLibrary(tester, fake, homeManual);
      await openSheet(tester, 'Boiler');
      await tester.tap(find.text('Delete page'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete page'));
      await tester.pumpAndSettle();
      expect(find.text('Boiler'), findsNothing);
      await tapMore(tester, 'Deleted pages');
      expect(find.text('Boiler'), findsOneWidget);
      expect(find.text('25 days left'), findsOneWidget);
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(fake.of('page_undelete').single.body['pageId'], 'p-3');
      expect(find.text('Put back.'), findsOneWidget);
      expect(find.text('Boiler'), findsOneWidget);
      expect(fake.page('p-3'), isNotNull);
    });

    testWidgets('only this notebook\'s pages are listed; none says so', (
      tester,
    ) async {
      final fake = sampleLibrary();
      fake.page('p-4')!
        ..deleted = true
        ..deletedAt = fake.deletedAtStamp;
      await pumpLibrary(tester, fake, homeManual);
      await tapMore(tester, 'Deleted pages');
      expect(find.text('No deleted pages.'), findsOneWidget);
      expect(find.text('Flights'), findsNothing);
    });

    testWidgets('restoring without a connection says it needs one', (
      tester,
    ) async {
      final fake = sampleLibrary();
      fake.page('p-3')!
        ..deleted = true
        ..deletedAt = fake.deletedAtStamp;
      await pumpLibrary(tester, fake, homeManual);
      await tapMore(tester, 'Deleted pages');
      fake.offline = true;
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(find.textContaining('needs a connection'), findsOneWidget);
    });
  });

  group('copy as Markdown', () {
    testWidgets('copies the notebook with its pages and sub-pages in order', (
      tester,
    ) async {
      final copied = watchClipboard(tester);
      final fake = sampleLibrary();
      await pumpLibrary(tester, fake, homeManual);
      await tapMore(tester, 'Copy as Markdown');
      expect(copied, hasLength(1));
      expect(
        copied.single,
        '# Home manual\n\n## Wi-Fi\n\n# Wi-Fi\n\nThe router is in the hall.\n\n## Reset\n\nHold the button.\n\n### Router settings\n\nAdmin page.\n\n## Boiler\n\nTurn the dial.\n',
      );
      expect(find.text('Copied 3 pages as Markdown.'), findsOneWidget);
    });

    testWidgets('with no connection it says so and copies nothing', (
      tester,
    ) async {
      final copied = watchClipboard(tester);
      final fake = sampleLibrary();
      await pumpLibrary(tester, fake, homeManual);
      fake.offline = true;
      await tapMore(tester, 'Copy as Markdown');
      expect(copied, isEmpty);
      expect(find.textContaining('needs a connection'), findsOneWidget);
    });

    testWidgets('an empty notebook has no export', (tester) async {
      final fake = FakeLibrary(
        books: <FakeNotebook>[FakeNotebook('nb-1', 'Empty')],
      );
      await pumpLibrary(tester, fake, homeManual);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Copy as Markdown'), findsNothing);
    });
  });

  group('the page editor', () {
    Future<void> openEditor(WidgetTester tester, FakeLibrary fake) async {
      await pumpLibrary(tester, fake, const PageReaderScreen(pageId: 'p-1'));
      await tester.tap(find.widgetWithText(FilledButton, 'Edit'));
      await tester.pumpAndSettle();
    }

    testWidgets('has the six Markdown buttons, each at least 48 dp', (
      tester,
    ) async {
      await openEditor(tester, sampleLibrary());
      for (final k in <String>[
        'heading',
        'bold',
        'list',
        'checkbox',
        'link',
        'pageLink',
      ]) {
        final button = find.byKey(ValueKey<String>('md.$k'));
        expect(button, findsOneWidget);
        final size = tester.getSize(button);
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('a button edits the text where the cursor is', (tester) async {
      await openEditor(tester, sampleLibrary());
      final field = find.byType(TextField);
      await tester.enterText(field, 'milk');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('md.checkbox')));
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '- [ ] milk');
      // The text is changed, so Save is on
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('a page link button writes the double brackets', (
      tester,
    ) async {
      await openEditor(tester, sampleLibrary());
      final field = find.byType(TextField);
      await tester.enterText(field, '');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('md.pageLink')));
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '[[]]');
    });

    testWidgets('the main notebook\'s editor has no toolbar', (tester) async {
      await pumpLibrary(
        tester,
        sampleLibrary(),
        const NotebookEditor(initial: 'Main', version: 1),
      );
      expect(find.byKey(const ValueKey<String>('md.bold')), findsNothing);
    });

    testWidgets('a save with no connection keeps the text and says so', (
      tester,
    ) async {
      final fake = sampleLibrary();
      await openEditor(tester, fake);
      await tester.enterText(find.byType(TextField), 'My careful text');
      await tester.pump();
      fake.offline = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No connection. Your text is still here'),
        findsOneWidget,
      );
      // Still in the editor, with the text, and nothing was queued under the person's feet
      final field = find.byType(TextField);
      expect(
        tester.widget<TextField>(field).controller!.text,
        'My careful text',
      );
      fake.offline = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(fake.page('p-1')!.text, 'My careful text');
    });
  });
}
