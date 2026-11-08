// WHAT A TOOL CALL KEEPS OF ITS LABEL: THE KIND AND SUBJECT FROM THE START, THE TIME FROM THE ANSWER, NOTHING LOST WHEN THE ROW IS REPLACED, AND AN OLDER SERVER STILL WORKS.

// -- DEP-MODULES -- //
import 'package:botler/features/chat/chat_state.dart';
import 'package:botler/features/chat/tool_label.dart';
import 'package:flutter_test/flutter_test.dart';

// -- MODULES -- //
import 'chat_live_test.dart' show LiveServer, containerFor, ev, settle;

// -- FUNCTIONS -- //

void main() {
  group('reading the label off an event', () {
    test('takes the kind, the subject and the time', () {
      final l = toolLabelOf(<String, Object?>{
        'label': <String, Object?>{
          'family': 'page_read',
          'subject': ' Trip plan ',
        },
        'ms': 1250,
      });
      expect(l.family, 'page_read');
      expect(l.subject, 'Trip plan');
      expect(l.ms, 1250);
    });

    test('ignores anything of the wrong shape', () {
      for (final e in <Map<String, Object?>>[
        <String, Object?>{},
        <String, Object?>{'label': 'nonsense', 'ms': 'slow'},
        <String, Object?>{
          'label': <String, Object?>{'family': 3, 'subject': <Object?>[]},
          'ms': -4,
        },
      ]) {
        final l = toolLabelOf(e);
        expect(l.family, isNull);
        expect(l.subject, isNull);
        expect(l.ms, isNull);
      }
    });
  });

  group('the live row', () {
    test(
      'keeps the label from the start to the answer, and adds the time',
      () async {
        final s = LiveServer();
        final c = await containerFor(s);
        final chat = c.read(chatProvider.notifier);
        final run = chat.send('read my trip');
        await settle();
        s.emit(ev('start'));
        s.emit(
          ev('tool_start', <String, Object?>{
            'id': 'call_1',
            'name': 'page_get',
            'label': <String, Object?>{
              'family': 'page_read',
              'subject': 'Trip plan',
            },
          }),
        );
        await settle(20);
        final running = c.read(chatProvider).items.whereType<ToolItem>().single;
        expect(running.family, 'page_read');
        expect(running.subject, 'Trip plan');
        expect(running.startedAt, isNotNull);

        // The answer has no label of its own: the running row's stays, and the server's time is used
        s.emit(
          ev('tool', <String, Object?>{
            'id': 'call_1',
            'name': 'page_get',
            'status': 'ok',
            'ms': 900,
          }),
        );
        await settle(20);
        final done = c.read(chatProvider).items.whereType<ToolItem>().single;
        expect(done.id, running.id);
        expect(done.running, false);
        expect(done.family, 'page_read');
        expect(done.subject, 'Trip plan');
        expect(done.ms, 900);
        s.emit(
          ev('done', <String, Object?>{'reply': 'x', 'toolsRun': <String>[]}),
        );
        await s.current.close();
        await run;
      },
    );

    test('a blocked answer drops the subject and the running row does not bring it back', () async {
      final s = LiveServer();
      final c = await containerFor(s);
      final chat = c.read(chatProvider.notifier);
      final run = chat.send('look it up');
      await settle();
      s.emit(ev('start'));
      s.emit(
        ev('tool_start', <String, Object?>{
          'id': 'call_1',
          'name': 'research',
          'label': <String, Object?>{'family': 'web', 'subject': 'a question'},
        }),
      );
      await settle(20);
      s.emit(
        ev('tool', <String, Object?>{
          'id': 'call_1',
          'name': 'research',
          'status': 'blocked',
          'label': <String, Object?>{'family': 'web'},
        }),
      );
      await settle(20);
      final done = c.read(chatProvider).items.whereType<ToolItem>().single;
      expect(done.status, 'blocked');
      expect(done.family, 'web');
      expect(done.subject, isNull);
      s.emit(
        ev('done', <String, Object?>{'reply': 'x', 'toolsRun': <String>[]}),
      );
      await s.current.close();
      await run;
    });

    test('an older server that sends no label still works, with the time measured here', () async {
      final s = LiveServer();
      final c = await containerFor(s);
      final chat = c.read(chatProvider.notifier);
      final run = chat.send('what do I have?');
      await settle();
      s.emit(ev('start'));
      s.emit(
        ev('tool_start', <String, Object?>{
          'id': 'call_1',
          'name': 'accounts_list',
        }),
      );
      await settle(20);
      s.emit(
        ev('tool', <String, Object?>{
          'id': 'call_1',
          'name': 'accounts_list',
          'status': 'ok',
        }),
      );
      await settle(20);
      final done = c.read(chatProvider).items.whereType<ToolItem>().single;
      expect(done.family, isNull);
      expect(done.subject, isNull);
      expect(done.ms, isNotNull);
      s.emit(
        ev('done', <String, Object?>{'reply': 'x', 'toolsRun': <String>[]}),
      );
      await s.current.close();
      await run;
    });
  });

  test('answering a chip keeps the whole row', () {
    const item = ToolItem(
      1,
      name: 'page_get',
      status: 'ok',
      family: 'page_read',
      subject: 'Trip plan',
      ms: 500,
      restored: true,
    );
    final answered = item.answered();
    expect(answered.family, 'page_read');
    expect(answered.subject, 'Trip plan');
    expect(answered.ms, 500);
    expect(answered.restored, true);
  });
}
