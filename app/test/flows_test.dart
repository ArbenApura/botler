// THE FLOWS A PERSON SEES: A CHAT MESSAGE BECOMING A LOGGED EXPENSE WITH UNDO, A CONFIRMATION CHIP, AN APPROVAL CARD, THE PAYDAY SPLIT CARD, AN EXPENSE WRITTEN
// DOWN OFFLINE, AND THE APP LOCK. THE SERVER IS A STAND-IN THAT ANSWERS LIKE THE REAL ONE.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/features/auth/lock_gate.dart';
import 'package:botler/features/chat/chat_items.dart';
import 'package:botler/features/chat/chat_state.dart';
import 'package:botler/features/expense/expense_screen.dart';
import 'package:botler/features/payday/split_card.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- TYPES -- //

/// A stand-in server: counts calls per path and answers from a table.
class FakeServer {
  FakeServer({this.chatEvents = const <Json>[]});

  final List<Json> chatEvents;
  final Map<String, int> calls = <String, int>{};
  final Map<String, List<Json>> bodies = <String, List<Json>>{};
  final Map<String, Object?> results = <String, Object?>{};
  bool offline = false;
  int chatFailures = 0;

  MockClient get client => MockClient.streaming((req, stream) async {
    final path = req.url.path;
    final body = await http.ByteStream(stream).bytesToString();
    calls[path] = (calls[path] ?? 0) + 1;
    (bodies[path] ??= <Json>[]).add(decodeJson(body));
    if (offline) throw http.ClientException('offline');
    if (path == '/api/v1/agent/chat') {
      if (chatFailures > 0) {
        chatFailures--;
        throw http.ClientException('dropped');
      }
      final text = chatEvents.map((e) => 'data: ${jsonEncode(e)}\n\n').join();
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(text)),
        200,
      );
    }
    final verb = path.split('/').last;
    final result = results[verb] ?? <String, Object?>{};
    return http.StreamedResponse(
      Stream<List<int>>.value(
        utf8.encode(
          jsonEncode(<String, Object?>{'result': result, 'action': result}),
        ),
      ),
      200,
    );
  });
}

// -- FUNCTIONS -- //

