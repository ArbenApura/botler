// A RUN OF TOOL CALLS ON THE SCREEN: ONE COUNTED ROW THAT OPENS TO THE LIST, THE LIVE COUNT WHILE THEY RUN, A FAILED CALL ON ITS OWN, AND THE OLD WORDING FOR A SERVER THAT SENDS NO LABEL.

// -- DEP-MODULES -- //
import 'package:botler/core/json.dart';
import 'package:botler/features/chat/chat_group.dart';
import 'package:botler/features/chat/chat_items.dart';
import 'package:botler/features/chat/chat_state.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- FUNCTIONS -- //

/// The rows of a conversation, drawn the way the chat screen draws them.
Future<Widget> screenOf(
  List<ChatItem> items, {
  Brightness mode = Brightness.light,
  String language = 'en',
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final rows = groupQuietTools(items);
  return ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      balancesProvider.overrideWith((ref) async => const <Json>[]),
    ],
    child: MaterialApp(
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(mode),
      home: Scaffold(
        body: ListView(
          children: <Widget>[
            for (final r in rows)
              ChatItemView(
                r.item,
                group: r.members,
                key: ValueKey<int>(r.item.id),
              ),
          ],
        ),
      ),
    ),
  );
}

ToolItem page(
  int id,
  String title, {
  bool running = false,
  bool restored = false,
  String status = 'ok',
  String? message,
  int? ms = 1200,
}) => ToolItem(
  id,
  name: 'page_get',
  status: running ? 'running' : status,
  running: running,
  restored: restored,
  message: message,
  family: 'page_read',
  subject: title,
  ms: running ? null : ms,
);

ToolItem lookup(int id, {bool restored = false}) => ToolItem(
  id,
  name: 'bill_occurrence_update',
  status: 'ok',
  restored: restored,
);

void main() {
  for (final mode in Brightness.values) {
    testWidgets(
      'three page reads are one row that opens to the list (${mode.name})',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          await screenOf(<ChatItem>[
            page(1, 'Trip plan'),
            page(2, 'Packing list'),
            page(3, 'Budget 2027', ms: 2400),
          ], mode: mode),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Read 3 pages'), findsOneWidget);
        // No +N counter, and the list is closed
        expect(find.textContaining('+'), findsNothing);
        expect(find.text('Read page Trip plan, 1 s'), findsNothing);
        expect(
          find.bySemanticsLabel('Read 3 pages, 3 steps, closed'),
          findsOneWidget,
        );
        await tester.tap(find.text('Read 3 pages'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Read page Trip plan, 1 s'), findsOneWidget);
        expect(find.text('Read page Packing list, 1 s'), findsOneWidget);
        expect(find.text('Read page Budget 2027, 2 s'), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp(r'^Read 3 pages, 3 steps, open')),
          findsOneWidget,
        );
        semantics.dispose();
      },
    );
  }

  testWidgets('a running group counts up in place and keeps its open state', (
    tester,
  ) async {
    Future<void> show(List<ChatItem> items) async {
      await tester.pumpWidget(await screenOf(items));
      await tester.pump(const Duration(milliseconds: 100));
    }

    await show(<ChatItem>[
      page(1, 'Trip plan'),
      page(2, 'Packing list'),
      page(3, 'Budget 2027', running: true),
    ]);
    expect(find.text('Reading pages'), findsOneWidget);
    expect(find.text('2 of 3'), findsOneWidget);
    // Open the list, then the last call finishes: the same row, still open
    await tester.tap(find.text('Reading pages'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Reading page Budget 2027'), findsOneWidget);
    await show(<ChatItem>[
      page(1, 'Trip plan'),
      page(2, 'Packing list'),
      page(3, 'Budget 2027'),
    ]);
    expect(find.text('Read 3 pages'), findsOneWidget);
    expect(find.text('Read page Budget 2027, 1 s'), findsOneWidget);
  });

  testWidgets('one labelled call alone says what it read and for how long', (
    tester,
  ) async {
    await tester.pumpWidget(await screenOf(<ChatItem>[page(1, 'Trip plan')]));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Read page Trip plan, 1 s'), findsOneWidget);
    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets('a failed call is its own row with the tool and the reason', (
    tester,
  ) async {
    await tester.pumpWidget(
      await screenOf(<ChatItem>[
        page(1, 'Trip plan'),
        page(2, 'Packing list'),
        page(
          3,
          'Budget 2027',
          status: 'error',
          message: 'No page with that title.',
        ),
        page(4, 'Notes', status: 'blocked', message: 'Not allowed here.'),
      ]),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Read 2 pages'), findsOneWidget);
    expect(find.text('Failed: Reading page Budget 2027'), findsOneWidget);
    expect(find.text('No page with that title.'), findsOneWidget);
    expect(find.text('Blocked: Reading page Notes'), findsOneWidget);
    // Neither reads as done
    expect(find.textContaining('Read page Budget'), findsNothing);
  });

  testWidgets(
    'lookups with no label from an older server group as things checked',
    (tester) async {
      await tester.pumpWidget(
        await screenOf(<ChatItem>[lookup(1), lookup(2), lookup(3)]),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Checked 3 things'), findsOneWidget);
      await tester.tap(find.text('Checked 3 things'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Checked bill occurrence update'), findsNWidgets(3));
    },
  );

  testWidgets('one unlabelled line alone keeps the old words', (tester) async {
    await tester.pumpWidget(await screenOf(<ChatItem>[lookup(1)]));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Checked bill occurrence update'), findsOneWidget);
    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets('a group from an earlier session reads the same', (tester) async {
    await tester.pumpWidget(
      await screenOf(<ChatItem>[
        page(1, 'Trip plan', restored: true),
        page(2, 'Packing list', restored: true),
      ]),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Read 2 pages'), findsOneWidget);
  });

  testWidgets('the Filipino words are used when the language is Filipino', (
    tester,
  ) async {
    await tester.pumpWidget(
      await screenOf(<ChatItem>[
        page(1, 'Trip plan'),
        page(2, 'Packing list'),
      ], language: 'fil'),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Nabasa ang 2 pahina'), findsOneWidget);
  });
}
