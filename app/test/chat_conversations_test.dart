// MANY CONVERSATIONS: THE DRAWER (GROUPS, SEARCH, OPEN, RENAME, PIN, ARCHIVE), BRANCHING FROM A MESSAGE, EDIT AND RESEND, AND THE RULES THAT KEEP IT SAFE
// (NOTHING SWITCHES WHILE AN ANSWER IS BEING WRITTEN, A FAILED BRANCH KEEPS THE WORDS, EVERY MESSAGE GOES TO THE CHAT ON SCREEN).

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:botler/core/api.dart';
import 'package:botler/features/chat/chat_screen.dart';
import 'package:botler/features/chat/chats_state.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- MODULES -- //
import 'chat_restore_test.dart' show RestoreServer, turn;

// -- FUNCTIONS -- //

/// A conversation as the server lists it.
Map<String, Object?> row(
  String id,
  String title, {
  bool pinned = false,
  bool archived = false,
  bool forked = false,
  DateTime? at,
  String preview = 'the last thing said',
}) => <String, Object?>{
  'id': id,
  'title': title,
  'preview': preview,
  'lastActiveAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
  'turns': 2,
  'pinned': pinned,
  'archived': archived,
  'forkedFromChatId': forked ? 'c-origin' : null,
};

Map<String, Object?> head(
  String id,
  String title, {
  Map<String, Object?>? from,
}) => <String, Object?>{'id': id, 'title': title, 'forkedFrom': from};

Future<ProviderContainer> open(WidgetTester tester, RestoreServer s) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      apiProvider.overrideWithValue(
        ApiClient(
          base: 'https://botler.test',
          token: () async => 'tok',
          client: s.client,
        ),
      ),
      syncProvider.overrideWith(
        (ref) async => <String, Object?>{
          'summary': <String, Object?>{'total': 500000},
        },
      ),
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
  await settle(tester);
  return container;
}

/// Lets the fake server answer and the screen draw. A skeleton pulses forever, so the steps are bounded.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// The search box of the drawer (the composer is a text field too).
Finder searchBox() =>
    find.descendant(of: find.byType(Drawer), matching: find.byType(TextField));

Future<void> openDrawer(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Chats'));
  await settle(tester);
}

RestoreServer twoChats() => RestoreServer()
  ..history = <String, Object?>{
    'chat': head('c1', 'Weekly plan'),
    'turns': <Object?>[
      turn('plan the week', reply: 'Here is a plan.', id: 'm0'),
      turn('and friday?', reply: 'Friday is free.', id: 'm1'),
    ],
  }
  ..chatList = <String, Object?>{
    'chats': <Object?>[
      row('c1', 'Weekly plan', pinned: true),
      row('c2', 'Groceries'),
      row(
        'c3',
        'Old chat',
        at: DateTime.now().subtract(const Duration(days: 30)),
      ),
    ],
  };

// -- TESTS -- //

