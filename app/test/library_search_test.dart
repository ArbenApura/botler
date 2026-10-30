// THE SEARCH SCREEN: ITS STATES (HINT, LOADING, NO RESULTS, A FAILURE WITH RETRY, OFFLINE, "MORE RESULTS"), SEARCHING AS YOU PAUSE, THE FOUND WORDS MARKED,
// A TAP OPENING THE PAGE SCROLLED TO THE MATCH, AND A SLOW OLD ANSWER NEVER REPLACING A NEWER ONE.

// -- DEP-MODULES -- //
import 'package:botler/features/notebooks/library_screen.dart';
import 'package:botler/features/notebooks/library_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// -- MODULES -- //
import 'library_fake.dart';

// -- FUNCTIONS -- //

/// Types and waits out the pause, so the search starts by itself.
Future<void> typeAndWait(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(searchPause + const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

FakeLibrary needleManual() => FakeLibrary(
  books: <FakeNotebook>[FakeNotebook('nb-1', 'Manual')],
  pages: <FakePage>[
    FakePage(
      'p-1',
      'nb-1',
      'Everything',
      text: [
        for (var i = 1; i <= 60; i++)
          '## Section $i\n\nFirst paragraph of section $i with a few words to fill a line.\n\n${i == 50 ? 'The needle is in section fifty.' : 'Second paragraph of section $i with a few words to fill a line.'}',
      ].join('\n\n'),
    ),
  ],
);

void main() {
  testWidgets('starts with a hint and asks nothing', (tester) async {
    final fake = sampleLibrary();
    await pumpLibrary(tester, fake, const LibrarySearchScreen());
    expect(find.textContaining('Type at least two letters'), findsOneWidget);
    expect(fake.of('notebook_search'), isEmpty);
  });

  testWidgets('one letter asks nothing; a pause after two starts the search', (
    tester,
  ) async {
    final fake = sampleLibrary();
    await pumpLibrary(tester, fake, const LibrarySearchScreen());
    await tester.enterText(find.byType(TextField), 'w');
    await tester.pump(searchPause + const Duration(milliseconds: 50));
    expect(fake.of('notebook_search'), isEmpty);
    await tester.enterText(find.byType(TextField), 'wi');
    await tester.pump(const Duration(milliseconds: 100));
    // Still typing: not yet
    expect(fake.of('notebook_search'), isEmpty);
    await tester.pump(searchPause);
    await tester.pumpAndSettle();
    expect(fake.of('notebook_search').single.body['query'], 'wi');
  });

  testWidgets(
    'a result says Notebook > Page, shows the line and marks the term',
    (tester) async {
      final fake = sampleLibrary();
      await pumpLibrary(tester, fake, const LibrarySearchScreen());
      await typeAndWait(tester, 'march');
      expect(find.text('Trip to Japan'), findsOneWidget);
      expect(find.text('Flights'), findsOneWidget);
      expect(richText('Leave on 3 March.'), findsOneWidget);
      // The found word is marked inside the line
      expect(markedSpans(tester), contains('March'));
    },
  );

  testWidgets('a sub-page is labelled with its parent', (tester) async {
    final fake = sampleLibrary();
    await pumpLibrary(tester, fake, const LibrarySearchScreen());
    await typeAndWait(tester, 'admin');
    expect(find.text('Home manual > Wi-Fi'), findsOneWidget);
    expect(find.text('Router settings'), findsOneWidget);
  });

  testWidgets('a title match marks the title', (tester) async {
    final fake = sampleLibrary();
    await pumpLibrary(tester, fake, const LibrarySearchScreen());
    await typeAndWait(tester, 'boil');
    expect(markedSpans(tester), contains('Boil'));
  });

  testWidgets('no matches says so', (tester) async {
    await pumpLibrary(tester, sampleLibrary(), const LibrarySearchScreen());
    await typeAndWait(tester, 'zzzz');
    expect(find.text('Nothing found.'), findsOneWidget);
  });

  testWidgets('more matches than listed adds a note', (tester) async {
    final fake = sampleLibrary()..searchMore = true;
    await pumpLibrary(tester, fake, const LibrarySearchScreen());
    await typeAndWait(tester, 'the');
    expect(find.textContaining('more matches'), findsOneWidget);
  });

  testWidgets('a complete list has no such note', (tester) async {
    await pumpLibrary(tester, sampleLibrary(), const LibrarySearchScreen());
    await typeAndWait(tester, 'the');
    expect(find.text('Boiler'), findsOneWidget);
    expect(find.textContaining('more matches'), findsNothing);
  });

  testWidgets('a failure says so and Try again asks again', (tester) async {
    final fake = sampleLibrary()..broken = true;
    await pumpLibrary(tester, fake, const LibrarySearchScreen());
    await typeAndWait(tester, 'flights');
    expect(find.text('Search did not work. Try again.'), findsOneWidget);
    fake.broken = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Flights'), findsOneWidget);
    expect(fake.of('notebook_search'), hasLength(2));
  });

  testWidgets('with no connection it says search needs one', (tester) async {
    final fake = sampleLibrary()..offline = true;
    await pumpLibrary(tester, fake, const LibrarySearchScreen());
    await typeAndWait(tester, 'flights');
    expect(find.textContaining('Search needs a connection'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a slow old answer never replaces a newer one', (tester) async {
    final fake = sampleLibrary();
    await pumpLibrary(tester, fake, const LibrarySearchScreen());
    fake.searchDelay = const Duration(seconds: 2);
    await tester.enterText(find.byType(TextField), 'router');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'boiler');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Boiler'), findsOneWidget);
    expect(find.text('Router settings'), findsNothing);
  });

  testWidgets('clearing the field goes back to the hint', (tester) async {
    await pumpLibrary(tester, sampleLibrary(), const LibrarySearchScreen());
    await typeAndWait(tester, 'flights');
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Type at least two letters'), findsOneWidget);
    expect(find.text('Flights'), findsNothing);
  });

  testWidgets(
    'a tap on a result opens the page at the block that has the match',
    (tester) async {
      final fake = needleManual();
      await pumpLibrary(tester, fake, const LibrarySearchScreen());
      await typeAndWait(tester, 'needle');
      await tester.tap(find.byKey(const ValueKey<String>('result.p-1')));
      await tester.pumpAndSettle();
      // Section 50 is far down a page of 60: it is on screen only because the reader scrolled there
      expect(richText('The needle is in section fifty.'), findsOneWidget);
      expect(richText('Section 1'), findsNothing);
    },
  );

  testWidgets('a title match opens the page from the top', (tester) async {
    final fake = needleManual();
    await pumpLibrary(tester, fake, const LibrarySearchScreen());
    await typeAndWait(tester, 'everything');
    await tester.tap(find.byKey(const ValueKey<String>('result.p-1')));
    await tester.pumpAndSettle();
    expect(richText('Section 1'), findsOneWidget);
  });

  testWidgets('the library opens it from its one primary action', (
    tester,
  ) async {
    await pumpLibrary(tester, sampleLibrary(), const LibraryScreen());
    await tester.tap(find.text('Search your notebooks'));
    await tester.pumpAndSettle();
    expect(find.byType(LibrarySearchScreen), findsOneWidget);
  });
}
