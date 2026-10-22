// THE ACCOUNT TIMELINE, THE ENTRY WORDS, THE SET-BALANCE FLOW AND THE RESET-DATA SCREEN, WITH A FAKE SERVER.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/features/auth/lock_gate.dart';
import 'package:botler/features/money/account_detail_screen.dart';
import 'package:botler/features/money/audit_words.dart';
import 'package:botler/features/settings/reset_screen.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- TYPES -- //

class Fake {
  final List<String> calls = <String>[];
  final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];
  final List<String> channels = <String>[];
  bool verifyOk = true;

  Map<String, Object?> entry(
    int seq,
    String action,
    int delta,
    int after, {
    String actor = 'person',
    String? onBehalf,
    String channel = 'app',
  }) => <String, Object?>{
    'seq': seq,
    'at': '2026-10-20T03:00:00.000Z',
    'actor': actor,
    'onBehalf': onBehalf,
    'channel': channel,
    'verb': 'x',
    'entity': 'ledger_txn',
    'entityId': 'e$seq',
    'action': action,
    'delta': delta,
    'balanceAfter': after,
    'note': null,
    'approvalId': null,
    'turnId': null,
    'requestId': 'abcdef1234567890',
    'undoOf': null,
    'before': <String, Object?>{'amount': 1000},
    'after': <String, Object?>{'amount': 2500},
  };

  Object? answer(String verb, Map<String, Object?> body) {
    switch (verb) {
      case 'accounts_balances':
        return <Object?>[
          <String, Object?>{'id': 'a1', 'name': 'GCash', 'balance': 120000},
        ];
      case 'account_history':
        return <String, Object?>{
          'entries': <Object?>[
            entry(3, 'reset', -120000, 0, actor: 'agent', channel: 'chat'),
            entry(2, 'create', -5000, 120000),
            entry(
              1,
              'create',
              125000,
              125000,
              actor: 'person',
              onBehalf: 'agent',
              channel: 'chat',
            ),
          ],
          'nextCursor': null,
          'balance': 0,
        };
      case 'audit_verify':
        return verifyOk
            ? <String, Object?>{
                'ok': true,
                'checked': 3,
                'problem': null,
                'verifiedAt': '2026-10-22T01:00:00.000Z',
              }
            : <String, Object?>{
                'ok': false,
                'checked': 3,
                'problem': <String, Object?>{'seq': 2, 'kind': 'hash'},
                'verifiedAt': '2026-10-22T01:00:00.000Z',
              };
      case 'snapshot_record':
        return <String, Object?>{'status': 'saved'};
      case 'data_reset_preview':
        return <String, Object?>{
          'scope': body['scope'],
          'counts': <String, Object?>{'account': 2, 'ledger_txn': 10},
          'total': 12,
          'token': 'a' * 32,
          'expiresInMinutes': 5,
          'word': 'RESET',
          'keeps': <Object?>['sign-in', 'settings'],
        };
      case 'data_reset':
        return <String, Object?>{
          'scope': body['scope'],
          'deleted': <String, Object?>{'account': 2, 'ledger_txn': 10},
        };
    }
    return <String, Object?>{};
  }

  ApiClient api() => ApiClient(
    base: 'https://botler.test',
    token: () async => 'tok',
    client: MockClient((req) async {
      final verb = req.url.pathSegments.last;
      final body = req.body.isEmpty
          ? <String, Object?>{}
          : (jsonDecode(req.body) as Map<String, Object?>);
      calls.add(verb);
      bodies.add(body);
      channels.add(req.headers['x-botler-channel'] ?? '');
      return http.Response(
        jsonEncode(<String, Object?>{'result': answer(verb, body)}),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    }),
  );
}

// -- FUNCTIONS -- //

AppLocalizations words(String code) => lookupAppLocalizations(Locale(code));