void main() {
  group('when a chat was last used', () {
    // Manila is eight hours ahead: this is noon on the 23rd there
    final now = DateTime.utc(2026, 10, 23, 4);
    test('puts a chat in its day group, and a pin above them all', () {
      expect(
        timeGroupOf(DateTime.utc(2026, 10, 23, 0, 30), now: now),
        ChatGroup.today,
      );
      // 18:00 on the 22nd in Manila
      expect(
        timeGroupOf(DateTime.utc(2026, 10, 22, 10), now: now),
        ChatGroup.yesterday,
      );
      expect(
        timeGroupOf(DateTime.utc(2026, 10, 18, 10), now: now),
        ChatGroup.week,
      );
      expect(
        timeGroupOf(DateTime.utc(2026, 10, 10, 10), now: now),
        ChatGroup.older,
      );
      // Late evening in UTC is already tomorrow in Manila
      expect(
        timeGroupOf(DateTime.utc(2026, 10, 22, 17), now: now),
        ChatGroup.today,
      );
      final pinned = ChatSummary.fromJson(
        row('p', 'Pinned one', pinned: true, at: DateTime.utc(2020)),
      );
      expect(groupOf(pinned, now: now), ChatGroup.pinned);
    });
  });

  group('the drawer', () {
    testWidgets(
      'lists the chats in groups, the open one marked, with archive at the bottom',
      (tester) async {
        final s = twoChats();
        await open(tester, s);
        expect(find.text('Weekly plan'), findsOneWidget);
        await openDrawer(tester);
        expect(find.text('Pinned'), findsOneWidget);
        expect(find.text('Today'), findsOneWidget);
        expect(find.text('Older'), findsOneWidget);
        expect(find.text('Groceries'), findsOneWidget);
        expect(find.text('Old chat'), findsOneWidget);
        expect(find.text('Archived chats'), findsOneWidget);
        // The title of the chat on screen is also in the app bar
        expect(find.text('Weekly plan'), findsWidgets);
      },
    );

    testWidgets(
      'opens a chat: tells the server, loads its messages and closes the drawer',
      (tester) async {
        final s = twoChats();
        await open(tester, s);
        await openDrawer(tester);
        s.history = <String, Object?>{
          'chat': head('c2', 'Groceries'),
          'turns': <Object?>[turn('buy rice', reply: 'Noted.', id: 'g0')],
        };
        await tester.tap(find.text('Groceries'));
        await settle(tester);
        await settle(tester);
        expect(s.lastArgs('chat_open'), <String, Object?>{'chatId': 'c2'});
        expect(s.lastArgs('chat_history'), <String, Object?>{'chatId': 'c2'});
        expect(find.text('buy rice'), findsOneWidget);
        expect(find.text('plan the week'), findsNothing);
        // The drawer is closed
        expect(find.text('Pinned'), findsNothing);
      },
    );

    testWidgets('searches after a pause, and says so when nothing matches', (
      tester,
    ) async {
      final s = twoChats();
      await open(tester, s);
      await openDrawer(tester);
      s.chatList = <String, Object?>{'chats': <Object?>[]};
      await tester.enterText(searchBox(), 'xyz');
      await tester.pump(const Duration(milliseconds: 100));
      // Not yet: the person is still typing
      expect(s.lastArgs('chat_list')?['search'], isNull);
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      expect(s.lastArgs('chat_list'), <String, Object?>{'search': 'xyz'});
      expect(find.text('No chat matches that.'), findsOneWidget);
    });

    testWidgets('does not search for one letter', (tester) async {
      final s = twoChats();
      await open(tester, s);
      await openDrawer(tester);
      final before = s.count('chat_list');
      await tester.enterText(searchBox(), 'x');
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(s.count('chat_list'), before);
    });

    testWidgets('renames, pins and archives from the row actions', (
      tester,
    ) async {
      final s = twoChats();
      await open(tester, s);
      await openDrawer(tester);

      await tester.longPress(find.text('Groceries'));
      await settle(tester);
      await tester.tap(find.text('Rename'));
      await settle(tester);
      expect(find.text('Name this chat'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Market list');
      await tester.tap(find.text('Save name'));
      await settle(tester);
      expect(s.lastArgs('chat_rename'), <String, Object?>{
        'chatId': 'c2',
        'title': 'Market list',
      });

      await tester.longPress(find.text('Groceries'));
      await settle(tester);
      await tester.tap(find.text('Pin'));
      await settle(tester);
      expect(s.lastArgs('chat_pin'), <String, Object?>{
        'chatId': 'c2',
        'pinned': true,
      });

      await tester.longPress(find.text('Groceries'));
      await settle(tester);
      await tester.tap(find.text('Archive'));
      await settle(tester);
      expect(s.lastArgs('chat_archive'), <String, Object?>{
        'chatId': 'c2',
        'archived': true,
      });
    });

    testWidgets('refuses an empty name without asking the server', (
      tester,
    ) async {
      final s = twoChats();
      await open(tester, s);
      await openDrawer(tester);
      await tester.longPress(find.text('Groceries'));
      await settle(tester);
      await tester.tap(find.text('Rename'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, '   ');
      await tester.tap(find.text('Save name'));
      await settle(tester);
      expect(
        find.text('Give it a name of 1 to 80 characters.'),
        findsOneWidget,
      );
      expect(s.count('chat_rename'), 0);
    });

    testWidgets('a failed rename leaves the sheet open with the words kept', (
      tester,
    ) async {
      final s = twoChats()..failVerbs.add('chat_rename');
      await open(tester, s);
      await openDrawer(tester);
      await tester.longPress(find.text('Groceries'));
      await settle(tester);
      await tester.tap(find.text('Rename'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, 'Market list');
      await tester.tap(find.text('Save name'));
      await settle(tester);
      expect(find.text('Name this chat'), findsOneWidget);
      expect(find.text('Market list'), findsOneWidget);
    });

    testWidgets(
      'a chat that cannot be opened leaves the drawer and the screen as they were',
      (tester) async {
        final s = twoChats()..failVerbs.add('chat_open');
        await open(tester, s);
        await openDrawer(tester);
        await tester.tap(find.text('Groceries'));
        await settle(tester);
        await settle(tester);
        expect(find.text('Pinned'), findsOneWidget);
        expect(find.text('plan the week'), findsOneWidget);
        expect(s.count('chat_history'), 1);
      },
    );

    testWidgets(
      'keeps the unsent words of each chat while another one is open',
      (tester) async {
        final s = twoChats();
        await open(tester, s);
        await tester.enterText(find.byType(TextField).first, 'half written');
        await openDrawer(tester);
        s.history = <String, Object?>{
          'chat': head('c2', 'Groceries'),
          'turns': <Object?>[turn('buy rice', reply: 'Noted.', id: 'g0')],
        };
        await tester.tap(find.text('Groceries'));
        await settle(tester);
        await settle(tester);
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller
              ?.text,
          '',
        );
        await tester.enterText(find.byType(TextField).first, 'rice and beans');
        await openDrawer(tester);
        s.history = <String, Object?>{
          'chat': head('c1', 'Weekly plan'),
          'turns': <Object?>[
            turn('plan the week', reply: 'Here is a plan.', id: 'm0'),
          ],
        };
        await tester.tap(find.text('Weekly plan'));
        await settle(tester);
        await settle(tester);
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller
              ?.text,
          'half written',
        );
      },
    );

    testWidgets(
      'shows the archive on its own, and a gentle note when it is empty',
      (tester) async {
        final s = twoChats();
        await open(tester, s);
        await openDrawer(tester);
        s.chatList = <String, Object?>{'chats': <Object?>[]};
        await tester.tap(find.text('Archived chats'));
        await settle(tester);
        expect(s.lastArgs('chat_list'), <String, Object?>{'archived': true});
        expect(find.text('Nothing is archived.'), findsOneWidget);
      },
    );

    testWidgets('shows a retry when the list cannot load', (tester) async {
      final s = twoChats()..failVerbs.add('chat_list');
      final container = await open(tester, s);
      await openDrawer(tester);
      expect(find.text('Try again'), findsOneWidget);
      // A failed request is tried again by a timer: take the screen down so none is left pending
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });

    testWidgets('waits while Botler is answering, and offers Stop', (
      tester,
    ) async {
      final s = twoChats();
      await open(tester, s);
      await tester.enterText(find.byType(TextField).first, 'one more thing');
      await tester.tap(find.byTooltip('Send'));
      await settle(tester);
      s.emit(<String, Object?>{
        'type': 'start',
        'turnId': 't9',
        'chatId': 'c1',
      });
      await settle(tester);
      await openDrawer(tester);
      expect(
        find.text(
          'Botler is answering. Wait for it, or stop it, to change chats.',
        ),
        findsOneWidget,
      );
      final button = tester.widget<ButtonStyleButton>(
        find.widgetWithText(FilledButton, 'New chat'),
      );
      expect(button.onPressed, isNull);
      expect(find.text('Stop'), findsOneWidget);
      expect(s.count('chat_open'), 0);
      s.emit(<String, Object?>{
        'type': 'done',
        'reply': 'ok',
        'toolsRun': <Object?>[],
      });
      unawaited(s.streams.last.close());
      await settle(tester);
    });
  });

  group('messages', () {
    testWidgets(
      'a double tap on send while editing rewinds once and sends once',
      (tester) async {
        final s = twoChats();
        await open(tester, s);
        s.answers['chat_rewind'] = <String, Object?>{
          'chatId': 'c1',
          'removed': 1,
        };
        s.forkGate = Completer<void>();
        s.history = <String, Object?>{
          'chat': head('c1', 'Weekly plan'),
          'turns': <Object?>[],
        };
        await tester.longPress(find.text('and friday?'));
        await settle(tester);
        await tester.tap(find.text('Edit and resend'));
        await settle(tester);
        await tester.enterText(find.byType(TextField).first, 'and sunday?');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.byTooltip('Send'));
        await tester.pump(const Duration(milliseconds: 50));
        s.forkGate!.complete();
        await settle(tester);
        await settle(tester);
        expect(s.count('chat_rewind'), 1);
        expect(s.count('chat_fork'), 0);
        expect(s.sentBodies, hasLength(1));
        expect(s.sentBodies.single['chatId'], 'c1');
        s.emit(<String, Object?>{
          'type': 'done',
          'reply': 'ok',
          'toolsRun': <Object?>[],
        });
        unawaited(s.streams.last.close());
        await settle(tester);
      },
    );

    testWidgets(
      'a message sent while a branch is being made stays in its own chat',
      (tester) async {
        final s = twoChats();
        await open(tester, s);
        s.answers['chat_fork'] = <String, Object?>{
          'chatId': 'c-fork',
          'turns': 1,
        };
        s.forkGate = Completer<void>();
        await tester.longPress(find.text('plan the week'));
        await settle(tester);
        await tester.tap(find.text('Branch from here'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.enterText(find.byType(TextField).first, 'quick one');
        await tester.tap(find.byTooltip('Send'));
        await settle(tester);
        expect(s.sentBodies.last['chatId'], 'c1');
        s.forkGate!.complete();
        await settle(tester);
        await settle(tester);
        // The branch was made, but the screen stays with the chat that is answering
        expect(find.text('quick one'), findsOneWidget);
        expect(find.textContaining('Branched from'), findsNothing);
        s.emit(<String, Object?>{'type': 'delta', 'text': 'Done.'});
        s.emit(<String, Object?>{
          'type': 'done',
          'reply': 'Done.',
          'toolsRun': <Object?>[],
        });
        unawaited(s.streams.last.close());
        await settle(tester);
        expect(find.text('Done.'), findsOneWidget);
      },
    );

    testWidgets(
      'an approval card copied into a branch can only be answered in the original chat',
      (tester) async {
        final card = <String, Object?>{
          'type': 'card',
          'actionId': 'a1',
          'summary': 'Add the bill "Gym".',
          'status': 'pending',
        };
        final s = RestoreServer()
          ..history = <String, Object?>{
            'chat': head('c-fork', 'Gym'),
            'turns': <Object?>[
              <String, Object?>{
                ...turn(
                  'add a gym bill',
                  reply: 'Please check.',
                  id: 'x1',
                  events: <Map<String, Object?>>[card],
                ),
                'copied': true,
              },
              turn(
                'another',
                reply: 'ok',
                id: 'x2',
                events: <Map<String, Object?>>[card],
              ),
            ],
          };
        await open(tester, s);
        expect(
          find.text('Waiting for your answer in the chat it came from.'),
          findsOneWidget,
        );
        // The card of the message said here keeps its button
        expect(find.text('Approve'), findsOneWidget);
      },
    );

    testWidgets(
      'go to the chat on screen, and a message learns its id from the server',
      (tester) async {
        final s = twoChats();
        await open(tester, s);
        await tester.enterText(find.byType(TextField).first, 'and saturday?');
        await tester.tap(find.byTooltip('Send'));
        await settle(tester);
        expect(s.sentBodies.last['chatId'], 'c1');
        s.emit(<String, Object?>{
          'type': 'start',
          'turnId': 't7',
          'chatId': 'c1',
        });
        s.emit(<String, Object?>{'type': 'delta', 'text': 'Saturday is free.'});
        s.emit(<String, Object?>{
          'type': 'done',
          'reply': 'Saturday is free.',
          'toolsRun': <Object?>[],
        });
        unawaited(s.streams.last.close());
        await settle(tester);
        // Now it can be branched from
        await tester.longPress(find.text('and saturday?'));
        await settle(tester);
        expect(find.text('Branch from here'), findsOneWidget);
        expect(find.text('Edit and resend'), findsOneWidget);
        expect(find.text('Copy'), findsOneWidget);
      },
    );

    testWidgets(
      'branches from a message into a new chat that says where it came from',
      (tester) async {
        final s = twoChats();
        await open(tester, s);
        s.answers['chat_fork'] = <String, Object?>{
          'chatId': 'c-fork',
          'turns': 1,
        };
        s.history = <String, Object?>{
          'chat': head(
            'c-fork',
            'Weekly plan',
            from: <String, Object?>{'id': 'c1', 'title': 'Weekly plan'},
          ),
          'turns': <Object?>[
            turn('plan the week', reply: 'Here is a plan.', id: 'f0'),
          ],
        };
        await tester.longPress(find.text('plan the week'));
        await settle(tester);
        await tester.tap(find.text('Branch from here'));
        await settle(tester);
        await settle(tester);
        expect(s.lastArgs('chat_fork'), <String, Object?>{
          'chatId': 'c1',
          'upToTurnId': 'row-m0',
        });
        expect(s.lastArgs('chat_history'), <String, Object?>{
          'chatId': 'c-fork',
        });
        expect(find.text('Branched from Weekly plan'), findsOneWidget);
        expect(
          find.text(
            'Changes saved before this point stay saved. Undo them in History.',
          ),
          findsOneWidget,
        );
        expect(find.text('and friday?'), findsNothing);
        // Tapping the line goes back to the original
        s.history = <String, Object?>{
          'chat': head('c1', 'Weekly plan'),
          'turns': <Object?>[
            turn('plan the week', reply: 'Here is a plan.', id: 'm0'),
          ],
        };
        await tester.tap(find.text('Branched from Weekly plan'));
        await settle(tester);
        await settle(tester);
        expect(s.lastArgs('chat_open'), <String, Object?>{'chatId': 'c1'});
        expect(find.text('Branched from Weekly plan'), findsNothing);
      },
    );

    testWidgets(
      'edit and resend: the messages are taken out of the same chat, no chat is made, then the new words are sent there',
      (tester) async {
        final s = twoChats();
        await open(tester, s);
        s.answers['chat_rewind'] = <String, Object?>{
          'chatId': 'c1',
          'removed': 1,
        };
        s.history = <String, Object?>{
          'chat': head('c1', 'Weekly plan'),
          'turns': <Object?>[
            turn('plan the week', reply: 'Here is a plan.', id: 'm0'),
          ],
        };
        await tester.longPress(find.text('and friday?'));
        await settle(tester);
        await tester.tap(find.text('Edit and resend'));
        await settle(tester);
        expect(find.text('Editing your message'), findsOneWidget);
        final box = find.byType(TextField).first;
        expect(tester.widget<TextField>(box).controller?.text, 'and friday?');
        await tester.enterText(box, 'and sunday?');
        await tester.tap(find.byTooltip('Send'));
        await settle(tester);
        await settle(tester);
        expect(s.lastArgs('chat_rewind'), <String, Object?>{
          'chatId': 'c1',
          'fromTurnId': 'row-m1',
        });
        // Nothing was copied, and the words go to the very same chat
        expect(s.count('chat_fork'), 0);
        expect(s.sentBodies.last['chatId'], 'c1');
        expect(s.sentBodies.last['text'], 'and sunday?');
        expect(find.text('Editing your message'), findsNothing);
        s.emit(<String, Object?>{
          'type': 'done',
          'reply': 'ok',
          'toolsRun': <Object?>[],
        });
        unawaited(s.streams.last.close());
        await settle(tester);
      },
    );

    testWidgets('a failed rewind keeps the edited words and sends nothing', (
      tester,
    ) async {
      final s = twoChats()..failVerbs.add('chat_rewind');
      await open(tester, s);
      await tester.longPress(find.text('and friday?'));
      await settle(tester);
      await tester.tap(find.text('Edit and resend'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, 'and sunday?');
      await tester.tap(find.byTooltip('Send'));
      await settle(tester);
      await settle(tester);
      expect(s.sentBodies, isEmpty);
      expect(s.count('chat_fork'), 0);
      expect(find.text('Editing your message'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        'and sunday?',
      );
    });

    testWidgets('stop editing empties the box and leaves the chat as it was', (
      tester,
    ) async {
      final s = twoChats();
      await open(tester, s);
      await tester.longPress(find.text('and friday?'));
      await settle(tester);
      await tester.tap(find.text('Edit and resend'));
      await settle(tester);
      await tester.tap(find.byTooltip('Stop editing'));
      await settle(tester);
      expect(find.text('Editing your message'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        '',
      );
      expect(s.count('chat_rewind'), 0);
    });
  });
}
