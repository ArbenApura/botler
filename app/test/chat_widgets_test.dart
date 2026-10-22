// THE LIVE CHAT WIDGETS: THE WORKING ROW SAYS WHAT STAGE IT IS, THE THINKING OPENS AND FOLDS, A RUNNING TOOL SHOWS A SPINNER AND NOT "FAILED",
// THE DOTS STAND STILL WHEN ANIMATIONS ARE OFF, AND THE SEND BUTTON TURNS INTO STOP. Tests pump by durations: the dots never settle.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:botler/core/api.dart';
import 'package:botler/features/chat/chat_items.dart';
import 'package:botler/features/chat/chat_screen.dart';
import 'package:botler/features/chat/chat_state.dart';
import 'package:botler/features/chat/live_parts.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- FUNCTIONS -- //

Widget host(
  Widget child, {
  Brightness mode = Brightness.light,
  bool still = false,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: buildTheme(mode),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  group('the working row', () {
    testWidgets('says the stage in words, in light and in dark', (
      tester,
    ) async {
      for (final mode in Brightness.values) {
        for (final (phase, tool, words) in <(TurnPhase, String?, String)>[
          (TurnPhase.waiting, null, 'Working on it'),
          (TurnPhase.thinking, null, 'Thinking'),
          (TurnPhase.tool, 'accounts_list', 'Checking accounts list'),
        ]) {
          await tester.pumpWidget(
            host(
              WorkingRow(phase: phase, tool: tool),
              mode: mode,
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text(words), findsOneWidget);
        }
      }
    });

    testWidgets('the dots move, and stand still when animations are off', (
      tester,
    ) async {
      await tester.pumpWidget(host(const PulsingDots()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, true);

      await tester.pumpWidget(host(const PulsingDots(), still: true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, false);
    });
  });

  group('the thinking panel', () {
    testWidgets(
      'is open while it thinks, then folds to a line that opens on a tap',
      (tester) async {
        await tester.pumpWidget(
          host(
            const ThinkingPanel(
              ThinkingItem(1, 'I should look at the accounts.'),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Thinking'), findsOneWidget);
        expect(find.text('I should look at the accounts.'), findsOneWidget);

        await tester.pumpWidget(
          host(
            const ThinkingPanel(
              ThinkingItem(
                1,
                'I should look at the accounts.',
                open: false,
                seconds: 4,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Thought for 4 s'), findsOneWidget);
        expect(find.text('I should look at the accounts.'), findsNothing);

        await tester.tap(find.text('Thought for 4 s'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('I should look at the accounts.'), findsOneWidget);
        await tester.tap(find.text('Thought for 4 s'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('I should look at the accounts.'), findsNothing);
      },
    );

    testWidgets(
      'the toggle is at least 48 logical pixels tall and says what it does',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          host(
            const ThinkingPanel(ThinkingItem(1, 'x', open: false, seconds: 2)),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester.getSize(find.byType(InkWell).first).height,
          greaterThanOrEqualTo(48),
        );
        expect(
          find.bySemanticsLabel(
            RegExp('Show or hide what the assistant thought'),
          ),
          findsOneWidget,
        );
        handle.dispose();
      },
    );

    testWidgets('a screen reader can open the folded thinking', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          const ThinkingPanel(
            ThinkingItem(1, 'The hidden thought.', open: false, seconds: 3),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('The hidden thought.'), findsNothing);
      tester.semantics.tap(
        find.semantics.byLabel(
          RegExp('Show or hide what the assistant thought'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('The hidden thought.'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a thought with no words leaves no line behind', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const ThinkingPanel(ThinkingItem(1, '  ', open: false, seconds: 1)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Thought for'), findsNothing);
    });

    testWidgets('reads the thinking as plain text, never as markdown', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const ThinkingPanel(
            ThinkingItem(1, '**bold** [link](https://x.test)'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('**bold** [link](https://x.test)'), findsOneWidget);
    });
  });

  group('a tool in the conversation', () {
    testWidgets(
      'shows a spinner and what it is doing while it runs, not the failed words',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [prefsProvider.overrideWithValue(prefs)],
            child: host(
              const ChatItemView(
                ToolItem(
                  1,
                  name: 'accounts_list',
                  status: 'running',
                  callId: 'c1',
                  running: true,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Checking accounts list'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.textContaining('could not'), findsNothing);
      },
    );

    testWidgets(
      'with animations removed a running tool shows a still mark, not a spinner',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [prefsProvider.overrideWithValue(prefs)],
            child: host(const RunningToolRow('accounts_list'), still: true),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Checking accounts list'), findsOneWidget);
      },
    );

    testWidgets('the answer being written ends with a soft block', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [prefsProvider.overrideWithValue(prefs)],
          child: host(
            const ChatItemView(AgentItem(1, 'You have two', streaming: true)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(StreamCaret), findsOneWidget);
      expect(find.textContaining('▍', findRichText: true), findsNothing);
    });
  });

  group('the chat screen', () {
    testWidgets(
      'the send button becomes stop while a turn runs, and stopping ends it',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        final streams = <StreamController<List<int>>>[];
        final client = MockClient.streaming((req, body) async {
          await body.drain<void>();
          final controller = StreamController<List<int>>();
          streams.add(controller);
          if (req is http.Abortable) {
            unawaited(
              req.abortTrigger?.then((_) {
                if (!controller.isClosed) {
                  controller.addError(http.RequestAbortedException());
                  unawaited(controller.close());
                }
              }),
            );
          }
          return http.StreamedResponse(controller.stream, 200);
        });
        final container = ProviderContainer(
          overrides: [
            prefsProvider.overrideWithValue(prefs),
            apiProvider.overrideWithValue(
              ApiClient(
                base: 'https://botler.test',
                token: () async => 'tok',
                client: client,
              ),
            ),
            syncProvider.overrideWith((ref) => Completer<Never>().future),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildTheme(Brightness.light),
              home: const ChatScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byTooltip('Send'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'hello there');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byTooltip('Stop'), findsOneWidget);
        expect(find.byTooltip('Send'), findsNothing);
        expect(find.text('Working on it'), findsOneWidget);

        // Words typed while it runs are kept, not lost
        await tester.enterText(find.byType(TextField), 'and another');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('and another'), findsOneWidget);

        await tester.tap(find.byTooltip('Stop'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        expect(container.read(chatProvider).busy, false);
        expect(find.byTooltip('Send'), findsOneWidget);
        expect(find.text('Stopped.'), findsOneWidget);
      },
    );
  });
}
