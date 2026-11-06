// THE PHONE'S SIDE OF THE ASSISTANT'S PHONE TOOLS (BTL-20261031-1334): THE STORAGE, THE TOOLBOX, THE RUNNER THAT ANSWERS EACH CALL, AND THE CHAT THAT HANDS THE CALLS OVER
// The engine is replaced by a stand-in here (the real one is tested in script_sandbox_test.dart), so these always run.

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/core/script/device_tools.dart';
import 'package:botler/core/script/sandbox.dart';
import 'package:botler/core/script/storage.dart';
import 'package:botler/core/script/toolbox.dart';
import 'package:botler/features/chat/chat_state.dart';
import 'package:botler/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- TYPES -- //

class Sent {
  Sent(this.callId, this.ok, this.result);

  final String callId;
  final bool ok;
  final Json result;
}

class Rig {
  Rig(
    this.dir,
    this.storage,
    this.toolbox,
    this.runner,
    this.sent,
    this.started,
  );

  final Directory dir;
  final ScriptStorage storage;
  final Toolbox toolbox;
  final DeviceToolRunner runner;
  final List<Sent> sent;

  /// What the stand-in engine was asked to run: code, input, scratch folder, photos.
  final List<({String code, String input, String scratch, List<String> photos})>
  started;
}

// -- FUNCTIONS -- //

Rig rig({ScriptResult? result}) {
  final dir = Directory.systemTemp.createTempSync('device_tools');
  addTearDown(() => dir.deleteSync(recursive: true));
  final storage = ScriptStorage(owner: 'a@b.c', baseDir: () async => dir);
  final toolbox = Toolbox(storage);
  final sent = <Sent>[];
  final started =
      <({String code, String input, String scratch, List<String> photos})>[];
  final runner = DeviceToolRunner(
    storage: storage,
    toolbox: toolbox,
    send: (id, ok, r) async => sent.add(Sent(id, ok, r)),
    start:
        ({
          required String code,
          required Directory scratch,
          String input = '',
          List<String> photos = const <String>[],
        }) {
          started.add((
            code: code,
            input: input,
            scratch: scratch.path,
            photos: photos,
          ));
          return ScriptRun.finished(
            result ?? const ScriptResult(ok: true, output: '42', ms: 3),
          );
        },
  );
  return Rig(dir, storage, toolbox, runner, sent, started);
}

