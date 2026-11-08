// THE RESEARCH CARD: LIVE COUNTS AND SITES WHILE IT RUNS, ONE FOLDED LINE WHEN DONE THAT OPENS TO THE SOURCES, AND PLAIN WORDS WHEN IT STOPPED OR FAILED.
// The card is drawn by ChatItemView for a tool called research. The live counts come from the server's research event (ChatNotifier._handle).

// -- DEP-MODULES -- //
import 'package:botler/features/chat/chat_items.dart';
import 'package:botler/features/chat/chat_state.dart';
import 'package:botler/features/chat/research_card.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- FUNCTIONS -- //

Future<Widget> hosted(
  ToolItem item, {
  Brightness mode = Brightness.light,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(mode),
      home: Scaffold(body: SingleChildScrollView(child: ChatItemView(item))),
    ),
  );
}

const Map<String, Object?> sourcesData = <String, Object?>{
  'searches': 12,
  'reads': 31,
  'sources': <Object?>[
    <String, Object?>{
      'title': 'Ferry timetable changes',
      'host': 'portauthority.example',
      'url': 'https://portauthority.example/ferry',
    },
    <String, Object?>{
      'title': 'Passenger rights',
      'host': 'consumer.example',
      'url': 'https://consumer.example/rights',
    },
    // Not a web address: left out of the list
    <String, Object?>{
      'title': 'Bad',
      'host': 'bad.example',
      'url': 'javascript:alert(1)',
    },
  ],
};

void main() {
  group('the research card', () {
    testWidgets('counts up while it runs and shows the newest sites', (
      tester,
    ) async {
      for (final mode in Brightness.values) {
        await tester.pumpWidget(
          await hosted(
            const ToolItem(
              1,
              name: 'research',
              status: 'running',
              callId: 'r1',
              running: true,
              family: 'web',
              subject: 'why are the ferries late',
              live: ResearchLive(
                searches: 12,
                reads: 31,
                hosts: <String>[
                  'maritimenews.example',
                  'portauthority.example',
                ],
              ),
            ),
            mode: mode,
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.text('Researching: why are the ferries late'),
          findsOneWidget,
        );
        expect(find.text('12 searches, 31 pages'), findsOneWidget);
        expect(find.text('maritimenews.example'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      }
    });

    testWidgets('shows only the question before the first count arrives', (
      tester,
    ) async {
      await tester.pumpWidget(
        await hosted(
          const ToolItem(
            1,
            name: 'research',
            status: 'running',
            callId: 'r1',
            running: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Researching'), findsOneWidget);
      expect(find.textContaining('searches'), findsNothing);
    });

    testWidgets('folds to one line and opens to the sources on a tap', (
      tester,
    ) async {
      await tester.pumpWidget(
        await hosted(
          const ToolItem(
            1,
            name: 'research',
            status: 'ok',
            callId: 'r1',
            data: sourcesData,
          ),
        ),
      );
      await tester.pump();
      // Two real sources: the address that is not a web address is dropped
      expect(find.text('Researched, 2 sources'), findsOneWidget);
      expect(find.text('Ferry timetable changes'), findsNothing);
      await tester.tap(find.text('Researched, 2 sources'));
      await tester.pump();
      expect(find.text('Ferry timetable changes'), findsOneWidget);
      expect(find.text('consumer.example'), findsOneWidget);
      expect(find.text('Bad'), findsNothing);
      // Each source is a target of at least 48 dp
      final row = tester.getSize(find.byType(InkWell).last);
      expect(row.height, greaterThanOrEqualTo(48));
    });

    test('keeps only web addresses as sources', () {
      expect(researchSources(sourcesData).map((s) => s.host), <String>[
        'portauthority.example',
        'consumer.example',
      ]);
      expect(researchSources(null), isEmpty);
      expect(researchSources(<String, Object?>{'sources': 'x'}), isEmpty);
    });

    testWidgets('says what it found so far when it stopped early', (
      tester,
    ) async {
      await tester.pumpWidget(
        await hosted(
          const ToolItem(
            1,
            name: 'research',
            status: 'ok',
            callId: 'r1',
            data: <String, Object?>{
              'stopped': 'time',
              'sources': <Object?>[
                <String, Object?>{
                  'title': 'One',
                  'host': 'one.example',
                  'url': 'https://one.example/a',
                },
              ],
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Researched, 1 source'), findsOneWidget);
      expect(
        find.text('It ran out of time, so this is what it found so far.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed research says so in words, with no error code', (
      tester,
    ) async {
      await tester.pumpWidget(
        await hosted(
          const ToolItem(
            1,
            name: 'research',
            status: 'error',
            callId: 'r1',
            message: 'Searches and page reads kept failing, so the digest is only what was found.',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Research could not reach the web.'), findsOneWidget);
    });
  });
}
