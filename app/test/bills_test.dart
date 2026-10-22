// THE BILLS SCREEN: DUE DATES GROUPED BY MONTH WITH THE LATE ONES FIRST, A ROW THAT OPENS THE BILL SHEET, PAYING STILL POSSIBLE, AND ONE DATE CHANGED ON ITS OWN.
// The server is a stand-in that answers from a table and remembers every call.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/core/manila.dart';
import 'package:botler/features/money/bills_logic.dart';
import 'package:botler/features/money/bills_screen.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- TYPES -- //

class Call {
  const Call(this.verb, this.args);

  final String verb;
  final Json args;
}

/// Answers the verbs the screen uses and keeps what it was asked.
class Stand {
  Stand({required this.due, required this.bills});

  final List<Json> due;
  final List<Json> bills;
  final List<Call> calls = <Call>[];

  Object? answer(String verb) {
    switch (verb) {
      case 'bills_due':
        return due;
      case 'bills_list':
        return bills;
      case 'accounts_balances':
        return const <Json>[
          <String, Object?>{'id': 'acc-rcbc', 'name': 'RCBC', 'balance': 0},
          <String, Object?>{'id': 'acc-gcash', 'name': 'GCash', 'balance': 0},
        ];
      case 'schedule_preview':
        return <String, Object?>{'windows': <Json>[]};
      default:
        return <String, Object?>{};
    }
  }

