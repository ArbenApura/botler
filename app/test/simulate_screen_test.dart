// TIME TRAVEL ON SCREEN: THE BANNER SAYS WHICH PART OF TIME IS SHOWN, EVERY NUMBER HAS ITS TAG, THE PERIOD THAT HOLDS TODAY SHOWS BOTH
// NUMBERS, THE JUMPER MOVES, AN OFFLINE COPY SAYS WHEN IT WAS SAVED, A REFUSAL KEEPS THE JUMPER, AND A WHAT-IF IS COUNTED AND RESET.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/features/calendar/calendar_data.dart';
import 'package:botler/features/simulate/simulate_data.dart';
import 'package:botler/features/simulate/simulate_parts.dart';
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

/// Wallets and entries a test can swap in (reset after each test), to show other currencies.
List<Object?>? _walletsOverride;
List<Object?>? _entriesOverride;

/// How many recorded entries the detail holds (a page of them is sent per request), the offsets and groups asked for, whether pages
/// after the first fail, whether the answer is the older one without spent and received, and the currencies left out of the totals.
int? _manyEntries;
final List<int> _offsets = <int>[];
final List<String> _groups = <String>[];
bool _failLater = false;
bool _refuseDetail = false;
bool _oldAnswer = false;
List<String> _leftOut = <String>[];

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
    if (!_oldAnswer) ...<String, Object?>{
      'recordedSpent': part == 'future' ? null : 5000,
      'recordedReceived': part == 'future' ? null : 0,
      'recordedUntracked': part == 'future' ? null : 0,
      'replaySpent': part == 'past' ? 150000 : null,
      'replayReceived': part == 'past' ? 2500000 : null,
      'simulatedSpent': part == 'past' ? null : 150000,
      'simulatedReceived': part == 'past' ? null : 2500000,
      'leftOut': _leftOut,
    },
    'wallets':
        _walletsOverride ??
        <Object?>[
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
  // The entries the detail holds, the way the server limits them to a group and cuts a page
  var all =
      _entriesOverride ??
      (_manyEntries != null
          ? <Object?>[
              for (var i = 0; i < _manyEntries!; i++)
                <String, Object?>{
                  'id': 'r$i',
                  'source': 'recorded',
                  'kind': 'out',
                  'date': from,
                  'label': 'Row $i',
                  'accountName': 'Wallet',
                  'currency': 'PHP',
                  'amount': 100 + i,
                  'groupKey': i.isEven ? 'cat:food' : 'bill:rent',
                },
            ]
          : <Object?>[
              <String, Object?>{
                'id': 'r1',
                'source': 'recorded',
                'kind': 'out',
                'date': from,
                'label': 'Groceries',
                'accountName': 'Wallet',
                'currency': 'PHP',
                'amount': 5000,
                'groupKey': 'cat:food',
              },
              <String, Object?>{
                'id': 's1',
                'source': 'simulated',
                'kind': 'in',
                'date': to,
                'label': 'Salary',
                'accountName': 'Wallet',
                'currency': 'PHP',
                'amount': 2500000,
              },
            ]);
  final group = body['groupKey'];
  if (group is String) {
    all = all
        .where((e) => (e! as Map<String, Object?>)['groupKey'] == group)
        .toList();
  }
  final paged = body.containsKey('limit') || body.containsKey('offset');
  final offset = (body['offset'] as int?) ?? 0;
  final limit = (body['limit'] as int?) ?? 500;
  return <String, Object?>{
    'from': from,
    'to': to,
    'today': _today,
    'currency': 'PHP',
    'firstRecord': '2020-01-01',
    'periods': periods,
    if (detail) ...<String, Object?>{
      'entries': paged ? all.skip(offset).take(limit).toList() : all,
      if (paged) 'entriesTotal': all.length,
      'breakdown': <String, Object?>{
        'recorded': <String, Object?>{
          'groups': <Object?>[
            <String, Object?>{
              'key': 'cat:food',
              'label': 'Food',
              'kind': 'category',
              'amount': 5000,
              'count': 1,
            },
          ],
          'more': null,
        },
        'replay': <String, Object?>{'groups': <Object?>[], 'more': null},
        'simulated': <String, Object?>{
          'groups': <Object?>[
            <String, Object?>{
              'key': 'bill:rent',
              'label': 'Rent',
              'kind': 'bill',
              'amount': 1500000,
              'count': 1,
            },
          ],
          'more': null,
        },
      },
    },
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
  String? initialDate,
  String locale = 'en',
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    simulateIntroKey: true,
    ...saved,
  });
  final prefs = await SharedPreferences.getInstance();
  final api = ApiClient(
    base: 'https://botler.test',
    token: () async => 'tok',
    client: MockClient((req) async {
      if (offline) throw http.ClientException('offline');
      final body = jsonDecode(req.body) as Map<String, Object?>;
      if (req.url.path.endsWith('balance_simulate')) {
        if (body['view'] == 'detail') {
          _offsets.add((body['offset'] as int?) ?? 0);
          _groups.add((body['groupKey'] as String?) ?? '');
        }
        if (refuse ||
            (_refuseDetail && body['view'] == 'detail') ||
            (_failLater && ((body['offset'] as int?) ?? 0) > 0)) {
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
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SimulateScreen(initialDate: initialDate),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Scrolls the page until the text is on screen, then taps it. The entries list is lazy, so the extent of the page grows as rows are
/// built: one scroll may stop short, and it is asked again.
Future<void> _tapOnPage(WidgetTester tester, String text) async {
  final finder = find.text(text).first;
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  for (var i = 0; i < 8; i++) {
    await tester.ensureVisible(finder);
    await tester.pump();
    if (tester.getCenter(finder).dy < height - 20) break;
  }
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

// -- TESTS -- //

Map<String, Object?> _wallet(
  String id,
  String name,
  String currency, {
  int? simulated,
  int? simulatedMain,
}) => <String, Object?>{
  'accountId': id,
  'accountName': name,
  'currency': currency,
  'archived': false,
  'recorded': simulated,
  'replay': null,
  'simulated': simulated,
  'recordedMain': simulatedMain,
  'replayMain': null,
  'simulatedMain': simulatedMain,
};

Future<void> _jump(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Jump further'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  tearDown(() {
    _walletsOverride = null;
    _entriesOverride = null;
    _manyEntries = null;
    _offsets.clear();
    _groups.clear();
    _failLater = false;
    _refuseDetail = false;
    _oldAnswer = false;
    _leftOut = <String>[];
  });

  testWidgets(
    'the month of today shows recorded up to today and simulated after, each tagged',
    (tester) async {
      await _open(tester);
      expect(find.text('Real until today, an estimate after'), findsOneWidget);
      // Spent so far is recorded; what is still to come is an estimate, with a whole-period figure
      expect(find.text('Spent so far'), findsOneWidget);
      expect(find.text('Still to come (estimate)'), findsOneWidget);
      expect(find.textContaining('Whole period (estimate)'), findsOneWidget);
      expect(find.text('Simulated at the end'), findsOneWidget);
      // The balance up to today sits behind Details
      expect(find.text('Recorded up to today'), findsNothing);
      await _tapOnPage(tester, 'Details');
      expect(find.text('Recorded up to today'), findsOneWidget);
      expect(find.text('Recorded'), findsWidgets);
      expect(find.text('Simulated'), findsWidgets);
    },
  );

  testWidgets('a year ahead is simulated, and says it is not real money', (
    tester,
  ) async {
    await _open(tester);
    await _jump(tester, '1 year ahead');
    expect(find.text('Simulated'), findsWidgets);
    expect(find.text('An estimate, not real money'), findsOneWidget);
    expect(find.text('Recorded up to today'), findsNothing);
  });

  testWidgets(
    'a year back is recorded, with the plan replay, the gap and what was missed',
    (tester) async {
      await _open(tester);
      await _jump(tester, '1 year back');
      expect(find.text('What really happened'), findsOneWidget);
      expect(find.text('Recorded at the end'), findsOneWidget);
      expect(find.text('Spent'), findsOneWidget);
      expect(find.textContaining('below the plan'), findsOneWidget);
      expect(find.text('1 payday or bill was not recorded'), findsOneWidget);
      // What the plan expected sits behind Details
      expect(find.text('Your plan expected to spend'), findsNothing);
      await _tapOnPage(tester, 'Details');
      expect(find.text('Your plan expected to spend'), findsOneWidget);
      expect(find.text('Plan replay'), findsWidgets);
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

  testWidgets('the zoom is one control and changes the window', (tester) async {
    final container = await _open(tester);
    expect(find.byType(SegmentedButton<Zoom>), findsOneWidget);
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(container.read(simViewProvider).zoom, Zoom.week);
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
    'a ready-made what-if is counted in its own row, Reset clears it and Undo brings it back',
    (tester) async {
      await _open(tester);
      await tester.tap(find.text('What if'));
      await tester.pumpAndSettle();
      await _tap(tester, 'Pay bills a week late');
      await _tap(tester, 'Done');
      // The row counts what is on screen, once the answer with the what-if is there
      await tester.pump(whatIfDebounce + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(find.text('What-if on: 1 change'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      await _tap(tester, 'Reset');
      expect(find.text('What-if on: 1 change'), findsNothing);
      expect(
        find.text('What-if cleared. Your plan is back as it is.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Undo'));
      await tester.pump(whatIfDebounce + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(find.text('What-if on: 1 change'), findsOneWidget);
    },
  );

  testWidgets(
    'the what-if sheet has tiles that switch on and off and a collapsed part with counts',
    (tester) async {
      await _open(tester);
      await tester.tap(find.text('What if'));
      await tester.pumpAndSettle();
      expect(find.text('Start with one of these'), findsOneWidget);
      expect(
        find.text('Every bill is paid 7 days after its due date.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Pay bills a week late'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      await tester.tap(find.text('Pay bills a week late'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsNothing);
      await tester.tap(find.text('Pay bills a week late'));
      await tester.pumpAndSettle();
      // The by-hand part is collapsed until it is opened, and shows how many changes it holds
      await tester.ensureVisible(find.text('Change something yourself'));
      expect(find.text('1 change'), findsOneWidget);
      expect(find.text('Timing'), findsNothing);
      await tester.tap(find.text('Change something yourself'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Timing'));
      expect(find.text('Timing'), findsOneWidget);
      expect(find.text('Bills paid 7 days late'), findsNothing);
    },
  );

  testWidgets('Undo is dropped by any other edit of the what-if', (
    tester,
  ) async {
    final container = await _open(tester);
    container.read(whatIfProvider.notifier).set(const WhatIf(lateDays: 7));
    await tester.pump(whatIfDebounce + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    await _tap(tester, 'Reset');
    expect(find.text('Undo'), findsOneWidget);
    container.read(whatIfProvider.notifier).set(const WhatIf(defer: true));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('a what-if while offline shows the error and keeps the screen', (
    tester,
  ) async {
    final container = await _open(tester, offline: true);
    container.read(whatIfProvider.notifier).set(const WhatIf(lateDays: 7));
    await tester.pump(whatIfDebounce + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    // A lost connection is asked again a few times before it is shown as lost
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Later'), findsOneWidget);
    expect(find.text('Try again'), findsWidgets);
  });

  testWidgets(
    'an older answer without spent and received draws no card, not zeros',
    (tester) async {
      _oldAnswer = true;
      await _open(tester);
      expect(find.text('Spent so far'), findsNothing);
      expect(find.text('Spent'), findsNothing);
      expect(find.text('Nothing was spent in this period.'), findsNothing);
    },
  );

  testWidgets(
    'a currency with no rate in the period is named and left out of spent',
    (tester) async {
      _leftOut = <String>['JPY'];
      await _open(tester);
      expect(
        find.text('No exchange rate for JPY: left out of the totals.'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'where it went lists the groups with their share, and a tap shows only that group',
    (tester) async {
      await _open(tester);
      await tester.scrollUntilVisible(
        find.text('Where it went'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Where it went'), findsOneWidget);
      expect(
        find.textContaining('Includes what is still to come (estimate)'),
        findsOneWidget,
      );
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Rent'), findsOneWidget);
      // Rent is almost all of it, Food a sliver
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      await _tapOnPage(tester, 'Rent');
      expect(_groups.last, 'bill:rent');
      expect(find.text('Showing Rent'), findsOneWidget);
      await _tapOnPage(tester, 'Show all');
      expect(find.text('Showing Rent'), findsNothing);
    },
  );

  testWidgets(
    'with thousands of entries only a screenful is built, and the next page is asked for at the end',
    (tester) async {
      _manyEntries = 2000;
      await _open(tester);
      expect(_offsets.where((o) => o == 0), isNotEmpty);
      // A first page of 50 is loaded, and the rows built are far fewer than that
      await tester.scrollUntilVisible(
        find.text('Row 0'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(EntryRow).evaluate().length, lessThan(30));
      // Scrolling to the end of what is loaded asks for the following page
      for (var i = 0; i < 40 && !_offsets.contains(50); i++) {
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -2500),
        );
        await tester.pumpAndSettle();
      }
      expect(_offsets, contains(50));
      expect(find.byType(EntryRow).evaluate().length, lessThan(30));
    },
  );

  testWidgets('a page that fails keeps the rows and offers to try again', (
    tester,
  ) async {
    _manyEntries = 200;
    _failLater = true;
    await _open(tester);
    for (
      var i = 0;
      i < 40 && find.text('Could not load more.').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2500));
      await tester.pumpAndSettle();
    }
    expect(find.text('Could not load more.'), findsOneWidget);
    expect(find.byType(EntryRow), findsWidgets);
    _failLater = false;
    await tester.tap(find.text('Try again').last);
    await tester.pumpAndSettle();
    expect(find.text('Could not load more.'), findsNothing);
  });

  testWidgets(
    'a refused first page is shown at once with one request, not retried',
    (tester) async {
      _refuseDetail = true;
      await _open(tester);
      // The unfiltered list also carries the breakdown, so it is one request for both; Riverpod does not ask again
      expect(_offsets, <int>[0]);
      expect(find.text('Try again'), findsWidgets);
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

  testWidgets('the first-open explanation shows once and is remembered', (
    tester,
  ) async {
    final container = await _open(
      tester,
      saved: <String, Object>{simulateIntroKey: false},
    );
    expect(
      find.textContaining('Numbers after today are estimates'),
      findsOneWidget,
    );
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Numbers after today are estimates'),
      findsNothing,
    );
    expect(container.read(prefsProvider).getBool(simulateIntroKey), isTrue);
  });

  testWidgets('the info button explains the screen', (tester) async {
    await _open(tester);
    await tester.tap(find.byTooltip('What am I looking at?'));
    await tester.pumpAndSettle();
    expect(find.text('How Time travel works'), findsOneWidget);
    expect(find.text('The tags'), findsOneWidget);
  });

  testWidgets('opened from the calendar it lands on that day, by month', (
    tester,
  ) async {
    final container = await _open(tester, initialDate: '2027-03-05');
    final view = container.read(simViewProvider);
    expect(view.zoom, Zoom.month);
    expect(dayOf(view.anchor), '2027-03-05');
  });

  testWidgets(
    'other currencies show in their own money with the main-currency figure, and a missing rate is named',
    (tester) async {
      _walletsOverride = <Object?>[
        _wallet(
          'a1',
          'Wallet',
          'PHP',
          simulated: 100000,
          simulatedMain: 100000,
        ),
        _wallet(
          'a2',
          'Dollar jar',
          'USD',
          simulated: 5000,
          simulatedMain: 290000,
        ),
        _wallet('a3', 'Yen box', 'JPY', simulated: 9000),
      ];
      _entriesOverride = <Object?>[
        <String, Object?>{
          'source': 'simulated',
          'kind': 'out',
          'date': _today,
          'label': 'Hosting',
          'accountName': 'Dollar jar',
          'currency': 'USD',
          'amount': 1500,
          'amountMain': 87000,
        },
        <String, Object?>{
          'source': 'simulated',
          'kind': 'out',
          'date': _today,
          'label': 'Ramen',
          'accountName': 'Yen box',
          'currency': 'JPY',
          'amount': 900,
          'amountMain': null,
        },
      ];
      await _open(tester);
      expect(
        find.text('No exchange rate for JPY: left out of the totals.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Ramen'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('about'), findsWidgets);
      expect(find.text('no exchange rate yet'), findsWidgets);
      expect(find.textContaining('USD'), findsWidgets);
    },
  );

  testWidgets(
    'a period whose every wallet lacks a rate has no total, not zero',
    (tester) async {
      _walletsOverride = <Object?>[
        _wallet('a3', 'Yen box', 'JPY', simulated: 9000),
      ];
      await _open(tester);
      expect(find.text('No total'), findsOneWidget);
      // Nothing is drawn from a total that is unknown: no zero shown as recorded money
      expect(find.text('Recorded up to today'), findsNothing);
    },
  );

  testWidgets('the header holds at a narrow width and a large text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _open(tester);
    expect(tester.takeException(), isNull);
    // The four segments stay on one row: a label that does not fit shrinks
    expect(find.byType(SegmentedButton<Zoom>), findsOneWidget);
    final seg = tester.getRect(find.byType(SegmentedButton<Zoom>));
    final year = tester.getRect(find.text('Year'));
    expect(year.top, greaterThanOrEqualTo(seg.top));
    expect(year.bottom, lessThanOrEqualTo(seg.bottom));
  });

  testWidgets('the screen holds in Filipino at a narrow width', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester, locale: 'fil');
    expect(tester.takeException(), isNull);
    // Even in Filipino at this width the four segments are one row
    expect(find.byType(SegmentedButton<Zoom>), findsOneWidget);
    final seg = tester.getRect(find.byType(SegmentedButton<Zoom>));
    expect(
      tester.getRect(find.text('Taon')).bottom,
      lessThanOrEqualTo(seg.bottom),
    );
  });
}
