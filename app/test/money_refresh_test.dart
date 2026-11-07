// EVERY SAVED MONEY CHANGE MAKES THE SHARED MONEY LISTS READ AGAIN (BTL-20261107-0354)
// The Accounts screen watched lists that only some screens refreshed by hand. These tests pin the hook that now covers every caller.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// -- MODULES -- //
import 'package:botler/core/api.dart';
import 'package:botler/core/auth.dart';
import 'package:botler/core/json.dart';
import 'package:botler/core/money_verbs.dart';
import 'package:botler/state/providers.dart';

import 'api_verb_keys_test.dart' show writeVerbs;

// -- TYPES -- //

class _SignedIn implements SessionStore {
  @override
  Future<Session?> read() async =>
      const Session(token: 'tok', email: 'a@x.y', name: 'A');

  @override
  Future<void> write(Session s) async {}

  @override
  Future<void> clear() async {}
}

// -- FUNCTIONS -- //

http.Response _ok() => http.Response(
  jsonEncode(<String, Object?>{'result': <String, Object?>{}}),
  200,
  headers: <String, String>{'content-type': 'application/json'},
);

void main() {
  group('which verbs can change the accounts', () {
    test('the money writes do, reads and other areas do not', () {
      for (final v in <String>[
        'expense_log',
        'transfer_record',
        'bill_mark_paid',
        'income_record',
        'goal_update',
        'snapshot_record',
        'undo',
        'account_create',
        'settings_set',
      ]) {
        expect(changesMoney(v), true, reason: v);
      }
      for (final v in <String>[
        'accounts_balances',
        'assets_summary',
        'income_list',
        'settings_get',
        'account_history',
        'split_upcoming',
        'task_create',
        'meal_log',
        'page_edit',
      ]) {
        expect(changesMoney(v), false, reason: v);
      }
    });

    test('every money write of the server registry is covered', () {
      final money = RegExp(
        '^(expense|income|refund|transfer|bill|goal|rule|split|account|snapshot|mark)_',
      );
      final covered = writeVerbs.where(money.hasMatch).toList();
      expect(covered, isNotEmpty);
      for (final v in covered) {
        expect(changesMoney(v), true, reason: v);
      }
    });
  });

  group('the client hook', () {
    test('fires after a saved call and not after a refused one', () async {
      final seen = <String>[];
      var refuse = false;
      final api = ApiClient(
        base: 'https://botler.test',
        token: () async => 'tok',
        client: MockClient(
          (_) async => refuse
              ? http.Response(
                  jsonEncode(<String, Object?>{
                    'error': <String, Object?>{
                      'code': 'INVALID',
                      'message': 'No.',
                    },
                  }),
                  400,
                  headers: <String, String>{'content-type': 'application/json'},
                )
              : _ok(),
        ),
      )..onWrite = seen.add;
      await api.verb('expense_log', <String, Object?>{
        'amount': 1,
      }, 'k-0000001');
      expect(seen, <String>['expense_log']);
      refuse = true;
      await expectLater(
        api.verb('transfer_record', <String, Object?>{}, 'k-0000002'),
        throwsA(isA<ApiException>()),
      );
      expect(seen, <String>['expense_log']);
    });

    test('a listener that throws never fails a saved write', () async {
      final api = ApiClient(
        base: 'https://botler.test',
        token: () async => 'tok',
        client: MockClient((_) async => _ok()),
      )..onWrite = (_) => throw StateError('listener');
      await api.verb('expense_log', <String, Object?>{}, 'k-0000003');
    });
  });

  group('the shared lists', () {
    test('a money write reads them again once, a read does not', () async {
      var balances = 0;
      var assets = 0;
      final container = ProviderContainer(
        overrides: [
          sessionStoreProvider.overrideWithValue(_SignedIn()),
          balancesProvider.overrideWith((ref) async {
            balances++;
            return <Json>[];
          }),
          assetsProvider.overrideWith((ref) async {
            assets++;
            return <String, Object?>{};
          }),
          syncProvider.overrideWith((ref) async => <String, Object?>{}),
        ],
      );
      addTearDown(container.dispose);
      container
        ..listen(balancesProvider, (_, _) {})
        ..listen(assetsProvider, (_, _) {})
        ..listen(syncProvider, (_, _) {});
      await container.read(balancesProvider.future);
      await container.read(assetsProvider.future);
      final hook = container.read(apiProvider).onWrite;
      expect(hook, isNotNull);

      hook!('accounts_balances');
      hook('task_create');
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(balances, 1);

      // A burst of queued writes joins into one refresh
      hook('expense_log');
      hook('transfer_record');
      hook('bill_mark_paid');
      await Future<void>.delayed(const Duration(milliseconds: 450));
      await container.read(balancesProvider.future);
      await container.read(assetsProvider.future);
      expect(balances, 2);
      expect(assets, 2);
    });
  });
}
