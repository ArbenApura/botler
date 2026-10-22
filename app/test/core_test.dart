// THE CORE: MONEY IN MINOR UNITS, THE SERVER CLIENT (ERRORS, THE CHAT STREAM), THE OUTBOX (ONCE ONLY, IN ORDER, DROP WHAT IS REFUSED) AND NOTIFICATION WORDS.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/core/money.dart';
import 'package:botler/core/outbox.dart';
import 'package:botler/core/reminders.dart';
import 'package:botler/state/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- FUNCTIONS -- //

ApiClient clientFor(MockClient c) =>
    ApiClient(base: 'https://botler.test', token: () async => 'tok', client: c);

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json'},
);

void main() {
  group('money', () {
    test('shows pesos, dollars and yen from integers, exactly', () {
      expect(formatMoney(123450), '₱1,234.50');
      expect(formatMoney(-5), '-₱0.05');
      expect(formatMoney(0), '₱0.00');
      expect(formatMoney(100000000), '₱1,000,000.00');
      expect(formatMoney(123456789, 'USD'), r'$1,234,567.89');
      expect(formatMoney(1234, 'JPY'), '¥1,234');
      expect(formatMoney(-1500000, 'KRW'), '-₩1,500,000');
      expect(formatMoney(5, 'EUR'), '€0.05');
      // An unknown code never breaks a screen: it reads as pesos
      expect(formatMoney(100, 'XXX'), '₱1.00');
    });

    test('reads what a person types', () {
      expect(parseMoney('180'), 18000);
      expect(parseMoney('1,250.50'), 125050);
      expect(parseMoney('₱ 90'), 9000);
      expect(parseMoney('php 12.5'), 1250);
      expect(parseMoney('abc'), isNull);
      expect(parseMoney('12.345'), isNull);
      expect(parseMoney(''), isNull);
      expect(parseMoney('99999999'), isNull);
      expect(parseMoney(r'$5', 'USD'), 500);
      expect(parseMoney('usd 12.05', 'USD'), 1205);
    });

    test(
      'a currency with no decimals takes none, and keeps the 32 bit cap',
      () {
        expect(parseMoney('1,500', 'JPY'), 1500);
        expect(parseMoney('¥200', 'JPY'), 200);
        expect(parseMoney('1500.50', 'JPY'), isNull);
        expect(parseMoney('2147483647', 'JPY'), 2147483647);
        expect(parseMoney('2147483648', 'JPY'), isNull);
      },
    );

    test('puts an amount back in a field', () {
      expect(plainAmount(18000), '180.00');
      expect(plainAmount(125050), '1250.50');
      expect(plainAmount(180, 'JPY'), '180');
      expect(plainAmount(-5, 'USD'), '-0.05');
    });

    test('every currency round-trips through plain text', () {
      for (final c in currencies) {
        for (final n in <int>[0, 1, 99, 100, 123456]) {
          expect(parseMoney(plainAmount(n, c.code), c.code), n, reason: c.code);
        }
      }
    });
  });

  group('the server client', () {
    test(
      'sends the session and a request id, and returns the verb result',
      () async {
        late http.Request seen;
        final api = clientFor(
          MockClient((req) async {
            seen = req;
            return jsonResponse(<String, Object?>{
              'result': <String, Object?>{'ok': true},
            });
          }),
        );
        final r = await api.verbJson('expense_log', <String, Object?>{
          'amount': 1,
        }, 'req-key-0001');
        expect(r['ok'], true);
        expect(seen.url.path, '/api/v1/do/expense_log');
        expect(seen.headers['authorization'], 'Bearer tok');
        expect(seen.headers['idempotency-key'], 'req-key-0001');
        expect(jsonDecode(seen.body), <String, Object?>{'amount': 1});
      },
    );

    test('turns the server error into plain words with a code', () async {
      final api = clientFor(
        MockClient(
          (_) async => jsonResponse(<String, Object?>{
            'error': <String, Object?>{
              'code': 'INVALID',
              'message': 'amount: Too small',
            },
          }, 400),
        ),
      );
      await expectLater(
        api.verb('expense_log'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'amount: Too small')
              .having((e) => e.code, 'code', 'INVALID')
              .having((e) => e.isRetryable, 'retryable', false),
        ),
      );
    });

    test(
      'says the server could not be reached, and that it is worth trying again',
      () async {
        final api = clientFor(
          MockClient((_) async => throw http.ClientException('down')),
        );
        await expectLater(
          api.verb('x'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.isNetwork, 'network', true)
                .having((e) => e.isRetryable, 'retryable', true),
          ),
        );
      },
    );

    test('reads the chat stream event by event', () async {
      final api = clientFor(
        MockClient.streaming((req, body) async {
          final text =
              'data: {"type":"delta","text":"Hel"}\n\ndata: {"type":"delta","text":"lo"}\n\n: ignored\n\ndata: {"type":"done","reply":"Hello","toolsRun":[]}\n\n';
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(text)),
            200,
          );
        }),
      );
      final events = await api.chat(id: 'msg-00000001', text: 'hi').toList();
      expect(events.map((e) => str(e['type'])).toList(), <String>[
        'delta',
        'delta',
        'done',
      ]);
      expect(events.map((e) => str(e['text'])).join(), 'Hello');
    });

    test('asks for an uncompressed stream and ignores keep-alive pings', () async {
      String? encoding;
      final api = clientFor(
        MockClient.streaming((req, body) async {
          encoding = req.headers['accept-encoding'];
          const text =
              'data: {"type":"start"}\n\n: ping\n\n: ping\n\ndata: {"type":"done","reply":"","toolsRun":[]}\n\n';
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(text)),
            200,
          );
        }),
      );
      final events = await api.chat(id: 'msg-00000003', text: 'hi').toList();
      expect(encoding, 'identity');
      expect(events.map((e) => str(e['type'])).toList(), <String>[
        'start',
        'done',
      ]);
    });

    test('a stream that goes silent becomes a network error', () async {
      final api = clientFor(
        MockClient.streaming((req, body) async {
          final controller = StreamController<List<int>>();
          controller.add(utf8.encode('data: {"type":"start"}\n\n'));
          return http.StreamedResponse(controller.stream, 200);
        }),
      );
      await expectLater(
        api
            .chat(
              id: 'msg-00000004',
              text: 'hi',
              idle: const Duration(milliseconds: 50),
            )
            .toList(),
        throwsA(
          isA<ApiException>().having((e) => e.isNetwork, 'network', true),
        ),
      );
    });

    test('a connection dropped mid stream becomes a network error', () async {
      final api = clientFor(
        MockClient.streaming((req, body) async {
          Stream<List<int>> broken() async* {
            yield utf8.encode('data: {"type":"start"}\n\n');
            throw const SocketException('reset');
          }

          return http.StreamedResponse(broken(), 200);
        }),
      );
      await expectLater(
        api.chat(id: 'msg-00000005', text: 'hi').toList(),
        throwsA(
          isA<ApiException>().having((e) => e.isNetwork, 'network', true),
        ),
      );
    });

    test('stopping ends the stream quietly and keeps what arrived', () async {
      final abort = Completer<void>();
      final api = clientFor(
        MockClient.streaming((req, body) async {
          Stream<List<int>> slow() async* {
            yield utf8.encode('data: {"type":"delta","text":"Hel"}\n\n');
            await abort.future;
            throw http.RequestAbortedException();
          }

          return http.StreamedResponse(slow(), 200);
        }),
      );
      final seen = <String>[];
      final done = api
          .chat(id: 'msg-00000006', text: 'hi', abort: abort.future)
          .forEach((e) => seen.add(str(e['text'])));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      abort.complete();
      await done;
      expect(seen, <String>['Hel']);
    });

    test('refuses a chat that the server rejects before streaming', () async {
      final api = clientFor(
        MockClient.streaming(
          (req, body) async => http.StreamedResponse(
            Stream<List<int>>.value(
              utf8.encode(
                jsonEncode(<String, Object?>{
                  'error': <String, Object?>{
                    'code': 'CONFLICT',
                    'message': 'still being answered',
                  },
                }),
              ),
            ),
            409,
          ),
        ),
      );
      await expectLater(
        api.chat(id: 'msg-00000002', text: 'hi').toList(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'CONFLICT')),
      );
    });
  });

  group('the outbox', () {
    Future<Outbox> box() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      return Outbox(await SharedPreferences.getInstance());
    }

    test('keeps a write while offline, then sends it once with the same request id', () async {
      final outbox = await box();
      final key = await outbox.add('expense_log', <String, Object?>{
        'amount': 18000,
      });
      final seen = <String>[];
      var offline = true;
      final api = clientFor(
        MockClient((req) async {
          if (offline) throw http.ClientException('offline');
          seen.add(req.headers['idempotency-key'] ?? '');
          return jsonResponse(<String, Object?>{'result': <String, Object?>{}});
        }),
      );
      var report = await outbox.flush(api);
      expect((report.sent, report.left), (0, 1));
      expect(outbox.length, 1);
      offline = false;
      report = await outbox.flush(api);
      expect((report.sent, report.left), (1, 0));
      expect(seen, <String>[key]);
      // Nothing is left to send twice
      await outbox.flush(api);
      expect(seen, hasLength(1));
    });

    test(
      'keeps the order and stops at the first one the network blocks',
      () async {
        final outbox = await box();
        await outbox.add('a', <String, Object?>{});
        await outbox.add('b', <String, Object?>{});
        final sent = <String>[];
        final api = clientFor(
          MockClient((req) async {
            if (req.url.path.endsWith('/a'))
              throw http.ClientException('offline');
            sent.add(req.url.path);
            return jsonResponse(<String, Object?>{'result': null});
          }),
        );
        await outbox.flush(api);
        expect(sent, isEmpty);
        expect(outbox.items().map((i) => i.verb).toList(), <String>['a', 'b']);
      },
    );

    test('drops what the server refuses for good and says why', () async {
      final outbox = await box();
      await outbox.add('expense_log', <String, Object?>{'amount': -1});
      final api = clientFor(
        MockClient(
          (_) async => jsonResponse(<String, Object?>{
            'error': <String, Object?>{
              'code': 'INVALID',
              'message': 'amount: Too small',
            },
          }, 400),
        ),
      );
      final report = await outbox.flush(api);
      expect(report.dropped, <String>['amount: Too small']);
      expect(outbox.length, 0);
    });

    test(
      'a write that was tried once keeps its request id when it is queued',
      () async {
        final outbox = await box();
        final key = await outbox.add(
          'expense_log',
          <String, Object?>{},
          key: 'already-tried-id',
        );
        expect(key, 'already-tried-id');
        expect(outbox.items().single.key, 'already-tried-id');
      },
    );
  });

  group('notifications', () {
    test('say only "Botler" when details are hidden, and the reminder itself otherwise', () {
      const hidden = Settings();
      expect(notificationFor('Pay the rent', hidden), (
        title: 'Botler',
        body: 'You have a reminder',
      ));
      expect(
        notificationFor('Pay the rent', hidden.copyWith(hideDetails: false)),
        (title: 'Pay the rent', body: null),
      );
    });
  });
}
