// BRINGING BACK THE EARLIER CONVERSATION: ONCE, READ-ONLY, SILENT WHEN IT FAILS, NEVER MOVING A TURN THAT IS RUNNING, NEVER SHOWING A TURN TWICE.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/features/chat/chat_state.dart';
import 'package:botler/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- TYPES -- //

/// A server that answers the history call from a table and lets the test feed the chat stream by hand.
class RestoreServer {
  Object history = <String, Object?>{'turns': <Object?>[]};
  bool historyFails = false;
  Completer<void>? historyGate;

  /// Holds the answer to chat_fork and chat_rewind until the test lets it go.
  Completer<void>? forkGate;
  int historyCalls = 0;
  int newCalls = 0;

  /// What chat_list answers, and what any other verb named here answers (anything else gets an empty result).
  Object chatList = <String, Object?>{'chats': <Object?>[]};
  final Map<String, Object?> answers = <String, Object?>{};

  /// Every verb called, in order, with its arguments.
  final List<(String, Json)> calls = <(String, Json)>[];
  Json? lastArgs(String verb) =>
      calls.where((c) => c.$1 == verb).map((c) => c.$2).lastOrNull;
  int count(String verb) => calls.where((c) => c.$1 == verb).length;
  final List<StreamController<List<int>>> streams =
      <StreamController<List<int>>>[];
  final List<String> sentIds = <String>[];

  /// The body of every message sent to the chat stream.
  final List<Json> sentBodies = <Json>[];

  /// Verbs that fail with a server error.
  final Set<String> failVerbs = <String>{};

  MockClient get client => MockClient.streaming((req, body) async {
    final text = await http.ByteStream(body).bytesToString();
    final verb = req.url.path.contains('/do/')
        ? req.url.pathSegments.last
        : null;
    if (verb != null) {
      final args = text.isEmpty ? <String, Object?>{} : decodeJson(text);
      calls.add((verb, args));
    }
    http.StreamedResponse reply(Object? result) => http.StreamedResponse(
      Stream<List<int>>.value(
        utf8.encode(jsonEncode(<String, Object?>{'result': result})),
      ),
      200,
    );
    if (verb != null && failVerbs.contains(verb)) {
      return http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{
                'code': 'INTERNAL',
                'message': 'Something went wrong.',
              },
            }),
          ),
        ),
        500,
      );
    }
    if (verb == 'chat_history') {
      historyCalls++;
      await historyGate?.future;
      if (historyFails) throw http.ClientException('offline');
      return reply(history);
    }
    if (verb == 'chat_fork' || verb == 'chat_rewind') await forkGate?.future;
    if (verb == 'chat_new') {
      newCalls++;
      return reply(<String, Object?>{'chatId': 'chat-new', 'created': true});
    }
    if (verb == 'chat_list') return reply(chatList);
    if (verb != null) return reply(answers[verb] ?? <String, Object?>{});
    sentBodies.add(decodeJson(text));
    sentIds.add(str(decodeJson(text)['clientMessageId']));
    final controller = StreamController<List<int>>();
    streams.add(controller);
    return http.StreamedResponse(controller.stream, 200);
  });

  void emit(Json event, [int which = -1]) {
    final c = which < 0 ? streams.last : streams[which];
    c.add(utf8.encode('data: ${jsonEncode(event)}\n\n'));
  }
}

// -- FUNCTIONS -- //

