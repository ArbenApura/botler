// SEVERAL CURRENCIES ON THE SCREENS: A DOLLAR IS NEVER WRITTEN WITH A PESO SIGN, AN ACCOUNT SHOWS EVERY CURRENCY IT HOLDS WITH THE TOTAL IN THE MAIN CURRENCY, A MISSING RATE IS
// SAID AND LEFT OUT, THE EXPENSE FORM TAKES THE CURRENCY OF A WALLET, AND A BILL IN ANOTHER CURRENCY SHOWS WHAT IT COMES TO IN THE MAIN ONE. THE SERVER IS A STAND-IN.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/core/money_scope.dart';
import 'package:botler/features/expense/expense_screen.dart';
import 'package:botler/features/history/history_screen.dart';
import 'package:botler/features/money/accounts_screen.dart';
import 'package:botler/features/money/audit_words.dart';
import 'package:botler/features/money/bills_parts.dart';
import 'package:botler/features/money/transfer_sheet.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:botler/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- CONSTANTS -- //

const List<Json> _accounts = <Json>[
  <String, Object?>{
    'id': 'acc-wise',
    'name': 'Wise',
    'currency': 'PHP',
    'balance': 100000,
    'minBalance': 0,
    'wallets': <Json>[
      <String, Object?>{'currency': 'PHP', 'balance': 100000},
      <String, Object?>{'currency': 'USD', 'balance': 5000},
    ],
  },
  <String, Object?>{
    'id': 'acc-cash',
    'name': 'Cash',
    'currency': 'PHP',
    'balance': 30000,
    'minBalance': 0,
    'wallets': <Json>[
      <String, Object?>{'currency': 'PHP', 'balance': 30000},
    ],
  },
];

Json _assets({
  List<String> missing = const <String>[],
  bool stale = false,
  List<Json> wallets = const <Json>[],
}) => <String, Object?>{
  'currency': 'PHP',
  'total': 410000,
  'missing': missing,
  'wallets': wallets,
  'accounts': <Json>[
    <String, Object?>{
      'accountId': 'acc-wise',
      'name': 'Wise',
      'subtotal': 380000,
    },
    <String, Object?>{
      'accountId': 'acc-cash',
      'name': 'Cash',
      'subtotal': 30000,
    },
  ],
  'rates': <String, Object?>{
    'asOf': DateTime.now()
        .subtract(Duration(days: stale ? 9 : 0))
        .toUtc()
        .toIso8601String(),
    'stale': stale,
    'source': 'rates.test',
    'configured': true,
  },
};

// -- FUNCTIONS -- //

Future<ProviderContainer> _container({
  bool offline = false,
  Json? assets,
  List<Json>? accounts,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'accounts.cache': jsonEncode(accounts ?? _accounts),
  });
  final prefs = await SharedPreferences.getInstance();
  final client = MockClient.streaming((req, stream) async {
    if (offline) throw http.ClientException('offline');
    final verb = req.url.path.split('/').last;
    final result = switch (verb) {
      'accounts_balances' => accounts ?? _accounts,
      'assets_summary' => assets ?? _assets(),
      'ledger_spending' => <String, Object?>{
        'spending': 20000,
        'untracked': 0,
        'currency': 'PHP',
        'otherCurrencies': <String>['USD'],
      },
      'ledger_list' => <Json>[
        <String, Object?>{
          'id': 'tx1',
          'type': 'expense',
          'amount': 500,
          'currency': 'USD',
          'accountId': 'acc-wise',
          'note': 'coffee',
          'occurredAt': DateTime.now().toUtc().toIso8601String(),
        },
      ],
      _ => <String, Object?>{},
    };
    return http.StreamedResponse(
      Stream<List<int>>.value(
        utf8.encode(jsonEncode(<String, Object?>{'result': result})),
      ),
      200,
    );
  });
  final c = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
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

Widget _app(ProviderContainer c, Widget home) => UncontrolledProviderScope(
  container: c,
  child: MaterialApp.router(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildTheme(Brightness.light),
    routerConfig: GoRouter(
      routes: <RouteBase>[GoRoute(path: '/', builder: (_, _) => home)],
    ),
  ),
);

