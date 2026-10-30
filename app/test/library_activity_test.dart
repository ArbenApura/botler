// BOTLER'S RECENT CHANGES ON THE LIBRARY: THE FEED (A FEW, THEN "SHOW ALL"), A TAP OPENING THE PAGE, AND UNDO ONLY WHILE THE CHANGE IS STILL THE NEWEST:
// IT PUTS BACK THE TEXT BOTLER REPLACED, OR, FOR A PAGE BOTLER MADE, DELETES IT AFTER ASKING; ANY OTHER ENTRY CAN ONLY BE VIEWED.

// -- DEP-MODULES -- //
import 'package:botler/features/notebooks/library_screen.dart';
import 'package:botler/state/library_extras.dart';
import 'package:botler/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// -- MODULES -- //
import 'library_fake.dart';

// -- FUNCTIONS -- //

Finder undoOf(String pageId) =>
    find.byKey(ValueKey<String>('activity.undo.$pageId'));

/// Botler rewrote "Wi-Fi" (version 2, the old text kept) and made "Notes" (version 1).
FakeLibrary botlerWork() {
  final fake = sampleLibrary();
  fake
      .page('p-1')!
      .revisions
      .add(FakeRevision('rev-p-1-1', 1, 'Old wifi text.'));
  fake.pages.add(
    FakePage('p-9', 'nb-1', 'Notes', text: 'Botler wrote this.', by: 'agent'),
  );
  return fake;
}

