// TIME TRAVEL'S DATA: THE ANSWER IS READ WITH ITS SOURCES, EACH ZOOM ASKS FOR ITS OWN WINDOW, A WHAT-IF IS ONE STABLE REQUEST, EDITS WAIT
// FOR A PAUSE, AND ONLY A PLAIN ANSWER IS KEPT FOR OFFLINE.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/features/simulate/simulate_data.dart';
import 'package:botler/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -- FUNCTIONS -- //

Map<String, Object?> answer() => <String, Object?>{
  'from': '2026-05-01',
  'to': '2026-07-31',
  'group': 'month',
  'today': '2026-06-10',
  'currency': 'PHP',
  'firstRecord': '2026-01-02',
  'periods': <Object?>[
    <String, Object?>{
      'from': '2026-05-01',
      'to': '2026-05-31',
      'part': 'past',
      'beforeFirstRecord': false,
      'recordedStart': 100,
      'recordedEnd': 200,
      'replayEnd': 250,
      'simulatedStart': null,
      'simulatedEnd': null,
      'gap': -50,
      'missed': 1,
      'low': false,
      'below': false,
      'wallets': <Object?>[
        <String, Object?>{
          'accountId': 'a',
          'accountName': 'RCBC',
          'currency': 'PHP',
          'archived': false,
          'recorded': 200,
          'replay': 250,
          'simulated': null,
        },
      ],
    },
    <String, Object?>{
      'from': '2026-06-01',
      'to': '2026-06-30',
      'part': 'mixed',
      'recordedStart': 200,
      'recordedEnd': 210,
      'replayEnd': null,
      'simulatedStart': 210,
      'simulatedEnd': 300,
      'gap': null,
      'missed': 0,
      'low': true,
      'below': false,
      'wallets': <Object?>[],
    },
    <String, Object?>{
      'from': '2026-07-01',
      'to': '2026-07-31',
      'part': 'future',
      'simulatedStart': 300,
      'simulatedEnd': 400,
      'missed': 0,
      'wallets': <Object?>[],
    },
  ],
  'entries': <Object?>[
    <String, Object?>{
      'source': 'recorded',
      'kind': 'out',
      'date': '2026-05-03',
      'label': 'Groceries',
      'accountName': 'RCBC',
      'currency': 'PHP',
      'amount': 5000,
    },
    <String, Object?>{
      'source': 'missed',
      'kind': 'in',
      'date': '2026-05-15',
      'label': 'Salary',
      'accountName': 'RCBC',
      'currency': 'PHP',
      'amount': null,
    },
    <String, Object?>{
      'source': 'simulated',
      'kind': 'out',
      'date': '2026-07-02',
      'label': 'Phone',
      'accountName': 'RCBC',
      'currency': 'PHP',
      'amount': 7000,
      'pretend': true,
    },
  ],
  'warnings': <Object?>[
    <String, Object?>{
      'source': 'simulated',
      'kind': 'below_zero',
      'date': '2026-07-02',
      'accountName': 'RCBC',
      'currency': 'PHP',
      'balance': -1,
    },
  ],
  'unknown': <Object?>[
    <String, Object?>{
      'kind': 'bill',
      'label': 'Gas',
      'count': 3,
      'first': '2026-06-12',
    },
  ],
  'notes': <Object?>['Only recorded numbers are real.'],
  'missing': <Object?>['EUR'],
  'rates': <String, Object?>{'asOf': null, 'stale': true},
};

ApiClient api(Future<http.Response> Function(http.Request req) handler) =>
    ApiClient(
      base: 'https://botler.test',
      token: () async => 'tok',
      client: MockClient(handler),
    );

http.Response ok(Object? result) => http.Response(
  jsonEncode(<String, Object?>{'result': result}),
  200,
  headers: <String, String>{'content-type': 'application/json'},
);

// -- TESTS -- //

