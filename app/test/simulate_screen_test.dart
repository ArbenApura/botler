// TIME TRAVEL ON SCREEN: THE BAND SAYS WHICH PART OF TIME IS SHOWN, EVERY NUMBER HAS ITS TAG, THE PERIOD THAT HOLDS TODAY SHOWS BOTH
// NUMBERS, THE JUMPER MOVES, AN OFFLINE COPY SAYS WHEN IT WAS SAVED, A REFUSAL KEEPS THE JUMPER, AND A WHAT-IF IS COUNTED AND RESET.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/features/calendar/calendar_data.dart';
import 'package:botler/features/simulate/simulate_data.dart';
import 'package:botler/features/simulate/simulate_screen.dart';
import 'package:botler/l10n/l10n.dart';
import 'package:botler/state/providers.dart';
import 'package:botler/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- FUNCTIONS -- //

final String _today = dayOf(DateTime.now());

/// A period of the answer, its part of time worked out from the real today, as the server would.
Map<String, Object?> _period(String from, String to) {
  final part = to.compareTo(_today) < 0
      ? 'past'
      : from.compareTo(_today) > 0
      ? 'future'
      : 'mixed';
  return <String, Object?>{
    'from': from,
    'to': to,
    'part': part,
    'beforeFirstRecord': false,
    'recordedStart': part == 'future' ? null : 100000,
    'recordedEnd': part == 'future' ? null : 120000,
    'replayEnd': part == 'past' ? 150000 : null,
    'simulatedStart': part == 'past' ? null : 120000,
    'simulatedEnd': part == 'past' ? null : 180000,
    'gap': part == 'past' ? -30000 : null,
    'missed': part == 'past' ? 1 : 0,
    'low': false,
    'below': false,
    'wallets': <Object?>[
      <String, Object?>{
        'accountId': 'a1',
        'accountName': 'Wallet',
        'currency': 'PHP',
        'archived': false,
        'recorded': part == 'future' ? null : 120000,
        'replay': part == 'past' ? 150000 : null,
        'simulated': part == 'past' ? null : 180000,
      },
    ],
  };
}

/// The months of a window, each a period (other groups get one period over the window: enough for the screen).
Map<String, Object?> _answer(Map<String, Object?> body) {
  final from = body['from']! as String;
  final to = body['to']! as String;
  final periods = <Map<String, Object?>>[];
  if (body['group'] == 'month') {
    var d = parseDay(from);
    while (dayOf(d).compareTo(to) <= 0) {
      final end = DateTime(d.year, d.month + 1, 0);
      final e = dayOf(end).compareTo(to) > 0 ? to : dayOf(end);
      periods.add(_period(dayOf(d), e));
      d = DateTime(d.year, d.month + 1);
    }
  } else {
    periods.add(_period(from, to));
  }
  final detail = body['view'] == 'detail';
  return <String, Object?>{
    'from': from,
    'to': to,
    'today': _today,
    'currency': 'PHP',
    'firstRecord': '2020-01-01',
    'periods': periods,
    if (detail)
      'entries': <Object?>[
        <String, Object?>{
          'source': 'recorded',
          'kind': 'out',
          'date': from,
          'label': 'Groceries',
          'accountName': 'Wallet',
          'currency': 'PHP',
          'amount': 5000,
        },
        <String, Object?>{
          'source': 'simulated',
          'kind': 'in',
          'date': to,
          'label': 'Salary',
          'accountName': 'Wallet',
          'currency': 'PHP',
          'amount': 2500000,
        },
      ],
    'warnings': <Object?>[],
    'unknown': <Object?>[],
    'notes': <Object?>[],
    'missing': <Object?>[],
    'rates': <String, Object?>{'stale': false},
  };
}

http.Response _ok(Object? result) => http.Response(
  jsonEncode(<String, Object?>{'result': result}),
  200,
  headers: <String, String>{'content-type': 'application/json'},
);

Future<ProviderContainer> _open(
  WidgetTester tester, {
  bool offline = false,
  bool refuse = false,
  Map<String, Object> saved = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(saved);
  final prefs = await SharedPreferences.getInstance();
  final api = ApiClient(
    base: 'https://botler.test',
    token: () async => 'tok',
    client: MockClient((req) async {
      if (offline) throw http.ClientException('offline');
      final body = jsonDecode(req.body) as Map<String, Object?>;
      if (req.url.path.endsWith('balance_simulate')) {
        if (refuse) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{'code': 'INVALID', 'message': 'No.'},
            }),
            400,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }
        return _ok(_answer(body));
      }
      if (req.url.path.endsWith('split_upcoming')) {
        return _ok(<Object?>[
          <String, Object?>{
            'incomeId': 'i1',
            'label': 'Salary',
            'payday': _today,
          },
        ]);
      }
      return _ok(<Object?>[]);
    }),
  );
  final container = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      apiProvider.overrideWithValue(api),
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
        home: const SimulateScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