void main() {
  group('the storage', () {
    test('a chat id that could name a path gets the shared folder', () async {
      final r = rig();
      for (final bad in <String?>['../x', 'a/b', r'a\b', '', null, 'x' * 65]) {
        final d = await r.storage.scratchFor(bad);
        expect(
          d.path,
          endsWith('${Platform.pathSeparator}new'),
          reason: '$bad',
        );
      }
      final ok = await r.storage.scratchFor('3f2a-9c');
      expect(ok.path, endsWith('${Platform.pathSeparator}3f2a-9c'));
      expect(ok.parent.parent.path, (await r.storage.root()).path);
    });

    test(
      'another person has another folder, and wipe removes only this one',
      () async {
        final r = rig();
        final other = ScriptStorage(owner: 'x@y.z', baseDir: () async => r.dir);
        await r.storage.scratchFor('c1');
        await other.scratchFor('c1');
        await r.storage.wipe();
        expect((await other.scratchFor('c1')).existsSync(), isTrue);
        expect(
          Directory('${r.dir.path}${Platform.pathSeparator}script_data')
              .listSync()
              .length,
          1,
        );
      },
    );

    test('the sweep removes only folders unused for 30 days', () async {
      final r = rig();
      final old = await r.storage.scratchFor('old');
      File('${old.path}${Platform.pathSeparator}a.txt').writeAsStringSync('x');
      final fresh = await r.storage.scratchFor('fresh');
      File('${fresh.path}${Platform.pathSeparator}a.txt')
          .writeAsStringSync('x');
      await r.storage.sweep(now: DateTime.now().add(const Duration(days: 31)));
      expect(old.existsSync(), isFalse);
      expect(
        fresh.existsSync(),
        isFalse,
        reason: 'both are 31 days idle at that clock',
      );
      final again = await r.storage.scratchFor('again');
      File('${again.path}${Platform.pathSeparator}a.txt')
          .writeAsStringSync('x');
      await r.storage.sweep(now: DateTime.now().add(const Duration(days: 5)));
      expect(again.existsSync(), isTrue);
    });
  });

  group('the toolbox', () {
    test('saves, reads, lists in name order and deletes', () async {
      final tb = rig().toolbox;
      await tb.save('Zebra', 'print(1)');
      await tb.save('apple', 'print(2)');
      expect((await tb.list()).map((e) => e.name), <String>['apple', 'Zebra']);
      expect((await tb.read('APPLE'))?.code, 'print(2)');
      expect(await tb.delete('zebra'), isTrue);
      expect(await tb.delete('zebra'), isFalse);
      expect(await tb.read('Zebra'), isNull);
    });

    test(
      'the same name in any case replaces the script, not adds one',
      () async {
        final tb = rig().toolbox;
        await tb.save('Total', 'print(1)');
        await tb.save('total', 'print(2)');
        final all = await tb.list();
        expect(all, hasLength(1));
        expect(all.single.code, 'print(2)');
        expect(all.single.name, 'total');
      },
    );

    test('keeps to 30 scripts, 20000 characters and sane names', () async {
      final tb = rig().toolbox;
      for (var i = 0; i < toolboxMaxScripts; i++) {
        await tb.save('s$i', 'print($i)');
      }
      await expectLater(
        tb.save('one more', 'print(1)'),
        throwsA(isA<ToolboxException>()),
      );
      // Replacing one of the 30 is still allowed
      await tb.save('s0', 'print("again")');
      await expectLater(
        tb.save('s1', 'x' * (toolboxMaxCodeChars + 1)),
        throwsA(isA<ToolboxException>()),
      );
      await expectLater(tb.save('s1', '   '), throwsA(isA<ToolboxException>()));
      await expectLater(
        tb.save('', 'print(1)'),
        throwsA(isA<ToolboxException>()),
      );
      await expectLater(
        tb.save('a\nb', 'print(1)'),
        throwsA(isA<ToolboxException>()),
      );
      await expectLater(
        tb.save('n' * 61, 'print(1)'),
        throwsA(isA<ToolboxException>()),
      );
    });

    test('changes made at the same moment are all kept', () async {
      final tb = rig().toolbox;
      await Future.wait(<Future<Object?>>[
        for (var i = 0; i < 10; i++) tb.save('s$i', 'print($i)'),
      ]);
      expect(await tb.list(), hasLength(10));
      await Future.wait(<Future<Object?>>[
        for (var i = 0; i < 5; i++) tb.delete('s$i'),
      ]);
      expect(await tb.list(), hasLength(5));
    });

    test(
      'a damaged file reads as empty and the next save repairs it',
      () async {
        final r = rig();
        final file = await r.storage.toolboxFile();
        file.writeAsStringSync('{not json');
        expect(await r.toolbox.list(), isEmpty);
        await r.toolbox.save('ok', 'print(1)');
        expect(await r.toolbox.list(), hasLength(1));
      },
    );
  });

  group('the runner', () {
    test(
      'runs a script with its input, in the chat folder, and answers once',
      () async {
        final r = rig(
          result: const ScriptResult(ok: true, output: '42', ms: 5),
        );
        await r.runner.handle(
          callId: 'dc_1',
          tool: 'script_run',
          args: <String, Object?>{'code': 'print(6*7)', 'input': 'hi'},
          chatId: 'chat-1',
          photos: <String>['/p/1.jpg'],
        );
        expect(r.started.single.code, 'print(6*7)');
        expect(r.started.single.input, 'hi');
        expect(r.started.single.photos, <String>['/p/1.jpg']);
        expect(
          r.started.single.scratch,
          endsWith('${Platform.pathSeparator}chat-1'),
        );
        expect(r.sent, hasLength(1));
        expect(r.sent.single.callId, 'dc_1');
        expect(r.sent.single.ok, isTrue);
        expect(r.sent.single.result['output'], '42');
      },
    );

    test(
      'a failed script answers ok false with its message and what it printed',
      () async {
        final r = rig(
          result: const ScriptResult(
            ok: false,
            output: 'before',
            error: 'boom',
          ),
        );
        await r.runner.handle(
          callId: 'dc_2',
          tool: 'script_run',
          args: <String, Object?>{'code': 'x'},
        );
        expect(r.sent.single.ok, isFalse);
        expect(r.sent.single.result['error'], 'boom');
        expect(r.sent.single.result['output'], 'before');
      },
    );

    test(
      'runs a saved script by name, and says so when there is none',
      () async {
        final r = rig();
        await r.toolbox.save('Totals', 'print("saved")');
        await r.runner.handle(
          callId: 'dc_3',
          tool: 'script_run',
          args: <String, Object?>{'saved': 'totals'},
        );
        expect(r.started.single.code, 'print("saved")');
        await r.runner.handle(
          callId: 'dc_4',
          tool: 'script_run',
          args: <String, Object?>{'saved': 'nope'},
        );
        expect(r.sent.last.ok, isFalse);
        expect(
          r.sent.last.result['error'],
          contains('no script called "nope"'),
        );
        expect(r.started, hasLength(1));
      },
    );

    test('answers a call with neither code nor a saved name', () async {
      final r = rig();
      await r.runner.handle(
        callId: 'dc_5',
        tool: 'script_run',
        args: <String, Object?>{},
      );
      expect(r.sent.single.ok, isFalse);
      expect(r.started, isEmpty);
    });

    test('the toolbox tool lists, reads, saves and deletes', () async {
      final r = rig();
      Future<Sent> call(Json args) async {
        await r.runner.handle(callId: 'dc_t', tool: 'toolbox', args: args);
        return r.sent.last;
      }

      var out = await call(<String, Object?>{
        'action': 'save',
        'name': 'Sum',
        'code': 'print(1+1)',
      });
      expect(out.ok, isTrue);
      expect(out.result['saved'], 'Sum');
      expect(out.result['count'], 1);
      out = await call(<String, Object?>{'action': 'list'});
      expect(out.result['scripts'], <Object?>[
        <String, Object?>{'name': 'Sum', 'chars': 10},
      ]);
      expect(out.result['limit'], 30);
      out = await call(<String, Object?>{'action': 'read', 'name': 'sum'});
      expect(out.result['code'], 'print(1+1)');
      out = await call(<String, Object?>{'action': 'delete', 'name': 'Sum'});
      expect(out.ok, isTrue);
      out = await call(<String, Object?>{'action': 'delete', 'name': 'Sum'});
      expect(out.ok, isFalse);
      out = await call(<String, Object?>{'action': 'read', 'name': 'Sum'});
      expect(out.ok, isFalse);
      out = await call(<String, Object?>{'action': 'save', 'name': 'x'});
      expect(out.ok, isFalse);
      out = await call(<String, Object?>{'action': 'explode'});
      expect(out.ok, isFalse);
    });

    test('a toolbox refusal is an answer with its words', () async {
      final r = rig();
      await r.runner.handle(
        callId: 'dc_6',
        tool: 'toolbox',
        args: <String, Object?>{
          'action': 'save',
          'name': '',
          'code': 'print(1)',
        },
      );
      expect(r.sent.single.ok, isFalse);
      expect(r.sent.single.result['error'], contains('1 to 60'));
    });

    test('an unknown tool is answered, never left waiting', () async {
      final r = rig();
      await r.runner.handle(
        callId: 'dc_7',
        tool: 'rm_rf',
        args: <String, Object?>{},
      );
      expect(r.sent.single.ok, isFalse);
    });

    test('a call that began before Stop does not start its script', () async {
      final r = rig();
      // The call is on its way (awaiting the toolbox and the folder) when Stop is pressed
      final call = r.runner.handle(
        callId: 'dc_9',
        tool: 'script_run',
        args: <String, Object?>{'code': 'print(1)'},
      );
      r.runner.stopAll();
      await call;
      expect(r.started, isEmpty);
      expect(r.sent.single.ok, isFalse);
      expect(r.sent.single.result['error'], contains('Stopped'));
      // A call after the Stop runs as usual
      await r.runner.handle(
        callId: 'dc_10',
        tool: 'script_run',
        args: <String, Object?>{'code': 'print(1)'},
      );
      expect(r.started, hasLength(1));
    });

    test('Stop in one chat leaves the scripts of another chat alone', () async {
      final r = rig();
      final a = r.runner.handle(
        callId: 'dc_a',
        tool: 'script_run',
        args: <String, Object?>{'code': 'print(1)'},
        chatId: 'chat-a',
      );
      final b = r.runner.handle(
        callId: 'dc_b',
        tool: 'script_run',
        args: <String, Object?>{'code': 'print(2)'},
        chatId: 'chat-b',
      );
      r.runner.stopChat('chat-a');
      await Future.wait<void>(<Future<void>>[a, b]);
      // chat-a's call was stopped before it started; chat-b's ran
      expect(r.started, hasLength(1));
      final byCall = <String, bool>{for (final s in r.sent) s.callId: s.ok};
      expect(byCall['dc_a'], isFalse);
      expect(byCall['dc_b'], isTrue);
    });

    test('a script that ran while untrusted text was in the message makes its folder untrusted for good', () async {
      final r = rig();
      await r.runner.handle(
        callId: 'dc_11',
        tool: 'script_run',
        args: <String, Object?>{'code': 'print(1)'},
        chatId: 'chat-u',
        tainted: false,
      );
      expect(r.sent.last.result['untrusted'], isNull);
      await r.runner.handle(
        callId: 'dc_12',
        tool: 'script_run',
        args: <String, Object?>{'code': 'print(1)'},
        chatId: 'chat-u',
        tainted: true,
      );
      expect(r.sent.last.result['untrusted'], isTrue);
      // Later, in a clean message of the same chat, what it prints is still marked
      await r.runner.handle(
        callId: 'dc_13',
        tool: 'script_run',
        args: <String, Object?>{'code': 'print(1)'},
        chatId: 'chat-u',
      );
      expect(r.sent.last.result['untrusted'], isTrue);
      // Another chat is not affected
      await r.runner.handle(
        callId: 'dc_14',
        tool: 'script_run',
        args: <String, Object?>{'code': 'print(1)'},
        chatId: 'chat-clean',
      );
      expect(r.sent.last.result['untrusted'], isNull);
    });

    test('a send that fails does not throw', () async {
      final r = rig();
      final runner = DeviceToolRunner(
        storage: r.storage,
        toolbox: r.toolbox,
        send: (id, ok, result) async => throw const SocketException('down'),
        start: ({
          required String code,
          required Directory scratch,
          String input = '',
          List<String> photos = const <String>[],
        }) => ScriptRun.finished(const ScriptResult(ok: true, output: '')),
      );
      await runner.handle(
        callId: 'dc_8',
        tool: 'script_run',
        args: <String, Object?>{'code': 'x'},
      );
    });
  });

  group('the chat', () {
    Future<(ProviderContainer, List<Json>, List<Sent>)> chat(
      List<Json> events,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final bodies = <Json>[];
      final api = MockClient.streaming((req, body) async {
        final text = await http.ByteStream(body).bytesToString();
        if (req.url.path.contains('/agent/chat')) bodies.add(decodeJson(text));
        final lines = events.map((e) => 'data: ${jsonEncode(e)}\n\n').join();
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(lines)),
          200,
        );
      });
      final r = rig(result: const ScriptResult(ok: true, output: '42', ms: 2));
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          apiProvider.overrideWithValue(
            ApiClient(
              base: 'https://botler.test',
              token: () async => 'tok',
              client: api,
            ),
          ),
          deviceToolRunnerProvider.overrideWithValue(r.runner),
        ],
      );
      addTearDown(c.dispose);
      return (c, bodies, r.sent);
    }

    test(
      'says it can run scripts, runs the announced call and answers it',
      () async {
        final (c, bodies, sent) = await chat(<Json>[
          <String, Object?>{'type': 'start', 'turnId': 't-1', 'chatId': 'c-1'},
          <String, Object?>{
            'type': 'tool_start',
            'id': 'call_0',
            'name': 'script_run',
            'device': <String, Object?>{
              'callId': 'dc_abc12345',
              'args': <String, Object?>{'code': 'print(6*7)'},
            },
          },
          <String, Object?>{
            'type': 'tool',
            'id': 'call_0',
            'name': 'script_run',
            'status': 'ok',
            'data': <String, Object?>{'ok': true, 'output': '42'},
          },
          <String, Object?>{'type': 'delta', 'text': 'It is 42.'},
          <String, Object?>{
            'type': 'done',
            'reply': 'It is 42.',
            'toolsRun': <String>['script_run'],
          },
        ]);
        await c.read(chatProvider.notifier).send('what is 6 times 7');
        expect(bodies.single['scripts'], isTrue);
        expect(sent, hasLength(1));
        expect(sent.single.callId, 'dc_abc12345');
        expect(sent.single.ok, isTrue);
        expect(sent.single.result['output'], '42');
        final tools = c.read(chatProvider).items.whereType<ToolItem>().toList();
        expect(tools.single.status, 'ok');
      },
    );

    test(
      'a tool_start without a device call runs nothing on the phone',
      () async {
        final (c, _, sent) = await chat(<Json>[
          <String, Object?>{'type': 'start', 'turnId': 't-1', 'chatId': 'c-1'},
          <String, Object?>{
            'type': 'tool_start',
            'id': 'call_0',
            'name': 'accounts_list',
          },
          <String, Object?>{
            'type': 'tool',
            'id': 'call_0',
            'name': 'accounts_list',
            'status': 'ok',
          },
          <String, Object?>{
            'type': 'done',
            'reply': 'ok',
            'toolsRun': <String>[],
          },
        ]);
        await c.read(chatProvider.notifier).send('list');
        expect(sent, isEmpty);
      },
    );
  });
}
