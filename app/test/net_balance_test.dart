// NET BALANCE (BTL-20261030-0546): THE SETTING IS READ WITH A SAFE DEFAULT, THE ACCOUNTS SCREEN LEADS WITH THE NET WHEN IT IS ON AND SHOWS WHAT A DUE
// BILL STILL LACKS, A MISSING OR NULL NET MEANS THE BALANCE AS COUNTED (NEVER A NET OF ZERO), AND A TOGGLE THE SERVER REFUSES KEEPS THE OLD VALUE.
// THE SERVER IS A STAND-IN.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/features/chat/summary_card.dart';
import 'package:botler/features/money/accounts_screen.dart';
import 'package:botler/features/money/net_parts.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:botler/ui/skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- CONSTANTS -- //

/// One account with a due bill it cannot fully cover, and the same account's answer from a server that has no net yet.
Json _account({bool withNet = true, bool netNull = false}) => <String, Object?>{
  'id': 'acc-gcash',
  'name': 'GCash',
  'currency': 'PHP',
  'balance': 100000,
  'minBalance': 0,
  'wallets': <Json>[
    <String, Object?>{
      'currency': 'PHP',
      'balance': 100000,
      if (withNet) ...<String, Object?>{
        'netBalance': netNull ? null : 0,
        'held': netNull ? null : 150000,
        'shortfall': netNull ? null : 50000,
        'holds': <Json>[
          <String, Object?>{
            'kind': 'bill',
            'label': 'Rent',
            'amount': 150000,
            'dueDate': '2026-11-05',
          },
        ],
      },
    },
  ],
  if (withNet) ...<String, Object?>{
    'netBalance': netNull ? null : 0,
    'held': netNull ? null : 150000,
    'shortfall': netNull ? null : 50000,
  },
};

Json _assets({bool withNet = true}) => <String, Object?>{
  'currency': 'PHP',
  'total': 100000,
  'missing': <String>[],
  'wallets': <Json>[],
  'accounts': <Json>[
    <String, Object?>{
      'accountId': 'acc-gcash',
      'name': 'GCash',
      'subtotal': 100000,
      if (withNet) 'netSubtotal': 0,
    },
  ],
  if (withNet) ...<String, Object?>{'netTotal': 0, 'shortfallTotal': 50000},
  'rates': <String, Object?>{
    'asOf': DateTime.now().toUtc().toIso8601String(),
    'stale': false,
    'source': 'rates.test',
    'configured': true,
  },
};

// -- FUNCTIONS -- //