void main() {
  test('reads the answer with a source on every number', () {
    final s = SimResult(answer());
    expect(s.periods.map((p) => p.part), <SimPart>[
      SimPart.past,
      SimPart.mixed,
      SimPart.future,
    ]);
    expect(s.periods.first.headline, (amount: 200, source: SimSource.recorded));
    expect(s.periods[1].headline, (amount: 300, source: SimSource.simulated));
    expect(s.periods.first.gap, -50);
    expect(s.periods.first.wallets.single.replay, 250);
    expect(s.periods.first.wallets.single.simulated, isNull);
    expect(s.entries.map((e) => e.source), <SimSource>[
      SimSource.recorded,
      SimSource.missed,
      SimSource.simulated,
    ]);
    expect(s.entries[1].amount, isNull);
    expect(s.entries[2].pretend, isTrue);
    expect(s.warnings.single.belowZero, isTrue);
    expect(s.unknown.single.count, 3);
    expect(s.missing, <String>['EUR']);
    expect(s.ratesStale, isTrue);
    expect(s.periodOf('2026-06-20')?.part, SimPart.mixed);
    expect(s.periodOf('2030-01-01')?.part, SimPart.future);
  });

  test('each zoom asks for its own window, inside 5 years of today', () {
    final today = DateTime(2026, 6, 10);
    final a = DateTime(2026, 6, 10);
    final day = windowFor(Zoom.day, a, 1, today);
    expect((day.from, day.to, day.group), ('2026-06-01', '2026-06-30', 'day'));
    final week = windowFor(Zoom.week, a, 1, today);
    expect(week.group, 'week');
    expect(
      DateTime.parse(week.to).difference(DateTime.parse(week.from)).inDays + 1,
      91,
    );
    final month = windowFor(Zoom.month, a, 1, today);
    expect((month.from, month.to), ('2026-01-01', '2026-12-31'));
    final year = windowFor(Zoom.year, a, 1, today);
    expect(year.group, 'year');
    expect(
      DateTime.parse(year.to).difference(DateTime.parse(year.from)).inDays + 1,
      lessThanOrEqualTo(reachDays),
    );
    // Near the edge of the reach the window is cut, never past it
    final far = windowFor(Zoom.month, DateTime(2031, 6, 1), 1, today);
    expect(DateTime.parse(far.to).isAfter(latestDay(today)), isFalse);
    expect(clampDay(DateTime(2040), today), latestDay(today));
  });

  test('picking another period inside a window keeps the same window', () {
    final today = DateTime(2026, 6, 10);
    String key(Zoom z, DateTime d) =>
        windowFor(z, d, 1, today).key(const WhatIf());
    // Year: 2025 to 2029 is one block, so every year in it asks for the same answer
    expect(
      key(Zoom.year, DateTime(2026, 6, 10)),
      key(Zoom.year, DateTime(2028, 3, 1)),
    );
    expect(
      key(Zoom.year, DateTime(2026, 6, 10)),
      isNot(key(Zoom.year, DateTime(2030, 1, 1))),
    );
    // Week: each week of a block of 13 asks for the same answer, and the block holds the week
    final w = windowFor(Zoom.week, DateTime(2026, 6, 10), 1, today);
    var same = 0;
    for (
      var d = DateTime.parse(w.from);
      !d.isAfter(DateTime.parse(w.to));
      d = d.add(const Duration(days: 7))
    ) {
      if (key(Zoom.week, d) == w.key(const WhatIf())) same++;
    }
    expect(same, 13);
    expect(
      w.from.compareTo('2026-06-10') <= 0 && w.to.compareTo('2026-06-10') >= 0,
      isTrue,
    );
    // Month and day are the calendar year and month
    expect(
      key(Zoom.month, DateTime(2026, 2, 1)),
      key(Zoom.month, DateTime(2026, 11, 30)),
    );
  });

  test('steps and jumps keep the day of the month when they can', () {
    expect(
      stepAnchor(Zoom.month, DateTime(2026, 1, 31), 1),
      DateTime(2026, 2, 28),
    );
    expect(
      stepAnchor(Zoom.week, DateTime(2026, 1, 31), -1),
      DateTime(2026, 1, 24),
    );
    expect(
      stepAnchor(Zoom.year, DateTime(2028, 2, 29), 1),
      DateTime(2029, 2, 28),
    );
    expect(jumpMonths(DateTime(2026, 6, 10), -12), DateTime(2025, 6, 10));
  });

  test('a what-if is one stable request and counts its changes', () {
    const empty = WhatIf();
    expect(empty.isEmpty, isTrue);
    expect(empty.toJson(), isEmpty);
    final w = const WhatIf().copyWith(
      off: <String>{'b', 'a'},
      amounts: <String, int>{'z': 5, 'y': 6},
      lateDays: 7,
      defer: true,
      skipDates: <String>{'2026-06-15'},
    );
    expect(w.changes, 7);
    expect(jsonEncode(w.toJson()), jsonEncode(w.copyWith().toJson()));
    expect(w.toJson()['off'], <String>['a', 'b']);
    const window = SimWindow('2026-01-01', '2026-12-31', 'month');
    expect(window.key(empty), '2026-01-01|2026-12-31|month|');
    expect(window.key(w), startsWith('2026-01-01|2026-12-31|month|{'));
  });

  test('a what-if is asked for only after a pause', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sub = container.listen(appliedWhatIfProvider, (_, _) {});
    container.read(whatIfProvider.notifier).setLateDays(3);
    container.read(whatIfProvider.notifier).setLateDays(5);
    expect(sub.read().isEmpty, isTrue);
    await Future<void>.delayed(
      whatIfDebounce + const Duration(milliseconds: 50),
    );
    expect(sub.read().lateDays, 5);
    container.read(whatIfProvider.notifier).reset();
    expect(sub.read().isEmpty, isTrue);
  });

  test('keeps a plain answer for offline, never a what-if', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    var online = true;
    final bodies = <Map<String, Object?>>[];
    final container = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        apiProvider.overrideWithValue(
          api((req) async {
            if (!online) throw http.ClientException('offline');
            bodies.add(jsonDecode(req.body) as Map<String, Object?>);
            return ok(answer());
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    const key = '2026-01-01|2026-12-31|month|';
    final first = await container.read(
      simOverviewProvider('$key#month').future,
    );
    expect(first.offline, isFalse);
    expect(bodies.single['view'], 'overview');
    expect(bodies.single.containsKey('scenario'), isFalse);
    expect(prefs.getString('${simulateCachePrefix}month'), isNotNull);

    final w = const WhatIf().copyWith(lateDays: 3);
    final withWhatIf = const SimWindow(
      '2026-01-01',
      '2026-12-31',
      'month',
    ).key(w);
    await container.read(simOverviewProvider('$withWhatIf#month').future);
    expect(bodies.last['scenario'], <String, Object?>{'lateDays': 3});
    // The saved copy is still the plain one
    expect(
      decodeJson(prefs.getString('${simulateCachePrefix}month') ?? '')['key'],
      key,
    );

    online = false;
    container.invalidate(simOverviewProvider('$key#month'));
    final offline = await container.read(
      simOverviewProvider('$key#month').future,
    );
    expect(offline.offline, isTrue);
    expect(offline.sim.periods, hasLength(3));
    // One saved answer per zoom, and the note that the intro was seen (a data reset clears them all)
    expect(simulateCacheKeys, hasLength(5));
    expect(simulateCacheKeys, contains(simulateIntroKey));
  });

  test('reads the main-currency figures of a wallet and an entry, and old answers without them', () {
    final w = SimWallet(<String, Object?>{
      'accountId': 'a2',
      'accountName': 'Dollar jar',
      'currency': 'USD',
      'recorded': 5000,
      'simulated': 5000,
      'recordedMain': null,
      'simulatedMain': 290000,
    });
    expect(w.mainKnown, isTrue);
    expect(w.mainFor(past: false), 290000);
    expect(w.noRate(past: false), isFalse);
    // A balance with no main figure is a currency with no rate
    expect(w.noRate(past: true), isTrue);
    final old = SimWallet(<String, Object?>{
      'accountId': 'a1',
      'accountName': 'Wallet',
      'currency': 'PHP',
      'simulated': 100,
    });
    expect(old.mainKnown, isFalse);
    expect(old.noRate(past: false), isFalse);
    final e = SimEntry(<String, Object?>{
      'source': 'simulated',
      'kind': 'out',
      'currency': 'USD',
      'amount': 1500,
      'amountMain': 87000,
    });
    expect(e.amountMain, 87000);
  });
}
