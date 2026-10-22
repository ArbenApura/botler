// THE LIVE CHAT STATE: STATUS, THINKING, RUNNING TOOLS AND THE GROWING ANSWER, DRAWN IN BATCHES, STOPPED ON REQUEST AND CLEANED UP WHEN A TURN ENDS.

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

/// A server whose chat stream the test feeds by hand, one event at a time.
class LiveServer {
  final List<StreamController<List<int>>> streams =
      <StreamController<List<int>>>[];
  int requests = 0;

  MockClient get client => MockClient.streaming((req, body) async {
    await body.drain<void>();
    requests++;
    final controller = StreamController<List<int>>();
    streams.add(controller);
    // Stopping the request ends the stream with an abort, as the real client does
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

  StreamController<List<int>> get current => streams.last;

  void emit(Json event, [int which = -1]) {
    final c = which < 0 ? current : streams[which];
    c.add(utf8.encode('data: ${jsonEncode(event)}\n\n'));
  }
}

// -- FUNCTIONS -- //

Future<ProviderContainer> containerFor(LiveServer s) async {
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

Future<void> settle([int ms = 0]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

Json ev(String type, [Map<String, Object?> more = const <String, Object?>{}]) =>
    <String, Object?>{'type': type, ...more};

void main() {
  group('the live turn', () {
    test(
      'shows each stage while the assistant works and cleans up at the end',
      () async {
        final s = LiveServer();
        final c = await containerFor(s);
        final chat = c.read(chatProvider.notifier);
        final run = chat.send('what do I have?');
        await settle();
        expect(c.read(chatProvider).busy, true);
        expect(c.read(chatProvider).phase, TurnPhase.waiting);

        s.emit(ev('start'));
        s.emit(ev('phase', <String, Object?>{'phase': 'thinking'}));
        s.emit(ev('reasoning', <String, Object?>{'text': 'Let me '}));
        s.emit(ev('reasoning', <String, Object?>{'text': 'look.'}));
        await settle(80);
        var items = c.read(chatProvider).items;
        expect(c.read(chatProvider).phase, TurnPhase.thinking);
        final thought = items.whereType<ThinkingItem>().single;
        expect(thought.text, 'Let me look.');
        expect(thought.open, true);

        s.emit(
          ev('tool_start', <String, Object?>{
            'id': 'call_1',
            'name': 'accounts_list',
          }),
        );
        await settle(10);
        items = c.read(chatProvider).items;
        expect(c.read(chatProvider).phase, TurnPhase.tool);
        expect(c.read(chatProvider).toolName, 'accounts_list');
        expect(items.whereType<ThinkingItem>().single.open, false);
        final running = items.whereType<ToolItem>().single;
        expect(running.running, true);

        s.emit(
          ev('tool', <String, Object?>{
            'id': 'call_1',
            'name': 'accounts_list',
            'status': 'ok',
            'data': <String, Object?>{},
          }),
        );
        await settle(10);
        final answered = c
            .read(chatProvider)
            .items
            .whereType<ToolItem>()
            .single;
        // Same place, same id, now with its answer
        expect(answered.id, running.id);
        expect(answered.running, false);
        expect(answered.status, 'ok');

        s.emit(ev('phase', <String, Object?>{'phase': 'writing'}));
        s.emit(ev('delta', <String, Object?>{'text': 'You have '}));
        s.emit(ev('delta', <String, Object?>{'text': 'two accounts.'}));
        await settle(80);
        final growing = c
            .read(chatProvider)
            .items
            .whereType<AgentItem>()
            .single;
        expect(growing.text, 'You have two accounts.');
        expect(growing.streaming, true);
        expect(c.read(chatProvider).phase, TurnPhase.writing);

        s.emit(
          ev('done', <String, Object?>{'reply': 'x', 'toolsRun': <String>[]}),
        );
        await s.current.close();
        await run;
        final end = c.read(chatProvider);
        expect(end.busy, false);
        expect(end.phase, TurnPhase.idle);
        expect(end.items.whereType<AgentItem>().single.streaming, false);
      },
    );

    test(
      'draws many tiny pieces in a few batches, in order, and loses none',
      () async {
        final s = LiveServer();
        final c = await containerFor(s);
        var draws = 0;
        c.listen<ChatState>(chatProvider, (_, _) => draws++);
        final run = c.read(chatProvider.notifier).send('hi');
        await settle();
        for (var i = 0; i < 100; i++) {
          s.emit(ev('delta', <String, Object?>{'text': '$i,'}));
        }
        s.emit(
          ev('done', <String, Object?>{'reply': '', 'toolsRun': <String>[]}),
        );
        await s.current.close();
        await run;
        final text = c
            .read(chatProvider)
            .items
            .whereType<AgentItem>()
            .single
            .text;
        expect(text, <String>[for (var i = 0; i < 100; i++) '$i,'].join());
        // 100 pieces arriving together are not 100 redraws
        expect(draws, lessThan(20));
      },
    );

    test(
      'a tool that asks for approval leaves no running row behind',
      () async {
        final s = LiveServer();
        final c = await containerFor(s);
        final run = c.read(chatProvider.notifier).send('add a gym bill');
        await settle();
        s.emit(
          ev('tool_start', <String, Object?>{
            'id': 'c9',
            'name': 'bill_create',
          }),
        );
        s.emit(
          ev('tool', <String, Object?>{
            'id': 'c9',
            'name': 'bill_create',
            'status': 'needs_approval',
          }),
        );
        s.emit(
          ev('card', <String, Object?>{'actionId': 'a1', 'summary': 'Add Gym'}),
        );
        s.emit(
          ev('done', <String, Object?>{'reply': '', 'toolsRun': <String>[]}),
        );
        await s.current.close();
        await run;
        final items = c.read(chatProvider).items;
        expect(items.whereType<ToolItem>(), isEmpty);
        expect(items.whereType<CardItem>(), hasLength(1));
      },
    );

    test('a tool answer with no matching start is added as before', () async {
      final s = LiveServer();
      final c = await containerFor(s);
      final run = c.read(chatProvider.notifier).send('hi');
      await settle();
      s.emit(
        ev('tool', <String, Object?>{
          'name': 'accounts_list',
          'status': 'ok',
          'data': <String, Object?>{},
        }),
      );
      s.emit(
        ev('done', <String, Object?>{'reply': '', 'toolsRun': <String>[]}),
      );
      await s.current.close();
      await run;
      expect(c.read(chatProvider).items.whereType<ToolItem>(), hasLength(1));
    });

    test('stop keeps what arrived, sends nothing again and says so', () async {
      final s = LiveServer();
      final c = await containerFor(s);
      final chat = c.read(chatProvider.notifier);
      final run = chat.send('write a long answer');
      await settle();
      s.emit(ev('delta', <String, Object?>{'text': 'Once upon'}));
      s.emit(
        ev('tool_start', <String, Object?>{
          'id': 'c1',
          'name': 'accounts_list',
        }),
      );
      await settle(60);
      chat.stop();
      await run.timeout(const Duration(seconds: 5));
      final end = c.read(chatProvider);
      expect(s.requests, 1);
      expect(end.busy, false);
      expect(end.phase, TurnPhase.idle);
      final agent = end.items.whereType<AgentItem>().single;
      expect(agent.text, 'Once upon');
      expect(agent.streaming, false);
      expect(end.items.whereType<ToolItem>(), isEmpty);
      expect(end.items.whereType<NoticeItem>().single.text, 'Stopped.');
    });

    test('a server error is shown once, not asked for again and not queued as an offline expense', () async {
      final s = LiveServer();
      final c = await containerFor(s);
      final run = c.read(chatProvider.notifier).send('spent 200 on lunch');
      await settle();
      s.emit(ev('error', <String, Object?>{'code': 'INTERNAL'}));
      await s.current.close();
      await run;
      final end = c.read(chatProvider);
      expect(s.requests, 1);
      expect(end.busy, false);
      expect(end.items.whereType<NoticeItem>(), hasLength(1));
      expect(c.read(outboxProvider).length, 0);
    });

    test(
      'a stream cut before "done" is asked for again under the same id',
      () async {
        final s = LiveServer();
        final c = await containerFor(s);
        final run = c.read(chatProvider.notifier).send('hi');
        await settle();
        s.emit(ev('delta', <String, Object?>{'text': 'Hel'}));
        await settle(60);
        await s.streams[0].close();
        // The second try answers in full; the first try's half answer is gone from the screen
        await Future<void>.delayed(const Duration(milliseconds: 2100));
        expect(s.requests, 2);
        s.emit(ev('delta', <String, Object?>{'text': 'Hello'}), 1);
        s.emit(
          ev('done', <String, Object?>{
            'reply': 'Hello',
            'toolsRun': <String>[],
          }),
          1,
        );
        await s.streams[1].close();
        await run;
        final agents = c.read(chatProvider).items.whereType<AgentItem>();
        expect(agents, hasLength(1));
        expect(agents.single.text, 'Hello');
        expect(c.read(chatProvider).busy, false);
      },
    );
  });
}