Future<ProviderContainer> containerFor(RestoreServer s) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(p),
      apiProvider.overrideWithValue(
        ApiClient(
          base: 'https://botler.test',
          token: () async => 'tok',
          client: s.client,
        ),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Json turn(
  String text, {
  String reply = '',
  String status = 'done',
  List<Json> events = const <Json>[],
  String id = 'earlier-1',
}) => <String, Object?>{
  'id': 'row-$id',
  'clientMessageId': id,
  'text': text,
  'reply': reply,
  'status': status,
  'at': '2026-10-22T01:00:00.000Z',
  'events': events,
};

Future<void> settle([int ms = 0]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  group('bringing back the conversation', () {
    test('puts each earlier turn in order as read-only items, apart from the live ones', () async {
      final s = RestoreServer()
        ..history = <String, Object?>{
          'turns': <Json>[
            turn(
              'lunch 180',
              reply: 'Logged it.',
              id: 'a',
              events: <Json>[
                <String, Object?>{
                  'type': 'tool',
                  'name': 'expense_log',
                  'status': 'ok',
                  'data': <String, Object?>{
                    'status': 'saved',
                    'txn': <String, Object?>{'amount': 18000, 'id': 't1'},
                  },
                },
                <String, Object?>{
                  'type': 'card',
                  'actionId': 'x1',
                  'summary': 'Add the bill "Gym".',
                  'status': 'pending',
                },
              ],
            ),
            turn('hello', reply: 'Hi!', id: 'b'),
          ],
        };
      final c = await containerFor(s);
      await c.read(chatProvider.notifier).restore();
      final state = c.read(chatProvider);
      expect(state.items, isEmpty);
      expect(state.restored.map((i) => i.runtimeType).toList(), <Type>[
        UserItem,
        ToolItem,
        CardItem,
        AgentItem,
        UserItem,
        AgentItem,
      ]);
      expect((state.restored[1] as ToolItem).restored, true);
      expect((state.restored[2] as CardItem).state, CardState.waiting);
      expect(state.restored.map((i) => i.id).toSet(), hasLength(6));
    });

    test(
      'asks the server once, however often it is asked to restore',
      () async {
        final s = RestoreServer();
        final c = await containerFor(s);
        final chat = c.read(chatProvider.notifier);
        await chat.restore();
        await chat.restore();
        await Future.wait(<Future<void>>[chat.restore(), chat.restore()]);
        expect(s.historyCalls, 1);
      },
    );

    test('says nothing when it fails, and may try again later', () async {
      final s = RestoreServer()..historyFails = true;
      final c = await containerFor(s);
      final chat = c.read(chatProvider.notifier);
      await chat.restore();
      expect(c.read(chatProvider).restored, isEmpty);
      expect(c.read(chatProvider).items, isEmpty);
      s
        ..historyFails = false
        ..history = <String, Object?>{
          'turns': <Json>[turn('hello', reply: 'Hi!')],
        };
      await chat.restore();
      expect(c.read(chatProvider).restored, hasLength(2));
    });

    test('copes with an empty or odd answer', () async {
      final s = RestoreServer()..history = <String, Object?>{};
      final c = await containerFor(s);
      await c.read(chatProvider.notifier).restore();
      expect(c.read(chatProvider).restored, isEmpty);
    });

    test('shows every kind of card as what it is now, and an expired one is not answerable', () async {
      Json card(String status) => <String, Object?>{
        'type': 'card',
        'actionId': 'id-$status',
        'summary': 'Add.',
        'status': status,
      };
      final s = RestoreServer()
        ..history = <String, Object?>{
          'turns': <Json>[
            turn(
              'x',
              events: <Json>[
                card('pending'),
                card('applied'),
                card('rejected'),
                card('failed'),
                card('expired'),
                card('gone'),
              ],
            ),
          ],
        };
      final c = await containerFor(s);
      await c.read(chatProvider.notifier).restore();
      expect(
        c.read(chatProvider).restored.whereType<CardItem>().map((i) => i.state),
        <CardState>[
          CardState.waiting,
          CardState.approved,
          CardState.declined,
          CardState.failed,
          CardState.expired,
          CardState.expired,
        ],
      );
    });

    test(
      'a turn that failed with no answer keeps the person\'s words and says so',
      () async {
        final s = RestoreServer()
          ..history = <String, Object?>{
            'turns': <Json>[turn('broke', status: 'failed')],
          };
        final c = await containerFor(s);
        await c.read(chatProvider.notifier).restore();
        final r = c.read(chatProvider).restored;
        expect(r.map((i) => i.runtimeType).toList(), <Type>[
          UserItem,
          NoticeItem,
        ]);
      },
    );

    test('does not show again a turn that was sent in this run', () async {
      final s = RestoreServer();
      final c = await containerFor(s);
      final chat = c.read(chatProvider.notifier);
      final run = chat.send('hi there');
      await settle(20);
      final mine = s.sentIds.single;
      s.history = <String, Object?>{
        'turns': <Json>[
          turn('hi there', reply: 'Hello', id: mine),
          turn('older', reply: 'Yes', id: 'older-1'),
        ],
      };
      await chat.restore();
      expect(
        c.read(chatProvider).restored.whereType<UserItem>().map((i) => i.text),
        <String>['older'],
      );
      s.emit(<String, Object?>{'type': 'done', 'reply': '', 'toolsRun': []});
      await s.streams.last.close();
      await run;
    });

    test('a restore that lands while a retry waits leaves the message and the turn alone', () async {
      final s = RestoreServer()..historyGate = Completer<void>();
      final c = await containerFor(s);
      final chat = c.read(chatProvider.notifier);
      final restoring = chat.restore();
      final run = chat.send('hi there');
      await settle(20);
      s.emit(<String, Object?>{'type': 'delta', 'text': 'Hel'});
      await settle(60);
      // The connection drops with no "done": the screen is cut back to the message and the wait for the retry begins
      await s.streams[0].close();
      await settle(100);
      s
        ..history = <String, Object?>{
          'turns': <Json>[turn('older', reply: 'Yes', id: 'older-1')],
        }
        ..historyGate!.complete();
      await restoring;
      await settle(2100);
      s.emit(<String, Object?>{'type': 'delta', 'text': 'Hello'}, 1);
      s.emit(<String, Object?>{
        'type': 'done',
        'reply': 'Hello',
        'toolsRun': <String>[],
      }, 1);
      await s.streams[1].close();
      await run;
      final state = c.read(chatProvider);
      expect(state.items.whereType<UserItem>().map((i) => i.text), <String>[
        'hi there',
      ]);
      expect(state.items.whereType<AgentItem>().single.text, 'Hello');
      expect(state.restored.whereType<UserItem>().single.text, 'older');
      expect(
        <ChatItem>[...state.restored, ...state.items].map((i) => i.id).toSet(),
        hasLength(state.restored.length + state.items.length),
      );
    });

    test(
      'an answer that arrives after another person signed in is thrown away',
      () async {
        final s = RestoreServer()
          ..historyGate = Completer<void>()
          ..history = <String, Object?>{
            'turns': <Json>[turn('the old person', reply: 'ok')],
          };
        final c = await containerFor(s);
        final late = c.read(chatProvider.notifier).restore();
        await settle(20);
        c.invalidate(chatProvider);
        expect(c.read(chatProvider).restored, isEmpty);
        s.historyGate!.complete();
        await late;
        expect(c.read(chatProvider).restored, isEmpty);
      },
    );

    test(
      'a card that came back can still be answered, and then it changes',
      () async {
        final s = RestoreServer()
          ..history = <String, Object?>{
            'turns': <Json>[
              turn(
                'add gym',
                events: <Json>[
                  <String, Object?>{
                    'type': 'card',
                    'actionId': 'x1',
                    'summary': 'Add the bill "Gym".',
                    'status': 'pending',
                  },
                ],
              ),
            ],
          };
        final c = await containerFor(s);
        final chat = c.read(chatProvider.notifier);
        await chat.restore();
        final card = c.read(chatProvider).restored.whereType<CardItem>().single;
        chat.setCard(card.id, CardState.approved);
        expect(
          c.read(chatProvider).restored.whereType<CardItem>().single.state,
          CardState.approved,
        );
      },
    );

    test(
      'starts over for another person: nothing is kept and it asks again',
      () async {
        final s = RestoreServer()
          ..history = <String, Object?>{
            'turns': <Json>[turn('mine', reply: 'ok')],
          };
        final c = await containerFor(s);
        await c.read(chatProvider.notifier).restore();
        expect(c.read(chatProvider).restored, isNotEmpty);
        c.invalidate(chatProvider);
        expect(c.read(chatProvider).restored, isEmpty);
        await c.read(chatProvider.notifier).restore();
        expect(s.historyCalls, 2);
      },
    );
  });
}
