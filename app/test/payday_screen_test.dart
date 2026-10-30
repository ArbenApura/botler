// THE PAYDAY SCREEN (BTL-20261030-0911): THE OPEN SPLIT SITS UNDER ITS PAYDAY, A PAYDAY CAN BE CHANGED OR DELETED, A RULE CAN BE STOPPED OR DELETED,
// AND AN EARLIER SPLIT (OR ALL OF THEM) CAN BE DELETED AFTER THE PERSON IS TOLD WHAT HAPPENS. THE SERVER IS A STAND-IN THAT KEEPS THE CALLS.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/features/payday/payday_screen.dart';
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

// -- CONSTANTS -- //

Json _plan(String id, String payday, String status) => <String, Object?>{
  'id': id,
  'incomeScheduleId': 'inc-1',
  'payday': payday,
  'pay': 2500000,
  'status': status,
  'gap': 0,
  'sentTransfers': <Json>[],
  'result': <String, Object?>{
    'lines': <Json>[],
    'transfers': <Json>[],
    'accountNames': <String, Object?>{},
  },
};

Json _rule(String id, String status) => <String, Object?>{
  'id': id,
  'status': status,
  'mode': 'fixed',
  'label': 'Fund $id',
  'summary': 'Fund $id: Put ₱500.00 into GCash, from 2026-10-01.',
  'targetName': 'GCash',
};

// -- FUNCTIONS -- //

Future<({ProviderContainer c, List<({String verb, Json body})> calls})> _server(
  WidgetTester tester, {
  List<Json>? splits,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final calls = <({String verb, Json body})>[];
  final client = MockClient.streaming((req, stream) async {
    final verb = req.url.path.split('/').last;
    final raw = await utf8.decodeStream(stream);
    final body = raw.isEmpty ? <String, Object?>{} : asJson(jsonDecode(raw));
    calls.add((verb: verb, body: body));
    final result = switch (verb) {
      'income_list' => <Json>[
        <String, Object?>{
          'id': 'inc-1',
          'label': 'Salary',
          'accountId': 'acc-1',
          'expectedAmount': 2500000,
          'schedule': <String, Object?>{
            'kind': 'semi_monthly',
            'days': <int>[15, 30],
          },
          'weekendRule': 'before',
          'active': true,
        },
      ],
      'split_upcoming' => <Json>[
        <String, Object?>{
          'incomeId': 'inc-1',
          'label': 'Salary',
          'payday': '2030-04-15',
        },
      ],
      'split_list' =>
        splits ??
            <Json>[
              _plan('sp-open', '2030-04-15', 'proposed'),
              _plan('sp-old', '2030-03-30', 'approved'),
            ],
      'rules_list' => <Json>[_rule('a', 'active'), _rule('b', 'retired')],
      'accounts_balances' => <Json>[
        <String, Object?>{
          'id': 'acc-1',
          'name': 'Bank',
          'currency': 'PHP',
          'balance': 0,
        },
      ],
      'split_delete' => <String, Object?>{'deleted': 1},
      _ => <Object?>[],
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
  tester.view.physicalSize = const Size(360, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTheme(Brightness.light),
        home: const PaydayScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (c: c, calls: calls);
}

void main() {
  group('PaydayScreen', () {
    testWidgets('shows the split being worked on right under its payday', (
      tester,
    ) async {
      await _server(tester);
      // The open split is a card under the coming payday; the older one is listed apart, below
      expect(find.byType(SplitCard), findsNWidgets(2));
      final open = tester.getTopLeft(find.text('Approve split')).dy;
      final earlier = tester.getTopLeft(find.text('Earlier splits')).dy;
      expect(open, lessThan(earlier));
      // A payday that already has its split offers no second "Plan the split"
      expect(find.text('Plan the split'), findsNothing);
      expect(find.text('Plan again'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('offers Plan the split when the payday has no split yet', (
      tester,
    ) async {
      await _server(tester, splits: <Json>[]);
      expect(find.text('Plan the split'), findsOneWidget);
      expect(find.text('No earlier splits yet.'), findsOneWidget);
      expect(find.text('Delete all earlier splits'), findsNothing);
    });

    testWidgets('deletes one earlier split after saying what happens', (
      tester,
    ) async {
      final s = await _server(tester);
      // The menu of the earlier (approved) split is the last one
      await tester.tap(find.byTooltip('More about this split').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete this split'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this split?'), findsOneWidget);
      expect(find.textContaining('stays in your accounts'), findsOneWidget);
      // The balances switch is off to begin with
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Delete it'));
      await tester.pumpAndSettle();
      final call = s.calls.lastWhere((x) => x.verb == 'split_delete');
      expect(call.body['splitId'], 'sp-old');
      expect(call.body.containsKey('removeEntries'), isFalse);
    });

    testWidgets('takes the entries out of the balances only when asked', (
      tester,
    ) async {
      final s = await _server(tester);
      await tester.tap(find.byTooltip('More about this split').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete this split'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.text('This changes your account balances.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete it'));
      await tester.pumpAndSettle();
      final call = s.calls.lastWhere((x) => x.verb == 'split_delete');
      expect(call.body['removeEntries'], isTrue);
    });

    testWidgets('clears all earlier splits with one confirm', (tester) async {
      final s = await _server(tester);
      await tester.tap(find.text('Delete all earlier splits'));
      await tester.pumpAndSettle();
      expect(find.text('Delete all earlier splits?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete them all'));
      await tester.pumpAndSettle();
      final call = s.calls.lastWhere((x) => x.verb == 'split_delete');
      expect(call.body['all'], isTrue);
    });

    testWidgets(
      'a rule can be stopped after a confirm, and a stopped one deleted',
      (tester) async {
        final s = await _server(tester);
        expect(find.text('Stopped'), findsOneWidget);
        await tester.tap(find.byTooltip('More about this rule').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Stop'));
        await tester.pumpAndSettle();
        expect(find.text('Stop this rule?'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Stop it'));
        await tester.pumpAndSettle();
        expect(
          s.calls.lastWhere((x) => x.verb == 'rule_retire').body['ruleId'],
          'a',
        );
        await tester.tap(find.byTooltip('More about this rule').last);
        await tester.pumpAndSettle();
        expect(find.text('Stop'), findsNothing);
        await tester.tap(find.text('Delete the rule'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Delete it'));
        await tester.pumpAndSettle();
        expect(
          s.calls.lastWhere((x) => x.verb == 'rule_delete').body['ruleId'],
          'b',
        );
      },
    );

    testWidgets('a payday opens to be changed or deleted', (tester) async {
      final s = await _server(tester);
      await tester.tap(find.text('Salary').last);
      await tester.pumpAndSettle();
      expect(find.text('Change this payday'), findsOneWidget);
      // The pay and the account are the ones it has, not the defaults
      expect(
        find.byWidgetPredicate(
          (w) => w is EditableText && w.controller.text.contains('25000'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete this payday'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this payday?'), findsOneWidget);
      // It has splits, so the confirm says they go with it
      expect(find.textContaining('has earlier splits'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete it'));
      await tester.pumpAndSettle();
      final call = s.calls.lastWhere((x) => x.verb == 'income_delete');
      expect(call.body['incomeId'], 'inc-1');
      expect(call.body['withSplits'], isTrue);
    });
  });
}
