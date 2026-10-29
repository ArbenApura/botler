// A PAYDAY RULE THAT SAVES FOR A BILL (BTL-20261029-0119): WHICH BILLS A RULE CAN SAVE FOR, THE "SAVES FOR" ROW AND ITS SHEET (LINK, UNLINK, A
// REFUSAL, NO CONNECTION), AND THE SPLIT CARD ROWS FOR WHAT DID NOT COME FROM THE PAY. THE SERVER IS A STAND-IN THAT ANSWERS LIKE THE REAL ONE.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/features/payday/rule_funding.dart';
import 'package:botler/features/payday/split_card.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- TYPES -- //

/// A stand-in server: keeps every body sent per verb and answers ok, a refusal, or no connection.
class _Server {
  final Map<String, List<Json>> bodies = <String, List<Json>>{};
  bool offline = false;
  String? refuse;

  MockClient get client => MockClient((req) async {
    final verb = req.url.path.split('/').last;
    (bodies[verb] ??= <Json>[]).add(decodeJson(req.body));
    if (offline) throw http.ClientException('offline');
    if (refuse != null) {
      return http.Response(
        jsonEncode(<String, Object?>{
          'error': <String, Object?>{'code': 'INVALID', 'message': refuse},
        }),
        400,
      );
    }
    return http.Response(
      jsonEncode(<String, Object?>{'result': <String, Object?>{}}),
      200,
    );
  });
}

// -- CONSTANTS -- //

const Json _rule = <String, Object?>{
  'id': 'rule-1',
  'mode': 'fixed',
  'status': 'active',
  'targetAccountId': 'acc-rcbc',
  'label': 'Parents',
  'fundsBillId': null,
  'fundsBillName': null,
};

const List<Json> _bills = <Json>[
  <String, Object?>{
    'id': 'bill-parents',
    'name': 'Parents allowance',
    'accountId': 'acc-rcbc',
    'currency': 'PHP',
    'active': true,
  },
  <String, Object?>{
    'id': 'bill-wifi',
    'name': 'WiFi',
    'accountId': 'acc-gcash',
    'currency': 'PHP',
    'active': true,
  },
  <String, Object?>{
    'id': 'bill-vps',
    'name': 'VPS',
    'accountId': 'acc-rcbc',
    'currency': 'USD',
    'active': true,
  },
  <String, Object?>{
    'id': 'bill-old',
    'name': 'Old',
    'accountId': 'acc-rcbc',
    'currency': 'PHP',
    'active': false,
  },
];

// -- FUNCTIONS -- //

Future<ProviderContainer> _container(_Server s) async {
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

Widget _app(ProviderContainer c, Widget home) => UncontrolledProviderScope(
  container: c,
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildTheme(Brightness.light),
    home: Scaffold(body: SingleChildScrollView(child: home)),
  ),
);

/// A button that opens the sheet for [_rule], so the test drives it like the rule card does.
class _Opener extends ConsumerWidget {
  const _Opener(this.rule, {super.key});

  final Json rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SavesForRow(
    billName: str(rule['fundsBillName']),
    onTap: () =>
        pickSavesFor(context, ref, rule, billsForRule(rule, _bills, 'PHP')),
  );
}

// -- TESTS -- //

