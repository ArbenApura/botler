// THE CHAT'S SAFETY NETS: WHAT LOOKS LIKE AN EXPENSE, THE OFFLINE EXPENSE KEEPING THE FIRST TRY'S ID, A SEND THAT OUTLIVES ITS ACCOUNT, THE PICTURE NOTICE,
// AND THE APP LOCK ON A PHONE WITH NO SCREEN LOCK.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/features/auth/lock_gate.dart';
import 'package:botler/features/chat/chat_state.dart';
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

Future<ProviderContainer> containerWith(MockClient client) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(p),
      apiProvider.overrideWithValue(
        ApiClient(
          base: 'https://botler.test',
          token: () async => 'tok',
          client: client,
        ),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('looksLikeExpense', () {
    test('wants an amount with a word or a currency, not any digit', () {
      for (final yes in <String>[
        'lunch 180',
        'lunch 180 gcash',
        'grab 250 pesos',
        '₱90 coffee',
        'rice 1,250.50',
        'coffee 12,50',
        r'$5 coffee',
        '90 php',
      ]) {
        expect(looksLikeExpense(yes), isTrue, reason: yes);
      }
      for (final no in <String>[
        'how am I doing?',
        'meeting at 3pm',
        'call mom at 3:30',
        'call mom 12/05',
        'on 2026-10-01 I paid',
        'the 2nd floor',
        'remind me in 30 minutes',
        '180',
        '',
        'order 1234567890123',
      ]) {
        expect(looksLikeExpense(no), isFalse, reason: no);
      }
    });
  });

  group('the offline expense', () {
    test('is kept under the request id of the first try', () async {
      final ids = <String>[];
      final c = await containerWith(
        MockClient((req) async {
          if (req.url.path.contains('/agent/chat')) {
            ids.add(str(decodeJson(req.body)['clientMessageId']));
          }
          throw const SocketException('offline');
        }),
      );
      final sent = await c.read(chatProvider.notifier).send('lunch 180 gcash');
      expect(sent, isTrue, reason: 'kept for later counts as handled');
      final item = c.read(outboxProvider).items().single;
      expect(item.verb, 'expense_from_text');
      expect(ids.toSet(), hasLength(1));
      expect(item.key, ids.first);
    });

    test('a message whose number is a time is not kept', () async {
      final c = await containerWith(
        MockClient((_) async => throw const SocketException('offline')),
      );
      final sent = await c.read(chatProvider.notifier).send('meeting at 3pm');
      expect(sent, isFalse);
      expect(c.read(outboxProvider).items(), isEmpty);
    });
  });

  group('a send that outlives its account', () {
    test('stops quietly and draws nothing into the new start', () async {
      final body = StreamController<List<int>>();
      final c = await containerWith(
        MockClient.streaming(
          (req, _) async => http.StreamedResponse(body.stream, 200),
        ),
      );
      c.listen(chatProvider, (_, _) {}, fireImmediately: true);
      final notifier = c.read(chatProvider.notifier);
      final sending = notifier.send('hello');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      body.add(
        utf8.encode(
          'data: ${jsonEncode(<String, Object?>{'type': 'start', 'turnId': 't-1', 'chatId': 'c-1'})}\n\n',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Another person signs in: the chat starts over
      c.invalidate(chatProvider);
      c.read(chatProvider);
      body
        ..add(
          utf8.encode(
            'data: ${jsonEncode(<String, Object?>{'type': 'delta', 'text': 'old words'})}\n\n',
          ),
        )
        ..add(
          utf8.encode(
            'data: ${jsonEncode(<String, Object?>{'type': 'done', 'reply': 'old words', 'toolsRun': <String>[]})}\n\n',
          ),
        );
      await body.close();
      final accepted = await sending.timeout(const Duration(seconds: 5));
      expect(accepted, isFalse);
      final now = c.read(chatProvider);
      expect(now.items, isEmpty);
      expect(now.busy, isFalse);
    });
  });

  group('the picture notice', () {
    MockClient refusing(List<Json> bodies) => MockClient((req) async {
      bodies.add(decodeJson(req.body));
      return http.Response(
        jsonEncode(<String, Object?>{
          'error': <String, Object?>{'code': 'INVALID', 'message': 'Too long.'},
        }),
        400,
      );
    });

    test('is not said when the retry on text failed too', () async {
      final bodies = <Json>[];
      final c = await containerWith(refusing(bodies));
      await c
          .read(chatProvider.notifier)
          .send(
            'what is this',
            photoTexts: <String>['total 120'],
            images: <String>['QUJD'],
          );
      expect(bodies, hasLength(2));
      final said = c
          .read(chatProvider)
          .items
          .whereType<NoticeItem>()
          .map((n) => n.text);
      expect(said, isNot(contains(wordsFor('en').chatPicturesNoted)));
      expect(said, contains('Too long.'));
    });
  });

  group('the app lock with no screen lock on the phone', () {
    Widget gate(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTheme(Brightness.light),
        home: const LockGate(child: Text('Secret balance')),
      ),
    );

    Future<ProviderContainer> locked({
      required Future<bool> Function() authenticate,
      required bool hasLock,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'settings.lock': true,
      });
      final p = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(p),
          authenticateProvider.overrideWithValue(authenticate),
          lockAvailableProvider.overrideWithValue(() async => hasLock),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    testWidgets('lets the person go on after one explicit confirm', (
      tester,
    ) async {
      final c = await locked(authenticate: () async => false, hasLock: false);
      await tester.pumpWidget(gate(c));
      await tester.pumpAndSettle();
      expect(find.textContaining('no screen lock'), findsOneWidget);
      expect(find.text('Secret balance'), findsNothing);
      await tester.tap(find.text('Continue without a lock'));
      await tester.pumpAndSettle();
      expect(find.text('Secret balance'), findsOneWidget);
    });

    testWidgets('a phone that has a lock stays locked after a wrong finger', (
      tester,
    ) async {
      final c = await locked(authenticate: () async => false, hasLock: true);
      await tester.pumpWidget(gate(c));
      await tester.pumpAndSettle();
      expect(find.text('Unlock'), findsOneWidget);
      expect(find.text('Continue without a lock'), findsNothing);
    });

    testWidgets('an error while asking does not block the next ask', (
      tester,
    ) async {
      var calls = 0;
      final c = await locked(
        authenticate: () async {
          calls++;
          if (calls == 1) throw StateError('sensor broke');
          return true;
        },
        hasLock: true,
      );
      final errors = <Object>[];
      await runZonedGuarded(() async {
        await tester.pumpWidget(gate(c));
        await tester.pump();
      }, (e, _) => errors.add(e));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Secret balance'), findsOneWidget);
    });
  });
}