Future<ProviderContainer> _container({
  bool net = true,
  bool serverNet = true,
  bool netNull = false,
  bool refuseSave = false,
  List<String>? saved,
  List<Json>? accounts,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'settings.showNet': net,
  });
  final prefs = await SharedPreferences.getInstance();
  final client = MockClient.streaming((req, stream) async {
    final verb = req.url.path.split('/').last;
    if (verb == 'settings_set' && refuseSave) {
      return http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{'code': 'INTERNAL', 'message': 'No.'},
            }),
          ),
        ),
        500,
      );
    }
    if (verb == 'settings_set') {
      final body = jsonDecode(await utf8.decodeStream(stream));
      saved?.add(jsonEncode(body));
    }
    final result = switch (verb) {
      'accounts_balances' =>
        accounts ?? <Json>[_account(withNet: serverNet, netNull: netNull)],
      'assets_summary' => _assets(withNet: serverNet && !netNull),
      'settings_set' => <String, Object?>{
        'settings': <String, Object?>{'showNetBalance': !net},
        'notice': null,
      },
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
  group('the setting', () {
    test('is off when nothing is stored, and read when it is', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      expect(
        readSettings(await SharedPreferences.getInstance()).showNetBalance,
        isFalse,
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'settings.showNet': true,
      });
      expect(
        readSettings(await SharedPreferences.getInstance()).showNetBalance,
        isTrue,
      );
    });

    test(
      'keeps what the phone has when an older server sends no field',
      () async {
        final c = await _container(net: true);
        await c.read(settingsProvider.notifier).pullFromServer();
        // The stand-in answers {} for settings_get, as an older server would
        expect(c.read(settingsProvider).showNetBalance, isTrue);
      },
    );
  });

  group('the accounts screen', () {
    testWidgets(
      'leads with the net, the balance counted smaller, and what a due bill lacks',
      (tester) async {
        final c = await _container();
        await tester.pumpWidget(_app(c, const AccountsScreen()));
        await tester.pumpAndSettle();
        expect(find.text('Net, after bills and goals'), findsOneWidget);
        expect(find.text('₱0.00'), findsWidgets);
        expect(find.text('Balance ₱1,000.00'), findsWidgets);
        expect(
          find.text('Short by ₱500.00 for bills due before payday'),
          findsWidgets,
        );
        expect(find.text('Show the balance as counted'), findsOneWidget);
      },
    );

    testWidgets('shows the balance as counted when the setting is off', (
      tester,
    ) async {
      final c = await _container(net: false);
      await tester.pumpWidget(_app(c, const AccountsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Everything you have'), findsOneWidget);
      expect(find.text('₱1,000.00'), findsWidgets);
      expect(find.textContaining('Short by'), findsNothing);
      expect(find.text('Show net balance'), findsOneWidget);
    });

    testWidgets(
      'shows the balance as counted, with no shortfall, when the server sends no net',
      (tester) async {
        final c = await _container(serverNet: false);
        await tester.pumpWidget(_app(c, const AccountsScreen()));
        await tester.pumpAndSettle();
        expect(find.text('Everything you have'), findsOneWidget);
        expect(find.textContaining('Short by'), findsNothing);
        expect(find.textContaining('Balance ₱'), findsNothing);
      },
    );

    testWidgets(
      'says the net is unavailable when the server could not work it out',
      (tester) async {
        final c = await _container(netNull: true);
        await tester.pumpWidget(_app(c, const AccountsScreen()));
        await tester.pumpAndSettle();
        expect(find.textContaining('could not be worked out'), findsOneWidget);
        expect(find.textContaining('Short by'), findsNothing);
        expect(find.text('₱1,000.00'), findsWidgets);
      },
    );

    testWidgets(
      'flips the setting from the line under the total, through the server',
      (tester) async {
        final sent = <String>[];
        final c = await _container(net: false, saved: sent);
        await tester.pumpWidget(_app(c, const AccountsScreen()));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Show net balance'));
        await tester.pumpAndSettle();
        expect(sent.single, contains('"showNetBalance":true'));
        expect(c.read(settingsProvider).showNetBalance, isTrue);
      },
    );

    testWidgets(
      'keeps the old value and says so when the server refuses the change',
      (tester) async {
        final c = await _container(net: false, refuseSave: true);
        await tester.pumpWidget(_app(c, const AccountsScreen()));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Show net balance'));
        await tester.pumpAndSettle();
        expect(c.read(settingsProvider).showNetBalance, isFalse);
        expect(find.byType(SnackBar), findsOneWidget);
      },
    );
  });

  group('on a small screen', () {
    testWidgets(
      'an account card with a shortfall holds at 360 dp in Filipino',
      (tester) async {
        tester.view.physicalSize = const Size(360 * 2, 640 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final c = await _container();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp.router(
              locale: const Locale('fil'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildTheme(Brightness.light),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.0)),
                child: child ?? const SizedBox(),
              ),
              routerConfig: GoRouter(
                routes: <RouteBase>[
                  GoRoute(path: '/', builder: (_, _) => const AccountsScreen()),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // The card is below the tall total at this size: scroll to it
        await tester.scrollUntilVisible(find.text('GCash'), 200);
        await tester.pumpAndSettle();
        // No overflow stripe, and the account name is still there
        expect(tester.takeException(), isNull);
        expect(find.text('GCash'), findsOneWidget);
      },
    );

    testWidgets(
      'many held lines open inside a bounded list and the page below keeps its room',
      (tester) async {
        tester.view.physicalSize = const Size(360 * 2, 640 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final wallet = <String, Object?>{
          'balance': 900000,
          'netBalance': 100000,
          'holds': <Json>[
            for (var i = 0; i < 14; i++)
              <String, Object?>{
                'kind': 'bill',
                'label': 'Bill number $i',
                'amount': 50000,
                'dueDate': '2026-11-05',
              },
          ],
        };
        await tester.pumpWidget(
          _app(
            await _container(),
            Scaffold(
              body: Column(
                children: <Widget>[
                  NetHolds(wallet: wallet, currency: 'PHP'),
                  const Expanded(child: Center(child: Text('entries'))),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Net now'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('entries'), findsOneWidget);
      },
    );

    testWidgets('a wallet with no net shows the balance as counted', (
      tester,
    ) async {
      final wallet = <String, Object?>{'balance': 123400};
      await tester.pumpWidget(
        _app(
          await _container(),
          Scaffold(
            body: NetAmount(wallet: wallet, currency: 'PHP'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('₱1,234.00'), findsOneWidget);
      expect(find.textContaining('Balance'), findsNothing);
    });
  });

  group('what consumed an account', () {
    Json four() {
      final a = _account();
      final w = asJsonList(a['wallets']).first;
      return <String, Object?>{
        ...a,
        'wallets': <Json>[
          <String, Object?>{
            ...w,
            'holds': <Json>[
              for (final n in <String>['Rent', 'Meralco', 'Wifi', 'Water'])
                <String, Object?>{
                  'kind': 'bill',
                  'label': n,
                  'amount': 10000,
                  'dueDate': '2026-11-05',
                },
            ],
          },
        ],
      };
    }

    testWidgets('lists the first three bills on the card and folds the rest', (
      tester,
    ) async {
      final c = await _container(accounts: <Json>[four()]);
      await tester.pumpWidget(_app(c, const AccountsScreen()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Taken from this by'), 200);
      expect(find.text('Rent, due Nov 5'), findsOneWidget);
      expect(find.text('Meralco, due Nov 5'), findsOneWidget);
      expect(find.text('Wifi, due Nov 5'), findsOneWidget);
      expect(find.text('Water, due Nov 5'), findsNothing);
      expect(find.text('+1 more, open the account to see all'), findsOneWidget);
      expect(find.text('-₱100.00'), findsNWidgets(3));
    });

    testWidgets('shows no lines with the net off', (tester) async {
      final c = await _container(net: false, accounts: <Json>[four()]);
      await tester.pumpWidget(_app(c, const AccountsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Taken from this by'), findsNothing);
    });

    testWidgets('shows no lines when the server sent no net', (tester) async {
      final c = await _container(serverNet: false);
      await tester.pumpWidget(_app(c, const AccountsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Taken from this by'), findsNothing);
    });
  });

  group('the wallet button sheet', () {
    const sync = <String, Object?>{
      'summary': <String, Object?>{
        'total': 100000,
        'currency': 'PHP',
        'nextBill': null,
        'firstEventToday': null,
      },
    };

    Future<void> openSheet(WidgetTester tester, ProviderContainer c) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildTheme(Brightness.light),
            routerConfig: GoRouter(
              routes: <RouteBase>[
                GoRoute(
                  path: '/',
                  builder: (_, _) => Scaffold(
                    body: Builder(
                      builder: (context) => TextButton(
                        onPressed: () => showSummarySheet(context),
                        child: const Text('open'),
                      ),
                    ),
                  ),
                ),
                GoRoute(
                  path: '/account/:id',
                  builder: (_, state) =>
                      Text('detail ${state.pathParameters['id']}'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<ProviderContainer> withSync({
      bool net = true,
      bool serverNet = true,
      List<Json>? accounts,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'settings.showNet': net,
      });
      final prefs = await SharedPreferences.getInstance();
      final client = MockClient.streaming((req, stream) async {
        final verb = req.url.path.split('/').last;
        final result = switch (verb) {
          'accounts_balances' =>
            accounts ?? <Json>[_account(withNet: serverNet)],
          'assets_summary' => _assets(withNet: serverNet),
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
          syncProvider.overrideWith((ref) async => sync),
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

    testWidgets(
      'leads with the net total, lists the accounts and what consumed them',
      (tester) async {
        await openSheet(tester, await withSync());
        expect(find.text('Net, after bills and goals'), findsOneWidget);
        expect(find.text('Balance ₱1,000.00'), findsWidgets);
        expect(find.text('Taken from this by'), findsOneWidget);
        expect(find.text('Rent, due Nov 5'), findsOneWidget);
        expect(find.textContaining('Short by ₱500.00'), findsWidgets);
      },
    );

    testWidgets('shows every wallet of an account, not only the peso one', (
      tester,
    ) async {
      final wise = <String, Object?>{
        'id': 'acc-wise',
        'name': 'Wise',
        'currency': 'PHP',
        'balance': 250000,
        'wallets': <Json>[
          <String, Object?>{'currency': 'PHP', 'balance': 250000},
          <String, Object?>{'currency': 'USD', 'balance': 10050},
        ],
      };
      await openSheet(tester, await withSync(accounts: <Json>[wise]));
      expect(find.text('Wise'), findsOneWidget);
      expect(find.text('₱2,500.00'), findsOneWidget);
      expect(find.text(r'$100.50'), findsOneWidget);
    });

    testWidgets('a row opens the account and closes the sheet', (tester) async {
      await openSheet(tester, await withSync());
      await tester.tap(find.text('GCash'));
      await tester.pumpAndSettle();
      expect(find.text('detail acc-gcash'), findsOneWidget);
    });

    testWidgets(
      'is the summary as it was with the net off, and with no net from the server',
      (tester) async {
        await openSheet(tester, await withSync(net: false));
        expect(find.text('Across your accounts'), findsOneWidget);
        // The accounts are listed (with their marks) whether the net leads or not; the hold lines come only with the net
        expect(find.text('₱1,000.00'), findsWidgets);
        expect(find.text('Taken from this by'), findsNothing);
        expect(find.text('GCash'), findsOneWidget);
      },
    );

    testWidgets('shows the total as counted when the server sends no net', (
      tester,
    ) async {
      await openSheet(tester, await withSync(serverNet: false));
      expect(find.text('Net, after bills and goals'), findsNothing);
      expect(find.text('₱1,000.00'), findsWidgets);
    });
  });

  group('while the money loads', () {
    Future<ProviderContainer> slow(Completer<void> gate) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'settings.showNet': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final client = MockClient.streaming((req, stream) async {
        final verb = req.url.path.split('/').last;
        if (verb == 'accounts_balances' || verb == 'assets_summary') {
          await gate.future;
        }
        final result = switch (verb) {
          'accounts_balances' => <Json>[_account()],
          'assets_summary' => _assets(),
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
          syncProvider.overrideWith(
            (ref) async => <String, Object?>{
              'summary': <String, Object?>{
                'total': 100000,
                'currency': 'PHP',
                'nextBill': null,
                'firstEventToday': null,
              },
            },
          ),
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

    testWidgets(
      'the card and the sheet accounts hold their place as skeletons, then fill without the card growing',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2200);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final gate = Completer<void>();
        final c = await slow(gate);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildTheme(Brightness.light),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showSummarySheet(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pump(const Duration(milliseconds: 600));
        // Waiting: skeletons, and none of the net lines yet
        expect(find.byType(Skeleton), findsWidgets);
        expect(find.text('Net, after bills and goals'), findsNothing);
        final waitingCard = tester.getSize(find.byType(SummaryCard)).height;
        gate.complete();
        await tester.pumpAndSettle();
        expect(find.text('Net, after bills and goals'), findsOneWidget);
        expect(find.text('GCash'), findsOneWidget);
        // The card keeps its height (its skeleton has the net lines): it was 78 px shorter while loading before the net lines were reserved
        final loadedCard = tester.getSize(find.byType(SummaryCard)).height;
        expect((loadedCard - waitingCard).abs(), lessThan(60));
      },
    );
  });

  group('what a wallet holds', () {
    testWidgets('lists the bill with its date and the net now', (tester) async {
      final wallet = asJsonList(_account()['wallets']).first;
      await tester.pumpWidget(
        _app(
          await _container(),
          Scaffold(
            body: NetHolds(wallet: wallet, currency: 'PHP'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Net now'), findsOneWidget);
      // Closed until the person opens it
      expect(find.text('Rent, due Nov 5'), findsNothing);
      await tester.tap(find.text('Net now'));
      await tester.pumpAndSettle();
      expect(find.text('Rent, due Nov 5'), findsOneWidget);
      expect(find.text('₱1,500.00'), findsOneWidget);
    });
  });
}