void main() {
  group('which bills a rule can save for', () {
    test('only switched-on bills in the main currency paid from the account the rule fills', () {
      expect(
        billsForRule(_rule, _bills, 'PHP').map((b) => b['id']).toList(),
        <String>['bill-parents'],
      );
    });

    test('none for a percentage, a goal or a retired rule', () {
      for (final r in <Json>[
        <String, Object?>{..._rule, 'mode': 'percent'},
        <String, Object?>{..._rule, 'targetAccountId': null},
        <String, Object?>{..._rule, 'status': 'retired'},
      ]) {
        expect(billsForRule(r, _bills, 'PHP'), isEmpty);
      }
    });
  });

  group('the Saves for row and sheet', () {
    testWidgets('links a bill, then unlinks it, and says so', (tester) async {
      final s = _Server();
      final c = await _container(s);
      await tester.pumpWidget(_app(c, const _Opener(_rule)));
      expect(find.text('Saves for a bill?'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('^Choose the bill this rule saves for')),
        findsOneWidget,
      );
      expect(tester.getSize(find.byType(SavesForRow)).height >= 48, isTrue);

      await tester.tap(find.byType(SavesForRow));
      await tester.pumpAndSettle();
      expect(find.text('What does this rule save for?'), findsOneWidget);
      // Only the bill the rule can save for is offered, beside Nothing
      expect(find.widgetWithText(ChoiceChip, 'Parents allowance'), findsOne);
      expect(find.widgetWithText(ChoiceChip, 'WiFi'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Parents allowance'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(s.bodies['rule_update']?.single, <String, Object?>{
        'ruleId': 'rule-1',
        'fundsBillId': 'bill-parents',
      });
      expect(find.text('Saved.'), findsOneWidget);

      final linked = <String, Object?>{
        ..._rule,
        'fundsBillId': 'bill-parents',
        'fundsBillName': 'Parents allowance',
      };
      await tester.pumpWidget(
        _app(c, _Opener(linked, key: const ValueKey<int>(2))),
      );
      expect(find.text('Saves for Parents allowance'), findsOneWidget);
      await tester.tap(find.byType(SavesForRow));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Nothing'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(s.bodies['rule_update']?.last['fundsBillId'], isNull);
      expect(s.bodies['rule_update']?.last.containsKey('fundsBillId'), isTrue);
    });

    testWidgets(
      'keeps the sheet open with the reason when the server refuses, or there is no connection',
      (tester) async {
        final s = _Server()
          ..refuse = 'Only a rule with a fixed amount can save for a bill.';
        final c = await _container(s);
        await tester.pumpWidget(_app(c, const _Opener(_rule)));
        await tester.tap(find.byType(SavesForRow));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'Parents allowance'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        expect(find.text('What does this rule save for?'), findsOneWidget);
        expect(find.textContaining('fixed amount'), findsOneWidget);

        s
          ..refuse = null
          ..offline = true;
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        expect(find.text('What does this rule save for?'), findsOneWidget);
        expect(find.text('Saved.'), findsNothing);
      },
    );
  });

  group('the split card', () {
    Json plan(Json extra, {String status = 'proposed'}) => <String, Object?>{
      'id': 'p1',
      'status': status,
      'payday': '2026-11-02',
      'pay': 1900000,
      'gap': status == 'shortfall' ? 80000 : 0,
      'sentTransfers': <Object?>[],
      'result': <String, Object?>{
        'status': status == 'shortfall' ? 'shortfall' : 'ok',
        'accountNames': <String, Object?>{
          'acc-rcbc': 'RCBC',
          'acc-gcash': 'GCash',
        },
        'lines': <Json>[
          <String, Object?>{
            'label': 'Parents',
            'amount': 1900000,
            'accountId': 'acc-rcbc',
          },
        ],
        'transfers': <Json>[],
        'cutOptions': <Json>[],
        ...extra,
      },
    };

    final parts = <String, Object?>{
      'covered': <Json>[
        <String, Object?>{
          'label': 'WiFi',
          'accountId': 'acc-gcash',
          'amount': 150000,
        },
        <String, Object?>{
          'label': 'Meralco',
          'accountId': 'acc-gone',
          'amount': 2496,
        },
      ],
      'funded': <Json>[
        <String, Object?>{
          'label': 'Pocket money',
          'ruleLabel': 'Pocket money',
          'accountId': 'acc-rcbc',
          'amount': 300000,
        },
      ],
      'unfunded': <Json>[
        <String, Object?>{
          'label': 'Parents',
          'accountId': 'acc-rcbc',
          'amount': 350000,
        },
      ],
      'brokenLinks': <Json>[
        <String, Object?>{
          'ruleLabel': 'Mommy',
          'billName': 'Mommy allowance',
          'reason': 'the bill is switched off',
        },
      ],
    };

    testWidgets(
      'lists what was covered, saved by a rule and still needed, and a rule that cannot save',
      (tester) async {
        final c = await _container(_Server());
        await tester.pumpWidget(_app(c, SplitCard(plan: plan(parts))));
        expect(find.text('Not taken from this pay'), findsOneWidget);
        expect(find.text('WiFi  ·  already in GCash'), findsOneWidget);
        // An account the plan no longer names falls back to a plain word
        expect(find.text('Meralco  ·  already in account'), findsOneWidget);
        expect(
          find.text('Pocket money  ·  saved by Pocket money'),
          findsOneWidget,
        );
        expect(
          find.text('Parents  ·  still needed from this pay'),
          findsOneWidget,
        );
        expect(find.text('₱1,500.00'), findsOneWidget);
        expect(
          find.text(
            'Mommy cannot save for Mommy allowance: the bill is switched off.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('shows none of it on a short pay, nor when there is nothing', (
      tester,
    ) async {
      final c = await _container(_Server());
      await tester.pumpWidget(
        _app(c, SplitCard(plan: plan(parts, status: 'shortfall'))),
      );
      expect(find.text('Not taken from this pay'), findsNothing);
      await tester.pumpWidget(
        _app(
          c,
          SplitCard(
            key: const ValueKey<int>(2),
            plan: plan(<String, Object?>{}),
          ),
        ),
      );
      expect(find.text('Not taken from this pay'), findsNothing);
    });
  });
}