void main() {
  group('amounts', () {
    testWidgets(
      'a dollar amount keeps its own sign under a peso main currency',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: MoneyScope(
              currency: 'PHP',
              child: Column(
                children: <Widget>[
                  Amount(1234, currency: 'USD'),
                  Amount(1234),
                  Amount(1234, currency: 'JPY'),
                ],
              ),
            ),
          ),
        );
        expect(find.text(r'$12.34'), findsOneWidget);
        expect(find.text('₱12.34'), findsOneWidget);
        expect(find.text('¥1,234'), findsOneWidget);
      },
    );

    testWidgets('a history line writes a count of dollars in dollars', (
      tester,
    ) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MoneyScope(
            currency: 'PHP',
            child: Builder(
              builder: (context) {
                captured = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(valueWords(captured, 'amount', 5000, 'USD'), r'$50.00');
      expect(valueWords(captured, 'min_balance', 5000, 'USD'), '₱50.00');
      // What arrived in a conversion is in the currency it landed in
      expect(valueWords(captured, 'to_amount', 9940, 'USD'), r'$99.40');
      expect(
        billAmountText(captured, 1599, 'USD', 89544),
        r'$15.99 (about ₱895.44)',
      );
      expect(
        billAmountText(captured, 1599, 'USD', null, missingRate: true),
        r'$15.99 (no exchange rate yet)',
      );
      expect(billAmountText(captured, 50000, 'PHP', null), '₱500.00');
    });

    test('the rate a person got reads as one unit of what was sent', () {
      expect(impliedRate(560000, 'PHP', 9940, 'USD'), '1 PHP = 0.01775 USD');
      expect(impliedRate(10000, 'USD', 560000, 'PHP'), '1 USD = 56.0000 PHP');
      expect(impliedRate(15720, 'JPY', 10000, 'USD'), '1 JPY = 0.006361 USD');
      expect(impliedRate(0, 'PHP', 10, 'USD'), '');
    });

    test(
      'an older server with no wallets is one wallet in the account currency',
      () {
        final wallets = walletsOf(<String, Object?>{
          'currency': 'JPY',
          'balance': 900,
        });
        expect(wallets.single['currency'], 'JPY');
        expect(wallets.single['balance'], 900);
        expect(hasWalletIn(_accounts.first, 'USD'), isTrue);
        expect(hasWalletIn(_accounts.last, 'USD'), isFalse);
      },
    );
  });

  group('the accounts screen', () {
    testWidgets(
      'shows the total in the main currency, every wallet of an account, and the date of the rates',
      (tester) async {
        final c = await _container();
        await tester.pumpWidget(_app(c, const AccountsScreen()));
        await tester.pumpAndSettle();
        expect(find.text('Everything you have'), findsOneWidget);
        expect(find.text('₱4,100.00'), findsOneWidget);
        // The Wise account lists both wallets, each in its own currency, and what it comes to in all
        expect(find.text('₱1,000.00'), findsOneWidget);
        expect(find.text(r'$50.00'), findsOneWidget);
        expect(find.text('About ₱3,800.00 in all'), findsOneWidget);
        expect(find.textContaining('Exchange rates as of'), findsOneWidget);
      },
    );

    testWidgets(
      'shows the rate of each added currency once, and none for the main currency, a missing rate or no foreign wallet',
      (tester) async {
        Json wallet(String currency, Object? rate) => <String, Object?>{
          'accountId': 'acc-wise',
          'currency': currency,
          'rate': rate,
        };
        final c = await _container(
          assets: _assets(
            wallets: <Json>[
              wallet('PHP', null),
              wallet('USD', '56.12'),
              wallet('USD', '56.12'),
              wallet('ZAR', null),
            ],
          ),
        );
        await tester.pumpWidget(_app(c, const AccountsScreen()));
        await tester.pumpAndSettle();
        expect(find.text('1 USD = 56.12 PHP'), findsOneWidget);
        expect(find.textContaining('ZAR ='), findsNothing);
        expect(find.textContaining('1 PHP ='), findsNothing);
      },
    );

    testWidgets('shows no rate lines when no foreign currency is held', (
      tester,
    ) async {
      final c = await _container();
      await tester.pumpWidget(_app(c, const AccountsScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining(' = '), findsNothing);
    });

    testWidgets('says a currency has no rate and says the rates are old', (
      tester,
    ) async {
      final c = await _container(
        assets: _assets(missing: <String>['ZAR'], stale: true),
      );
      await tester.pumpWidget(_app(c, const AccountsScreen()));
      await tester.pumpAndSettle();
      expect(
        find.text('No exchange rate yet for ZAR. It is not in the total.'),
        findsOneWidget,
      );
      expect(find.textContaining('Exchange rates are old'), findsOneWidget);
    });

    testWidgets('shows the last total when offline, and says so', (
      tester,
    ) async {
      // The answer that worked before is kept on the phone
      SharedPreferences.setMockInitialValues(<String, Object>{
        'accounts.cache': jsonEncode(_accounts),
        'assets.cache': jsonEncode(_assets()),
      });
      final c = await _container(offline: true);
      await c
          .read(prefsProvider)
          .setString('assets.cache', jsonEncode(_assets()));
      await tester.pumpWidget(_app(c, const AccountsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('₱4,100.00'), findsOneWidget);
      expect(
        find.text('No connection. Showing the last total.'),
        findsOneWidget,
      );
    });
  });

  group('moving money between currencies', () {
    testWidgets(
      'asks what arrived, shows the rate that implies, and keeps the move when offline',
      (tester) async {
        final c = await _container(offline: true);
        await c.read(balancesProvider.future);
        await tester.pumpWidget(
          _app(
            c,
            Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showMoveSheet(
                    context,
                    ref,
                    from: _accounts.first,
                    fromCurrency: 'PHP',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        // The only other wallet of the account is the dollar one, so a second amount is asked for
        expect(
          find.widgetWithText(TextField, 'Amount sent (PHP)'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(TextField, 'Amount that arrived (USD)'),
          findsOneWidget,
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Amount sent (PHP)'),
          '5600',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Amount that arrived (USD)'),
          '99.40',
        );
        await tester.pump();
        expect(find.text('Your rate: 1 PHP = 0.01775 USD'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Move money'));
        await tester.pumpAndSettle();
        final item = c.read(outboxProvider).items().single;
        expect(item.verb, 'transfer_record');
        expect(item.args, containsPair('amount', 560000));
        expect(item.args, containsPair('toAmount', 9940));
        expect(item.args, containsPair('currency', 'PHP'));
        expect(item.args, containsPair('toCurrency', 'USD'));
        expect(item.args['fromAccountId'], 'acc-wise');
        expect(item.args['toAccountId'], 'acc-wise');
      },
    );
  });

  group('the history', () {
    testWidgets(
      'names the other currencies it did not add, and writes each entry in its own',
      (tester) async {
        final c = await _container();
        await tester.pumpWidget(_app(c, const HistoryScreen()));
        await tester.pumpAndSettle();
        expect(
          find.text('Also spent in USD. Those are not added here.'),
          findsOneWidget,
        );
        expect(find.text('₱200.00'), findsOneWidget);
        expect(find.text(r'-$5.00'), findsOneWidget);
      },
    );
  });

  group('the expense form', () {
    testWidgets(
      'takes the currency of a wallet and keeps it with the entry when offline',
      (tester) async {
        final c = await _container(offline: true);
        await tester.pumpWidget(_app(c, const ExpenseScreen()));
        await tester.pumpAndSettle();
        // The first account is Wise: its own wallets are chips, the amount is asked in the one chosen
        expect(find.widgetWithText(ChoiceChip, 'USD'), findsOneWidget);
        await tester.tap(find.widgetWithText(ChoiceChip, 'USD'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'How much? (USD)'),
          '5',
        );
        await tester.tap(find.text('Log it'));
        await tester.pumpAndSettle();
        final item = c.read(outboxProvider).items().single;
        expect(item.verb, 'expense_log');
        expect(item.args['amount'], 500);
        expect(item.args['currency'], 'USD');
        expect(item.args['accountId'], 'acc-wise');
      },
    );

    testWidgets('an account with one wallet asks in its own currency', (
      tester,
    ) async {
      final c = await _container(
        offline: true,
        accounts: <Json>[
          <String, Object?>{
            'id': 'acc-tokyo',
            'name': 'Tokyo',
            'currency': 'JPY',
            'balance': 0,
            'wallets': <Json>[
              <String, Object?>{'currency': 'JPY', 'balance': 0},
            ],
          },
        ],
      );
      await tester.pumpWidget(_app(c, const ExpenseScreen()));
      await tester.pumpAndSettle();
      // Yen have no cents, so 900 is 900 and a decimal point is refused
      await tester.enterText(
        find.widgetWithText(TextField, 'How much? (JPY)'),
        '900',
      );
      await tester.tap(find.text('Log it'));
      await tester.pumpAndSettle();
      final item = c.read(outboxProvider).items().single;
      expect(item.args['amount'], 900);
      // The account's own currency is not sent: an ordinary entry is the same request as before
      expect(item.args.containsKey('currency'), isFalse);
    });
  });
}