void main() {
  group('the feed', () {
    testWidgets('lists what Botler changed with how long ago, newest first', (
      tester,
    ) async {
      final fake = botlerWork()
        ..activityAt = DateTime.now()
            .subtract(const Duration(hours: 2))
            .toUtc()
            .toIso8601String();
      await pumpLibrary(tester, fake, const LibraryScreen());
      expect(find.text("Botler's recent changes"), findsOneWidget);
      expect(find.text('Botler changed Wi-Fi in Home manual'), findsOneWidget);
      expect(find.text('Botler changed Notes in Home manual'), findsOneWidget);
      expect(find.text('2 hours ago'), findsNWidgets(2));
    });

    testWidgets('shows the latest three and the rest after Show all', (
      tester,
    ) async {
      final fake = sampleLibrary();
      for (var i = 1; i <= 5; i++) {
        fake.pages.add(
          FakePage('x-$i', 'nb-1', 'Made $i', text: 'x', by: 'agent'),
        );
      }
      await pumpLibrary(tester, fake, const LibraryScreen());
      // Wi-Fi is Botler's as well: six entries in all
      expect(
        find.byKey(const ValueKey<String>('activity.x-1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('activity.x-5')), findsNothing);
      await tester.ensureVisible(find.text('Show all 6'));
      await tester.tap(find.text('Show all 6'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('activity.x-5')),
        findsOneWidget,
      );
      expect(find.text('Show fewer'), findsOneWidget);
    });

    testWidgets('nothing Botler did means no section', (tester) async {
      final fake = sampleLibrary();
      fake.page('p-1')!.by = 'user';
      await pumpLibrary(tester, fake, const LibraryScreen());
      expect(find.text("Botler's recent changes"), findsNothing);
    });

    testWidgets('a tap on an entry opens the page', (tester) async {
      await pumpLibrary(tester, botlerWork(), const LibraryScreen());
      await tester.tap(find.byKey(const ValueKey<String>('activity.open.p-9')));
      await tester.pumpAndSettle();
      expect(richText('Botler wrote this.'), findsOneWidget);
    });

    test(
      'without a connection the feed is empty and nothing is raised',
      () async {
        final fake = botlerWork()..offline = true;
        final container = ProviderContainer(
          overrides: [apiProvider.overrideWithValue(fake.api)],
        );
        addTearDown(container.dispose);
        expect(await container.read(activityProvider.future), isEmpty);
      },
    );
  });

  group('undo', () {
    testWidgets(
      'puts back the text Botler replaced and reads the library again',
      (tester) async {
        final fake = botlerWork();
        await pumpLibrary(tester, fake, const LibraryScreen());
        await tester.tap(undoOf('p-1'));
        await tester.pumpAndSettle();
        expect(fake.of('page_restore').single.body['revisionId'], 'rev-p-1-1');
        expect(fake.of('page_restore').single.key, isNotNull);
        expect(fake.page('p-1')!.text, 'Old wifi text.');
        expect(find.text('Put back the earlier text.'), findsOneWidget);
        // Wi-Fi is the person's now: it left the feed
        expect(
          find.byKey(const ValueKey<String>('activity.p-1')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'a page Botler made is deleted after asking, and Not now keeps it',
      (tester) async {
        final fake = botlerWork();
        await pumpLibrary(tester, fake, const LibraryScreen());
        await tester.tap(undoOf('p-9'));
        await tester.pumpAndSettle();
        expect(find.text('Delete the page Botler made?'), findsOneWidget);
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
        expect(fake.of('page_delete'), isEmpty);
        await tester.tap(undoOf('p-9'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Delete page'));
        await tester.pumpAndSettle();
        expect(fake.of('page_delete').single.body['pageId'], 'p-9');
        expect(
          find.text('Deleted. You can put it back for 30 days.'),
          findsOneWidget,
        );
        expect(fake.page('p-9'), isNull);
      },
    );

    testWidgets('is not offered when the person wrote on the page since', (
      tester,
    ) async {
      // The feed names version 1 of a page that is at version 2 now: the entry is no longer the newest
      final fake = botlerWork()..activityVersionLag = 1;
      await pumpLibrary(tester, fake, const LibraryScreen());
      expect(
        find.byKey(const ValueKey<String>('activity.p-1')),
        findsOneWidget,
      );
      expect(undoOf('p-1'), findsNothing);
      expect(undoOf('p-9'), findsNothing);
      // It can still be viewed
      await tester.tap(find.byKey(const ValueKey<String>('activity.open.p-1')));
      await tester.pumpAndSettle();
      expect(richText('The router is in the hall.'), findsOneWidget);
    });

    testWidgets('a rename or a move by Botler is only viewed, never undone', (
      tester,
    ) async {
      final fake = sampleLibrary();
      // The person made "Mine" (version 1) and "Edited" (version 2, by the person); Botler only renamed or moved them
      fake.pages.addAll(<FakePage>[
        FakePage(
          'm-1',
          'nb-1',
          'Mine',
          text: 'Mine.',
          by: 'agent',
          userMade: true,
        ),
        FakePage(
            'm-2',
            'nb-1',
            'Edited',
            text: 'Edited.',
            by: 'agent',
            version: 2,
          )
          ..revisions.add(
            FakeRevision('rev-m-2-1', 1, 'Before.', actor: 'user'),
          ),
      ]);
      await pumpLibrary(tester, fake, const LibraryScreen());
      expect(
        find.byKey(const ValueKey<String>('activity.m-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('activity.m-2')),
        findsOneWidget,
      );
      expect(undoOf('m-1'), findsNothing);
      expect(undoOf('m-2'), findsNothing);
      expect(fake.of('page_delete'), isEmpty);
      expect(fake.of('page_restore'), isEmpty);
    });

    testWidgets('does not restore when the newest change was the person', (
      tester,
    ) async {
      final fake = botlerWork();
      // Botler's entry still says textChanged, but the saved change was the person's
      fake.page('p-1')!.revisions
        ..clear()
        ..add(FakeRevision('rev-p-1-1', 1, 'Old wifi text.', actor: 'user'));
      await pumpLibrary(tester, fake, const LibraryScreen());
      expect(undoOf('p-1'), findsNothing);
    });

    testWidgets('says so when the earlier text is no longer kept', (
      tester,
    ) async {
      final fake = botlerWork()..revisionsKept = 0;
      await pumpLibrary(tester, fake, const LibraryScreen());
      await tester.tap(undoOf('p-1'));
      await tester.pumpAndSettle();
      expect(fake.of('page_restore'), isEmpty);
      expect(find.textContaining('no longer kept'), findsOneWidget);
      expect(fake.page('p-1')!.version, 2);
    });

    testWidgets('does not offer undo for a change older than the newest one', (
      tester,
    ) async {
      final fake = botlerWork();
      // The newest saved change is of version 0 here, not 1: it is not what Botler replaced, so Botler did not make the latest text change
      fake.page('p-1')!.revisions
        ..clear()
        ..add(FakeRevision('rev-old', 0, 'Much older text.'));
      await pumpLibrary(tester, fake, const LibraryScreen());
      expect(undoOf('p-1'), findsNothing);
      expect(fake.of('page_restore'), isEmpty);
    });

    testWidgets('a failure to reach the server is told in plain words', (
      tester,
    ) async {
      final fake = botlerWork();
      await pumpLibrary(tester, fake, const LibraryScreen());
      fake.offline = true;
      await tester.tap(undoOf('p-1'));
      await tester.pumpAndSettle();
      expect(find.textContaining('needs a connection'), findsOneWidget);
      expect(fake.page('p-1')!.text, contains('router'));
    });
  });
}
