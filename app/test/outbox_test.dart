// THE OUTBOX: ONE KEY PER ITEM, THE RETRY CLASSES, A POISON ITEM, TWO FLUSHES, THE PERSON WHO QUEUED IT, A 401, THE OLD BLOBS AND SIGN OUT.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/core/outbox.dart';
import 'package:botler/core/person_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- FUNCTIONS -- //

ApiClient clientFor(MockClient c) =>
    ApiClient(base: 'https://botler.test', token: () async => 'tok', client: c);

http.Response ok() =>
    http.Response(jsonEncode(<String, Object?>{'result': null}), 200);

http.Response err(int status, String message) => http.Response(
  jsonEncode(<String, Object?>{
    'error': <String, Object?>{'code': 'X', 'message': message},
  }),
  status,
);

Future<SharedPreferences> fresh([
  Map<String, Object> initial = const <String, Object>{},
]) async {
  SharedPreferences.setMockInitialValues(<String, Object>{...initial});
  return SharedPreferences.getInstance();
}

void main() {
  resetTests();
  group('storage', () {
    test(
      'every item has its own key and removing one leaves the others',
      () async {
        final prefs = await fresh();
        final box = Outbox(prefs, userId: 'a@x');
        final k1 = await box.add('v1', <String, Object?>{});
        final k2 = await box.add('v2', <String, Object?>{});
        expect(
          prefs.getKeys().where((k) => k.startsWith('outbox.i.')).length,
          2,
        );
        expect(prefs.containsKey('outbox.i.$k1'), isTrue);
        expect(prefs.containsKey('outbox.i.$k2'), isTrue);
        expect(box.items().map((i) => i.verb).toList(), <String>['v1', 'v2']);
        final api = clientFor(
          MockClient(
            (r) async => r.url.path.endsWith('v1') ? ok() : err(400, 'no'),
          ),
        );
        await box.flush(api);
        expect(box.items(), isEmpty);
        expect(box.failed().single.verb, 'v2');
        expect(prefs.containsKey('outbox.f.$k2'), isTrue);
      },
    );

    test('the old blobs are read once and moved to the new keys', () async {
      final prefs = await fresh(<String, Object>{
        'outbox.v1': jsonEncode(<Json>[
          <String, Object?>{
            'key': 'old-1',
            'verb': 'a',
            'args': <String, Object?>{},
            'createdAt': DateTime.now().toIso8601String(),
            'attempts': 1,
          },
          <String, Object?>{
            'key': 'old-2',
            'verb': 'b',
            'args': <String, Object?>{},
            'createdAt': DateTime.now().toIso8601String(),
            'attempts': 0,
          },
        ]),
        'outbox.failed.v1': jsonEncode(<Json>[
          <String, Object?>{
            'key': 'f-1',
            'verb': 'bill_mark_paid',
            'args': <String, Object?>{},
            'reason': 'r',
            'at': DateTime.now().toIso8601String(),
          },
        ]),
      });
      final box = Outbox(prefs, userId: 'a@x');
      // Readable before it is moved
      expect(box.items().map((i) => i.key).toList(), <String>[
        'old-1',
        'old-2',
      ]);
      expect(box.failed().single.key, 'f-1');
      final seen = <String>[];
      final api = clientFor(
        MockClient((r) async {
          seen.add(r.url.path);
          return ok();
        }),
      );
      await box.flush(api);
      expect(seen, <String>['/api/v1/do/a', '/api/v1/do/b']);
      expect(prefs.containsKey('outbox.v1'), isFalse);
      expect(prefs.containsKey('outbox.failed.v1'), isFalse);
      expect(prefs.containsKey('outbox.f.f-1'), isTrue);
      expect(box.items(), isEmpty);
    });

    test('adding the same key twice keeps one item', () async {
      final prefs = await fresh();
      final box = Outbox(prefs);
      await box.add('v', <String, Object?>{'n': 1}, key: 'same-key-1');
      await box.add('v', <String, Object?>{'n': 2}, key: 'same-key-1');
      expect(box.items().single.args['n'], 1);
    });
  });

  group('retry classes', () {
    Future<(Outbox, SharedPreferences)> one() async {
      final prefs = await fresh();
      final box = Outbox(prefs, userId: 'a@x');
      await box.add('v', <String, Object?>{});
      return (box, prefs);
    }

    test('a socket, timeout or handshake failure is offline: no attempt, the pass stops', () async {
      for (final fail in <Object>[
        const SocketException('x'),
        TimeoutException('x'),
        const HandshakeException('x'),
        const TlsException('x'),
      ]) {
        final (box, _) = await one();
        await box.add('w', <String, Object?>{});
        var calls = 0;
        final api = clientFor(
          MockClient((_) async {
            calls++;
            throw fail;
          }),
        );
        final report = await box.flush(api);
        expect(report.offline, isTrue, reason: '$fail');
        expect(calls, 1, reason: 'stops at the first one');
        expect(box.items().first.attempts, 0);
        expect(box.items(), hasLength(2));
      }
    });

    test('a busy server counts an attempt and stops the pass', () async {
      for (final status in <int>[500, 503, 429]) {
        final (box, _) = await one();
        await box.add('w', <String, Object?>{});
        var calls = 0;
        final api = clientFor(
          MockClient((_) async {
            calls++;
            return err(status, 'busy');
          }),
        );
        await box.flush(api);
        expect(calls, 1);
        expect(box.items().first.attempts, 1);
        expect(box.items(), hasLength(2));
      }
    });

    test('any other exception counts an attempt, and a poison item does not block the rest', () async {
      final prefs = await fresh();
      final box = Outbox(prefs, userId: 'a@x');
      await box.add('poison', <String, Object?>{});
      await box.add('good', <String, Object?>{});
      final sent = <String>[];
      final api = clientFor(
        MockClient((r) async {
          if (r.url.path.endsWith('poison')) throw const FormatException('bad');
          sent.add(r.url.path);
          return ok();
        }),
      );
      var report = await box.flush(api);
      expect(sent, <String>['/api/v1/do/good']);
      expect(report.sent, 1);
      expect(box.items().single.verb, 'poison');
      expect(box.items().single.attempts, 1);
      for (var i = 0; i < 7; i++) {
        report = await box.flush(api);
      }
      // The eighth failure is out of attempts: the next pass moves it to the visible list
      report = await box.flush(api);
      expect(box.items(), isEmpty);
      expect(box.failed().single.verb, 'poison');
      expect(report.dropped, hasLength(1));
    });

    test('an item older than 14 days moves to the failed list, never silently dropped', () async {
      final prefs = await fresh();
      final old = Outbox(
        prefs,
        userId: 'a@x',
        now: () => DateTime.now().subtract(const Duration(days: 15)),
      );
      await old.add('v', <String, Object?>{});
      final box = Outbox(prefs, userId: 'a@x');
      var calls = 0;
      final api = clientFor(
        MockClient((_) async {
          calls++;
          return ok();
        }),
      );
      final report = await box.flush(api);
      expect(calls, 0);
      expect(box.items(), isEmpty);
      expect(box.failed().single.reason, contains('14 days'));
      expect(report.dropped, hasLength(1));
    });

    test('a refused write of any verb is kept with the reason', () async {
      final prefs = await fresh();
      final box = Outbox(prefs, userId: 'a@x');
      await box.add('anything_at_all', <String, Object?>{});
      await box.flush(
        clientFor(MockClient((_) async => err(400, 'Not allowed.'))),
      );
      expect(box.failed().single.verb, 'anything_at_all');
      expect(box.failed().single.reason, 'Not allowed.');
      await box.dismissFailed();
      expect(box.failed(), isEmpty);
    });

    test('a 401 keeps the whole queue and says to sign in', () async {
      final prefs = await fresh();
      final box = Outbox(prefs, userId: 'a@x');
      await box.add('a', <String, Object?>{});
      await box.add('b', <String, Object?>{});
      var calls = 0;
      final report = await box.flush(
        clientFor(
          MockClient((_) async {
            calls++;
            return err(401, 'Sign in');
          }),
        ),
      );
      expect(report.needsSignIn, isTrue);
      expect(calls, 1);
      expect(box.items(), hasLength(2));
      expect(box.items().first.attempts, 0);
      expect(box.failed(), isEmpty);
    });
  });

  group('concurrency', () {
    test(
      'an add during a flush is kept and not overwritten by the flush',
      () async {
        final prefs = await fresh();
        final box = Outbox(prefs, userId: 'a@x');
        await box.add('first', <String, Object?>{});
        final gate = Completer<void>();
        final api = clientFor(
          MockClient((r) async {
            await gate.future;
            return ok();
          }),
        );
        final flushing = box.flush(api);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // Does not wait for the network
        final key = await box
            .add('second', <String, Object?>{})
            .timeout(const Duration(seconds: 2));
        gate.complete();
        final report = await flushing;
        expect(report.sent, 1);
        expect(box.items().single.key, key);
      },
    );

    test('two flushes at once send each item once', () async {
      final prefs = await fresh();
      final box = Outbox(prefs, userId: 'a@x');
      await box.add('a', <String, Object?>{});
      await box.add('b', <String, Object?>{});
      var calls = 0;
      final api = clientFor(
        MockClient((_) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return ok();
        }),
      );
      final reports = await Future.wait(<Future<FlushReport>>[
        box.flush(api),
        box.flush(api),
      ]);
      expect(calls, 2);
      expect(reports.map((r) => r.sent).toList(), <int>[2, 0]);
    });

    test('a stale cache: another isolate adds an item after this one read, and the flush sees it', () async {
      final prefs = await fresh();
      final box = Outbox(prefs, userId: 'a@x');
      expect(box.items(), isEmpty);
      // The background isolate wrote straight to the store (not through this instance's cache)
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outbox.i.from-bg': jsonEncode(<String, Object?>{
          'key': 'from-bg',
          'verb': 'bg',
          'args': <String, Object?>{},
          'createdAt': DateTime.now().toIso8601String(),
          'attempts': 0,
          'userId': 'a@x',
          'seq': 5,
        }),
      });
      final seen = <String>[];
      final report = await box.flush(
        clientFor(
          MockClient((r) async {
            seen.add(r.url.path);
            return ok();
          }),
        ),
      );
      expect(seen, <String>['/api/v1/do/bg']);
      expect(report.sent, 1);
    });

    test('a clear during a flush is not undone by an attempt count', () async {
      final prefs = await fresh();
      final box = Outbox(prefs, userId: 'a@x');
      await box.add('a', <String, Object?>{});
      final gate = Completer<void>();
      final api = clientFor(
        MockClient((r) async {
          await gate.future;
          return err(503, 'busy');
        }),
      );
      final flushing = box.flush(api);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await box.clear();
      gate.complete();
      await flushing;
      expect(box.items(), isEmpty);
    });
  });

  group('the person', () {
    test(
      'person B never sends person A\'s items, and A still has them',
      () async {
        final prefs = await fresh();
        final a = Outbox(prefs, userId: 'a@x');
        await a.add('pay', <String, Object?>{});
        final b = Outbox(prefs, userId: 'b@x');
        var calls = 0;
        final api = clientFor(
          MockClient((_) async {
            calls++;
            return ok();
          }),
        );
        final report = await b.flush(api);
        expect(calls, 0);
        expect(report.sent, 0);
        expect(b.items(), isEmpty);
        expect(a.items(), hasLength(1));
        // B's data reset clears B's items only
        await b.add('mine', <String, Object?>{});
        await b.clear();
        expect(a.items(), hasLength(1));
        expect(a.allItems(), hasLength(1));
        await a.flush(api);
        expect(calls, 1);
      },
    );

    test(
      'sign out sweeps every cache key of the person and keeps the outbox',
      () async {
        final prefs = await fresh(<String, Object>{
          'accounts.cache': '[]',
          'assets.cache': '{}',
          'summary.cache': '{}',
          'calendar.range.v1': '{}',
          'simulate.overview.v1.2026-10-01': '{}',
          'library.outline.v1': '{}',
          'library.pages.v1': '[]',
          'library.recents.v1': '[]',
          'library.page.v1.p1': '{}',
          'expense.last_account': 'x',
          'sync.cursor': 'c',
          'sync.shown': <String>['a'],
          'sync.clock_handled': <String>['a'],
          'chatphotos.v1.me': '{}',
          'settings.language': 'fil',
        });
        final a = Outbox(prefs, userId: 'a@x');
        await a.add('pay', <String, Object?>{});
        await clearPersonData(prefs);
        final left = prefs
            .getKeys()
            .where((k) => !k.startsWith('outbox.'))
            .toList();
        expect(left, <String>['settings.language']);
        expect(a.items(), hasLength(1));
      },
    );
  });
}

void resetTests() {
  test(
    'a money-only reset keeps the notebook pages and the photo index',
    () async {
      final prefs = await fresh(<String, Object>{
        'accounts.cache': '[]',
        'library.outline.v1': '{}',
        'chatphotos.v1.me': '{}',
      });
      await clearPersonData(prefs, notebooks: false, photos: false);
      expect(prefs.containsKey('accounts.cache'), isFalse);
      expect(prefs.containsKey('library.outline.v1'), isTrue);
      expect(prefs.containsKey('chatphotos.v1.me'), isTrue);
    },
  );
}