// -- TESTS -- //

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  testWidgets(
    'the month of today shows recorded up to today and simulated after, each tagged',
    (tester) async {
      await _open(tester);
      expect(
        find.text('Recorded up to today, simulated after'),
        findsOneWidget,
      );
      expect(find.text('Recorded up to today'), findsOneWidget);
      expect(find.text('Simulated at the end'), findsOneWidget);
      expect(find.text('Recorded'), findsWidgets);
      expect(find.text('Simulated'), findsWidgets);
    },
  );

  testWidgets('a year ahead is simulated, and says it is not real money', (
    tester,
  ) async {
    await _open(tester);
    await _tap(tester, '1 year ahead');
    expect(find.text('Simulated'), findsWidgets);
    expect(
      find.text("Not real money: today's balances and your plan."),
      findsOneWidget,
    );
    expect(find.text('Recorded up to today'), findsNothing);
  });

  testWidgets(
    'a year back is recorded, with the plan replay, the gap and what was missed',
    (tester) async {
      await _open(tester);
      await _tap(tester, '1 year back');
      expect(find.text('Recorded, with a plan replay'), findsOneWidget);
      expect(find.text('Plan replay'), findsWidgets);
      expect(find.textContaining('below the plan'), findsOneWidget);
      expect(find.text('1 payday or bill was not recorded'), findsOneWidget);
    },
  );

  testWidgets('back and forward move the selected period by the zoom unit', (
    tester,
  ) async {
    final container = await _open(tester);
    final before = container.read(simViewProvider).anchor;
    await tester.tap(find.byTooltip('Later'));
    await tester.pumpAndSettle();
    final after = container.read(simViewProvider).anchor;
    expect(
      after.month == before.month + 1 || after.year == before.year + 1,
      isTrue,
    );
    await tester.tap(find.byTooltip('Earlier'));
    await tester.pumpAndSettle();
    expect(container.read(simViewProvider).anchor, before);
  });

  testWidgets('lists the entries of the period with their tags', (
    tester,
  ) async {
    await _open(tester);
    await tester.scrollUntilVisible(
      find.text('Salary'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
  });

  testWidgets(
    'the saved copy says when it was saved when there is no connection',
    (tester) async {
      final n = DateTime.now();
      final key = '${n.year}-01-01|${n.year}-12-31|month|';
      final data = _answer(<String, Object?>{
        'from': '${n.year}-01-01',
        'to': '${n.year}-12-31',
        'group': 'month',
      });
      await _open(
        tester,
        offline: true,
        saved: <String, Object>{
          '${simulateCachePrefix}month': jsonEncode(<String, Object?>{
            'key': key,
            'savedAt': '2026-10-01T08:00:00.000',
            'data': data,
          }),
        },
      );
      expect(find.textContaining('no connection'), findsOneWidget);
      expect(find.text('Simulated at the end'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    },
  );

  testWidgets('a refused range shows the error and keeps the jumper', (
    tester,
  ) async {
    await _open(tester, refuse: true);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byTooltip('Later'), findsOneWidget);
  });

  testWidgets(
    'a ready-made what-if is counted on the band and Reset clears it',
    (tester) async {
      await _open(tester);
      await tester.tap(find.text('What if'));
      await tester.pumpAndSettle();
      await _tap(tester, 'Pay bills a week late');
      await _tap(tester, 'Done');
      // The band counts what is on screen, once the answer with the what-if is there
      await tester.pump(whatIfDebounce + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(find.text('What-if on: 1 change'), findsOneWidget);
      await _tap(tester, 'Reset');
      expect(find.text('What-if on: 1 change'), findsNothing);
    },
  );

  testWidgets(
    'the chart is one target that moves period by period for a screen reader',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _open(tester);
      expect(find.bySemanticsLabel(RegExp('Swipe up or down')), findsNothing);
      // The date button can be pressed by a screen reader
      final date = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Pick a date')),
      );
      expect(date.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      final chart = tester.getSemantics(
        find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.slider ?? false),
        ),
      );
      expect(chart.value, contains('Simulated'));
      handle.dispose();
    },
  );
}