Future<void> show(WidgetTester tester, Fake fake, Widget home) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      apiProvider.overrideWithValue(fake.api()),
      authenticateProvider.overrideWithValue(() async => true),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  group('the words', () {
    test('say who did it, including an approved assistant action', () {
      final t = words('en');
      expect(actorWords(t, <String, Object?>{'actor': 'person'}), 'You');
      expect(actorWords(t, <String, Object?>{'actor': 'agent'}), 'Botler');
      expect(
        actorWords(t, <String, Object?>{
          'actor': 'person',
          'onBehalf': 'agent',
        }),
        'Botler, approved by you',
      );
      expect(channelWords(t, 'outbox'), 'offline, sent later');
      expect(actionWords(t, 'reset'), 'Reset');
    });

    test('read in Filipino too', () {
      final t = words('fil');
      expect(actorWords(t, <String, Object?>{'actor': 'person'}), 'Ikaw');
      expect(actionWords(t, 'create'), 'Idinagdag');
    });
  });

  group('the timeline', () {
    testWidgets('lists who did what with the running balance', (tester) async {
      final fake = Fake();
      await show(tester, fake, const AccountDetailScreen(accountId: 'a1'));
      expect(find.text('GCash'), findsWidgets);
      expect(find.textContaining('Botler · in chat'), findsOneWidget);
      expect(find.textContaining('Botler, approved by you'), findsOneWidget);
      expect(fake.calls, contains('account_history'));
    });

    testWidgets('the tab for money out keeps only the rows that took money', (
      tester,
    ) async {
      await show(tester, Fake(), const AccountDetailScreen(accountId: 'a1'));
      await tester.tap(find.text('Money out'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Botler · in chat'), findsOneWidget);
      expect(find.textContaining('approved by you'), findsNothing);
    });

    testWidgets('choosing Botler sends the filter to the server', (
      tester,
    ) async {
      final fake = Fake();
      await show(tester, fake, const AccountDetailScreen(accountId: 'a1'));
      await tester.tap(find.text('Botler'));
      await tester.pumpAndSettle();
      expect(
        fake.bodies.lastWhere((b) => b.containsKey('accountId'))['by'],
        'agent',
      );
    });

    testWidgets('an entry opens in full with its changes and references', (
      tester,
    ) async {
      await show(tester, Fake(), const AccountDetailScreen(accountId: 'a1'));
      await tester.tap(find.textContaining('Botler · in chat'));
      await tester.pumpAndSettle();
      expect(find.text('What changed'), findsOneWidget);
      expect(find.textContaining('request abcdef12'), findsOneWidget);
      expect(find.text('Copy reference'), findsOneWidget);
    });

    testWidgets('shows a calm banner when the audit trail has a break', (
      tester,
    ) async {
      final fake = Fake()..verifyOk = false;
      await show(tester, fake, const AccountDetailScreen(accountId: 'a1'));
      expect(find.text('The audit trail does not add up'), findsOneWidget);
    });

    testWidgets('reset to zero asks once and sends mode reset with a reason', (
      tester,
    ) async {
      final fake = Fake();
      await show(tester, fake, const AccountDetailScreen(accountId: 'a1'));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset to zero'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reset to zero'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set it'));
      await tester.pumpAndSettle();
      final i = fake.calls.lastIndexOf('snapshot_record');
      expect(i, greaterThanOrEqualTo(0));
      expect(fake.bodies[i]['mode'], 'reset');
      expect(fake.bodies[i]['amount'], 0);
      expect(fake.bodies[i]['reason'], 'Starting again from zero');
      expect(fake.bodies[i]['confirmed'], true);
    });
  });

  group('reset data', () {
    testWidgets('shows the counts, needs the typed word, then erases', (
      tester,
    ) async {
      final fake = Fake();
      await show(tester, fake, const ResetScreen());
      await tester.tap(find.text('Money'));
      await tester.pumpAndSettle();
      expect(find.text('This will erase 12 rows:'), findsOneWidget);
      // A wrong word never reaches the server
      await tester.enterText(find.byType(TextField), 'nope');
      await tester.tap(find.text('Erase now'));
      await tester.pumpAndSettle();
      expect(fake.calls, isNot(contains('data_reset')));
      await tester.enterText(find.byType(TextField), 'RESET');
      await tester.tap(find.text('Erase now'));
      await tester.pumpAndSettle();
      final i = fake.calls.indexOf('data_reset');
      expect(i, greaterThanOrEqualTo(0));
      expect(fake.bodies[i]['typed'], 'RESET');
      expect(fake.bodies[i]['scope'], 'money');
      expect(find.text('Done. 12 rows erased.'), findsOneWidget);
    });
  });
}