  ApiClient api() => ApiClient(
    base: 'https://botler.test',
    token: () async => 'tok',
    client: MockClient((req) async {
      final verb = req.url.path.split('/').last;
      calls.add(Call(verb, decodeJson(req.body)));
      return http.Response(
        jsonEncode(<String, Object?>{'result': answer(verb)}),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    }),
  );
}

// -- FUNCTIONS -- //

Json dueRow(
  String name,
  String date, {
  bool paid = false,
  int amount = 850000,
  bool unknown = false,
  bool moved = false,
}) => <String, Object?>{
  'billId': 'bill-$name',
  'name': name,
  'category': 'bills',
  'accountId': 'acc-rcbc',
  'dueDate': date,
  'originalDueDate': date,
  'overridden': moved,
  'windowStart': date,
  'windowEnd': date,
  'amount': unknown ? null : amount,
  'unknownAmount': unknown,
  'paid': paid,
  'deferrable': false,
};

Json billRow(String name, {String kind = 'fixed'}) => <String, Object?>{
  'id': 'bill-$name',
  'name': name,
  'category': 'bills',
  'accountId': 'acc-rcbc',
  'kind': kind,
  'amount': 850000,
  'schedule': <String, Object?>{'kind': 'monthly', 'day': 25},
  'weekendRule': 'none',
  'deferrable': false,
  'active': true,
  'version': 1,
  'estimate': <String, Object?>{'amount': 850000},
};

Future<void> show(
  WidgetTester tester,
  Stand stand, {
  String locale = 'en',
  double scale = 1,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      apiProvider.overrideWithValue(stand.api()),
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        ),
        home: const BillsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  final today = manilaToday();
  final later = addDaysTo(today, 40);

  group('the groups', () {
    test('put the late bills first and then one group per month in order, leaving an empty month out', () {
      final groups = groupDue(<Json>[
        dueRow('Late', '2026-10-20'),
        dueRow('Dec', '2026-12-10'),
        dueRow('Oct', '2026-10-25'),
        dueRow('Paid long ago', '2026-08-10', paid: true),
        dueRow('Paid this month', '2026-10-05', paid: true),
      ], '2026-10-22');
      expect(groups.map((g) => g.month), <String>['', '2026-10', '2026-12']);
      expect(groups.first.isOverdue, isTrue);
      expect(groups.first.rows.map((r) => r['name']), <Object?>['Late']);
      expect(groups[1].rows.map((r) => r['name']), <Object?>[
        'Paid this month',
        'Oct',
      ]);
      expect(anyUnpaid(groups), isTrue);
      expect(
        anyUnpaid(
          groupDue(<Json>[dueRow('P', '2026-10-30', paid: true)], '2026-10-22'),
        ),
        isFalse,
      );
    });

    test('read a month from the date text, so no time zone can move a day into another month', () {
      final g = groupDue(<Json>[dueRow('Edge', '2026-11-01')], '2026-10-31');
      expect(g.single.month, '2026-11');
    });

    test('leave out late dates from before the month a bill was added', () {
      Json row(String bill, String date, {bool paid = false}) =>
          <String, Object?>{
            'billId': bill,
            'dueDate': date,
            'paid': paid,
            'name': bill,
          };
      final bills = <Json>[
        <String, Object?>{'id': 'new', 'createdAt': '2026-10-22T05:00:00.000Z'},
      ];
      final kept = withoutBeforeAdded(<Json>[
        row('new', '2026-08-05'),
        row('new', '2026-09-05'),
        row('new', '2026-10-05'),
        row('new', '2026-08-25', paid: true),
        row('old', '2026-08-05'),
      ], bills);
      // The month it was added still counts (a bill added late), earlier months do not, a paid one and an unknown bill stay
      expect(kept.map((r) => str(r['dueDate'])), <String>[
        '2026-10-05',
        '2026-08-25',
        '2026-08-05',
      ]);
    });

    test('count Manila days whatever the phone says', () {
      expect(manilaToday(DateTime.utc(2026, 10, 22, 17)), '2026-10-23');
      expect(addDaysTo('2026-12-31', 1), '2027-01-01');
      expect(billsRange('2026-10-22').from, '2026-07-22');
    });
  });

  group('the screen', () {
    testWidgets('shows the late bills first and a header for each month', (
      tester,
    ) async {
      final stand = Stand(
        due: <Json>[
          dueRow('Meralco', addDaysTo(today, -3)),
          dueRow('WiFi', addDaysTo(today, 2)),
          dueRow('Rent', later),
        ],
        bills: <Json>[billRow('Meralco'), billRow('WiFi'), billRow('Rent')],
      );
      await show(tester, stand);
      expect(find.text('Overdue'), findsOneWidget);
      final month = DateFormat.yMMMM('en');
      final headers = <String>{
        month.format(DateTime.parse(addDaysTo(today, 2))),
        month.format(DateTime.parse(later)),
      };
      for (final h in headers) {
        expect(find.text(h), findsWidgets);
      }
      expect(find.text('Meralco'), findsWidgets);
      expect(find.text('Mark paid'), findsNWidgets(3));
    });

    testWidgets(
      'says Paid on a paid row and keeps the nothing-due note when nothing is left to pay',
      (tester) async {
        final stand = Stand(
          due: <Json>[dueRow('Rent', addDaysTo(today, 5), paid: true)],
          bills: <Json>[billRow('Rent')],
        );
        await show(tester, stand);
        expect(
          find.text('Nothing is due in the next 4 months.'),
          findsOneWidget,
        );
        expect(find.text('Paid'), findsOneWidget);
        expect(find.text('Mark paid'), findsNothing);
      },
    );

    testWidgets('a bill with no amount yet can still be paid from its row', (
      tester,
    ) async {
      final stand = Stand(
        due: <Json>[dueRow('Water', addDaysTo(today, 4), unknown: true)],
        bills: <Json>[billRow('Water', kind: 'variable')],
      );
      await show(tester, stand);
      expect(find.text('amount?'), findsOneWidget);
      await tester.tap(find.text('Mark paid'));
      await tester.pumpAndSettle();
      expect(find.text('Water paid'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '1200');
      await tester.tap(find.widgetWithText(FilledButton, 'Mark paid'));
      await tester.pumpAndSettle();
      final call = stand.calls.lastWhere((c) => c.verb == 'bill_mark_paid');
      expect(call.args, <String, Object?>{
        'billId': 'bill-Water',
        'dueDate': addDaysTo(today, 4),
        'amount': 120000,
      });
    });

    testWidgets('a long name at the largest text size does not overflow', (
      tester,
    ) async {
      final stand = Stand(
        due: <Json>[
          dueRow(
            'Quarterly condominium association dues and parking',
            addDaysTo(today, 3),
          ),
        ],
        bills: <Json>[
          billRow('Quarterly condominium association dues and parking'),
        ],
      );
      await show(tester, stand, scale: 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('writes the month in Filipino', (tester) async {
      final stand = Stand(
        due: <Json>[dueRow('Meralco', addDaysTo(today, 2))],
        bills: <Json>[billRow('Meralco')],
      );
      await show(tester, stand, locale: 'fil');
      final label = DateFormat.yMMMM('fil')
          .format(DateTime.parse(addDaysTo(today, 2)));
      expect(find.text(label), findsOneWidget);
      expect(find.text('Markahang bayad na'), findsOneWidget);
    });
  });

  group('changing one date', () {
    final date = addDaysTo(today, 6);

    Future<Stand> open(WidgetTester tester, {bool moved = false}) async {
      final stand = Stand(
        due: <Json>[dueRow('Meralco', date, moved: moved)],
        bills: <Json>[billRow('Meralco')],
      );
      await show(tester, stand);
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      return stand;
    }

    testWidgets(
      'opens the sheet from a tap on the row, with the date, amount and account',
      (tester) async {
        await open(tester);
        expect(find.text('Change the bill'), findsOneWidget);
        expect(find.textContaining('Due date'), findsWidgets);
        expect(find.text('RCBC'), findsOneWidget);
        expect(find.text('8500.00'), findsOneWidget);
      },
    );

    testWidgets(
      'asks just this one or every time when the amount changes, and sends this date only',
      (tester) async {
        final stand = await open(tester);
        await tester.enterText(
          find.widgetWithText(TextField, '8500.00'),
          '7000',
        );
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        expect(find.text('Just this one, or every time?'), findsOneWidget);
        await tester.tap(find.textContaining('Just this one ('));
        await tester.pumpAndSettle();
        final calls = stand.calls
            .where((c) => c.verb.startsWith('bill_'))
            .toList();
        expect(calls.map((c) => c.verb), <String>['bill_occurrence_update']);
        expect(calls.single.args, <String, Object?>{
          'billId': 'bill-Meralco',
          'dueDate': date,
          'amount': 700000,
        });
      },
    );

    testWidgets('changes the whole bill when every time is chosen', (
      tester,
    ) async {
      final stand = await open(tester);
      await tester.enterText(find.widgetWithText(TextField, '8500.00'), '7000');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Every time from now on'));
      await tester.pumpAndSettle();
      final calls = stand.calls
          .where((c) => c.verb.startsWith('bill_'))
          .toList();
      expect(calls.map((c) => c.verb), <String>['bill_update']);
      expect(calls.single.args, <String, Object?>{
        'billId': 'bill-Meralco',
        'amount': 700000,
      });
    });

    testWidgets('nothing is sent when nothing changed', (tester) async {
      final stand = await open(tester);
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(stand.calls.where((c) => c.verb.startsWith('bill_')), isEmpty);
      expect(find.text('Nothing changed.'), findsOneWidget);
    });

    testWidgets('a new name changes the bill without asking', (tester) async {
      final stand = await open(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Meralco'),
        'Meralco home',
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Just this one, or every time?'), findsNothing);
      final calls = stand.calls
          .where((c) => c.verb.startsWith('bill_'))
          .toList();
      expect(calls.map((c) => c.verb), <String>['bill_update']);
      expect(calls.single.args, <String, Object?>{
        'billId': 'bill-Meralco',
        'name': 'Meralco home',
      });
    });

    testWidgets(
      'turning off "varies" saves the amount that was shown, not an empty one',
      (tester) async {
        final stand = Stand(
          due: <Json>[dueRow('Water', date, amount: 120000)],
          bills: <Json>[
            <String, Object?>{
              ...billRow('Water', kind: 'variable'),
              'amount': null,
            },
          ],
        );
        await show(tester, stand);
        await tester.tap(find.byType(InkWell).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('The amount is different every time'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        final calls = stand.calls
            .where((c) => c.verb.startsWith('bill_'))
            .toList();
        expect(calls.map((c) => c.verb), <String>['bill_update']);
        expect(calls.single.args, <String, Object?>{
          'billId': 'bill-Water',
          'kind': 'fixed',
          'amount': 120000,
        });
      },
    );

    testWidgets('skips a date after a confirmation', (tester) async {
      final stand = await open(tester);
      await tester.ensureVisible(find.text('Skip this date'));
      await tester.tap(find.text('Skip this date'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Skip it'));
      await tester.pumpAndSettle();
      final call = stand.calls.lastWhere(
        (c) => c.verb == 'bill_occurrence_update',
      );
      expect(call.args, <String, Object?>{
        'billId': 'bill-Meralco',
        'dueDate': date,
        'skipped': true,
      });
    });

    testWidgets('offers to put a changed date back', (tester) async {
      final stand = await open(tester, moved: true);
      await tester.ensureVisible(find.text('Put back as scheduled'));
      await tester.tap(find.text('Put back as scheduled'));
      await tester.pumpAndSettle();
      final call = stand.calls.lastWhere(
        (c) => c.verb == 'bill_occurrence_reset',
      );
      expect(call.args, <String, Object?>{
        'billId': 'bill-Meralco',
        'dueDate': date,
      });
    });
  });
}