Future<ProviderContainer> containerFor(
  FakeServer s, {
  Map<String, Object> prefs = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
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

const List<Json> accounts = <Json>[
  <String, Object?>{'id': 'acc-gcash', 'name': 'GCash', 'balance': 0},
  <String, Object?>{'id': 'acc-rcbc', 'name': 'RCBC', 'balance': 50000},
];

void main() {
  group('chat', () {
    test('a logged expense appears as a plain line with the reply, and undo goes through the journal', () async {
      final s = FakeServer(
        chatEvents: <Json>[
          <String, Object?>{
            'type': 'tool',
            'name': 'expense_from_text',
            'status': 'ok',
            'data': <String, Object?>{
              'status': 'saved',
              'txn': <String, Object?>{
                'id': 'txn-1',
                'amount': 18000,
                'accountId': 'acc-gcash',
              },
            },
          },
          <String, Object?>{'type': 'delta', 'text': 'Logged '},
          <String, Object?>{'type': 'delta', 'text': 'your lunch.'},
          <String, Object?>{
            'type': 'done',
            'reply': 'Logged your lunch.',
            'toolsRun': <String>['expense_from_text'],
          },
        ],
      );
      final c = await containerFor(s);
      await c.read(chatProvider.notifier).send('lunch 180 gcash');
      final items = c.read(chatProvider).items;
      expect(items.map((i) => i.runtimeType).toList(), <Type>[
        UserItem,
        ToolItem,
        AgentItem,
      ]);
      expect((items.last as AgentItem).text, 'Logged your lunch.');
      expect((items.last as AgentItem).streaming, false);
      expect(c.read(chatProvider).busy, false);
      expect(s.bodies['/api/v1/agent/chat']?.single['text'], 'lunch 180 gcash');
    });

    test('a dropped connection is sent again under the same message id and shown once', () async {
      final s = FakeServer(
        chatEvents: <Json>[
          <String, Object?>{'type': 'delta', 'text': 'Hello'},
          <String, Object?>{
            'type': 'done',
            'reply': 'Hello',
            'toolsRun': <String>[],
          },
        ],
      )..chatFailures = 1;
      final c = await containerFor(s);
      await c.read(chatProvider.notifier).send('hi');
      final sent = s.bodies['/api/v1/agent/chat'] ?? <Json>[];
      expect(sent, hasLength(2));
      expect(sent[0]['clientMessageId'], sent[1]['clientMessageId']);
      expect(c.read(chatProvider).items.whereType<AgentItem>(), hasLength(1));
      expect(c.read(chatProvider).items.whereType<UserItem>(), hasLength(1));
    });

    test('an expense typed with no connection is kept on the phone and goes out once later', () async {
      final s = FakeServer()..offline = true;
      final c = await containerFor(s);
      await c.read(chatProvider.notifier).send('lunch 180 gcash');
      expect(
        c.read(chatProvider).items.whereType<NoticeItem>().single.text,
        contains('Saved on your phone'),
      );
      final box = c.read(outboxProvider);
      expect(box.length, 1);
      expect(box.items().single.verb, 'expense_from_text');
      s.offline = false;
      final report = await box.flush(c.read(apiProvider));
      expect(report.sent, 1);
      expect(
        s.bodies['/api/v1/do/expense_from_text']?.single['text'],
        'lunch 180 gcash',
      );
      await box.flush(c.read(apiProvider));
      expect(s.calls['/api/v1/do/expense_from_text'], 1);
    });

    test('words with no number are not kept for later', () async {
      final s = FakeServer()..offline = true;
      final c = await containerFor(s);
      await c.read(chatProvider.notifier).send('how am I doing?');
      expect(c.read(outboxProvider).length, 0);
      expect(c.read(chatProvider).items.whereType<NoticeItem>(), hasLength(1));
    });

    test(
      'a failing model shows the manual form, a card shows what needs a yes',
      () async {
        final s = FakeServer(
          chatEvents: <Json>[
            <String, Object?>{
              'type': 'card',
              'actionId': 'act-1',
              'summary': 'Add the bill "Gym", ₱1,500.00.',
            },
            <String, Object?>{
              'type': 'fallback',
              'reason': 'capped',
              'form': 'expense',
            },
            <String, Object?>{
              'type': 'done',
              'reply': '',
              'toolsRun': <String>[],
            },
          ],
        );
        final c = await containerFor(s);
        await c.read(chatProvider.notifier).send('add a gym bill');
        final items = c.read(chatProvider).items;
        expect(
          items.whereType<CardItem>().single.summary,
          'Add the bill "Gym", ₱1,500.00.',
        );
        expect(items.whereType<FallbackItem>().single.reason, 'capped');
      },
    );
  });

  group('screens', () {
    Widget app(ProviderContainer c, Widget home) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: home)),
      ),
    );

    testWidgets(
      'an approval card shows the sentence and one primary button, and approving tells the server',
      (tester) async {
        final s = FakeServer()
          ..results['act-1'] = <String, Object?>{'status': 'applied'};
        final c = await containerFor(s);
        c.read(chatProvider.notifier).notice('start');
        await tester.pumpWidget(
          app(
            c,
            const ChatItemView(
              CardItem(1, actionId: 'act-1', summary: 'Add the account "BPI".'),
            ),
          ),
        );
        expect(find.text('Add the account "BPI".'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
        await tester.tap(find.text('Approve'));
        await tester.pumpAndSettle();
        expect(
          s.bodies['/api/v1/agent/actions/act-1']?.single['decision'],
          'approve',
        );
      },
    );

    testWidgets(
      'the payday split lists where every peso goes, and cannot be approved when the pay is short',
      (tester) async {
        final s = FakeServer();
        final c = await containerFor(s);
        final plan = <String, Object?>{
          'id': 'p1',
          'status': 'proposed',
          'payday': '2026-11-30',
          'pay': 2500000,
          'gap': 0,
          'sentTransfers': <Object?>[],
          'result': <String, Object?>{
            'status': 'ok',
            'accountNames': <String, Object?>{
              'acc-rcbc': 'RCBC',
              'acc-gcash': 'GCash',
            },
            'lines': <Json>[
              <String, Object?>{
                'label': 'Rent',
                'amount': 800000,
                'accountId': 'acc-rcbc',
              },
              <String, Object?>{
                'label': 'Rest',
                'amount': 1700000,
                'accountId': 'acc-gcash',
              },
            ],
            'transfers': <Json>[
              <String, Object?>{
                'fromAccountId': 'acc-rcbc',
                'toAccountId': 'acc-gcash',
                'amount': 1700000,
              },
            ],
          },
        };
        await tester.pumpWidget(app(c, SplitCard(plan: plan)));
        expect(find.text('Rent  ·  RCBC'), findsOneWidget);
        expect(find.text('₱17,000.00'), findsWidgets);
        expect(find.text('RCBC → GCash'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, 'Approve split'),
          findsOneWidget,
        );

        final short = <String, Object?>{
          ...plan,
          'status': 'shortfall',
          'gap': 80000,
          'result': <String, Object?>{
            'status': 'shortfall',
            'cutOptions': <Json>[
              <String, Object?>{'label': 'Emergency fund', 'amount': 150000},
            ],
            'accountNames': <String, Object?>{},
          },
        };
        await tester.pumpWidget(
          app(c, SplitCard(key: const ValueKey<int>(2), plan: short)),
        );
        expect(find.textContaining('₱800.00 short'), findsOneWidget);
        expect(find.text('Emergency fund'), findsOneWidget);
        expect(find.text('Approve split'), findsNothing);
      },
    );

    testWidgets(
      'the expense form works offline: it keeps the entry, and tells the person',
      (tester) async {
        final s = FakeServer()..offline = true;
        final c = await containerFor(
          s,
          prefs: <String, Object>{'accounts.cache': jsonEncode(accounts)},
        );
        final router = GoRouter(
          routes: <RouteBase>[
            GoRoute(path: '/', builder: (_, _) => const ExpenseScreen()),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp.router(
              theme: buildTheme(Brightness.light),
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('GCash'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextField, 'How much? (pesos)'),
          '180',
        );
        await tester.tap(find.text('Log it'));
        await tester.pumpAndSettle();
        final box = c.read(outboxProvider);
        expect(box.items().single.verb, 'expense_log');
        expect(box.items().single.args['amount'], 18000);
        expect(box.items().single.args['accountId'], 'acc-gcash');
      },
    );
  });

  group('the app lock', () {
    Widget gate(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const LockGate(child: Text('Secret balance ₱1,000')),
      ),
    );

    testWidgets(
      'stays locked after a wrong finger, and opens after the right one',
      (tester) async {
        var ok = false;
        final s = FakeServer();
        SharedPreferences.setMockInitialValues(<String, Object>{
          'settings.lock': true,
        });
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
            authenticateProvider.overrideWithValue(() async => ok),
          ],
        );
        addTearDown(c.dispose);
        await tester.pumpWidget(gate(c));
        await tester.pumpAndSettle();
        expect(find.text('Botler is locked'), findsOneWidget);
        expect(find.textContaining('Secret balance'), findsNothing);
        ok = true;
        await tester.tap(find.text('Unlock'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Secret balance'), findsOneWidget);
      },
    );

    testWidgets('does nothing when the lock is off', (tester) async {
      final c = await containerFor(FakeServer());
      await tester.pumpWidget(gate(c));
      await tester.pumpAndSettle();
      expect(find.textContaining('Secret balance'), findsOneWidget);
    });
  });
}
