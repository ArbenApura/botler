// TIME TRAVEL'S DATA: THE ANSWER IS READ WITH ITS SOURCES, EACH ZOOM ASKS FOR ITS OWN WINDOW, A WHAT-IF IS ONE STABLE REQUEST, EDITS WAIT
// FOR A PAUSE, AND ONLY A PLAIN ANSWER IS KEPT FOR OFFLINE.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:botler/core/api.dart';
import 'package:botler/core/json.dart';
import 'package:botler/features/simulate/simulate_data.dart';
import 'package:botler/features/simulate/simulate_parts.dart';
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

  test(
    'reads spent and received of a period, and an older answer without them',
    () {
      final period = <String, Object?>{
        'from': '2026-03-01',
        'to': '2026-03-31',
        'part': 'past',
        'recordedSpent': 85000,
        'recordedReceived': 0,
        'recordedUntracked': 30000,
        'replaySpent': 150000,
        'replayReceived': 2500000,
        'simulatedSpent': null,
        'simulatedReceived': null,
        'leftOut': <String>['EUR'],
      };
      final p = SimPeriod(period);
      expect(p.totalsKnown, isTrue);
      expect(p.recordedSpent, 85000);
      expect(p.recordedReceived, 0);
      expect(p.simulatedSpent, isNull);
      expect(p.leftOut, <String>['EUR']);
      // An older saved answer has no such keys: nothing is read as zero
      final old = SimPeriod(<String, Object?>{
        'from': '2026-03-01',
        'to': '2026-03-31',
        'part': 'past',
      });
      expect(old.totalsKnown, isFalse);
      expect(old.recordedSpent, isNull);
      expect(old.leftOut, isEmpty);
    },
  );

  test('reads the breakdown and the entry fields, and merges both sources for the period of today', () {
    SpendGroup g(String key, int amount, [String label = '']) =>
        SpendGroup(<String, Object?>{
          'key': key,
          'label': label,
          'kind': key.startsWith('bill')
              ? 'bill'
              : key == 'other'
              ? 'other'
              : 'category',
          'amount': amount,
          'count': 1,
        });
    final b = SimBreakdowns(<String, Object?>{
      'recorded': <String, Object?>{
        'groups': <Object?>[
          <String, Object?>{
            'key': 'bill:rent',
            'label': 'Rent',
            'kind': 'bill',
            'amount': 1500000,
            'count': 1,
          },
          <String, Object?>{
            'key': 'cat:food',
            'label': 'Food',
            'kind': 'category',
            'amount': 5000,
            'count': 2,
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
          <String, Object?>{
            'key': 'cat:fun',
            'label': 'Fun',
            'kind': 'category',
            'amount': 20000,
            'count': 1,
          },
        ],
        'more': <String, Object?>{'amount': 700, 'count': 3, 'groups': 2},
      },
    });
    expect(spendGroupsFor(b, SimPart.past).groups.map((x) => x.key), <String>[
      'bill:rent',
      'cat:food',
    ]);
    expect(spendGroupsFor(b, SimPart.future).moreAmount, 700);
    final both = spendGroupsFor(b, SimPart.mixed);
    // The same bill in both sources is one line with both amounts; the biggest first
    expect(both.groups.map((x) => x.key), <String>[
      'bill:rent',
      'cat:fun',
      'cat:food',
    ]);
    expect(both.groups.first.amount, 3000000);
    expect(both.groups.first.count, 2);
    expect(both.moreAmount, 700);
    expect(both.moreGroups, 2);
    final e = SimEntry(<String, Object?>{
      'id': 'r1',
      'source': 'recorded',
      'kind': 'in',
      'currency': 'PHP',
      'amount': 200,
      'groupKey': 'cat:food',
      'refund': true,
    });
    expect(e.id, 'r1');
    expect(e.groupKey, 'cat:food');
    expect(e.refund, isTrue);
    expect(g('other', 1).kind, 'other');
  });

  test('a group with the separator in its name is sent whole, and a page with nothing new ends the list', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final groups = <Object?>[];
    final asked = <int>[];
    final api = ApiClient(
      base: 'https://botler.test',
      token: () async => 'tok',
      client: MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, Object?>;
        groups.add(body['groupKey']);
        final offset = body['offset']! as int;
        asked.add(offset);
        // 90 entries are announced but only 50 exist: the second page is empty
        final rows = offset == 0
            ? <Object?>[
                for (var i = 0; i < 50; i++)
                  <String, Object?>{
                    'id': 'r$i',
                    'source': 'recorded',
                    'kind': 'out',
                    'currency': 'PHP',
                    'amount': 100,
                  },
              ]
            : <Object?>[];
        return http.Response(
          jsonEncode(<String, Object?>{
            'result': <String, Object?>{
              'from': '2026-03-01',
              'to': '2026-03-31',
              'today': '2026-06-10',
              'currency': 'PHP',
              'periods': <Object?>[],
              'entries': rows,
              'entriesTotal': 90,
            },
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );
    final container = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        apiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    final key =
        '2026-03-01|2026-03-31|month|${Uri.encodeComponent('cat:a|b')}|';
    container.listen(simEntriesProvider(key), (_, _) {}, fireImmediately: true);
    await container.read(simEntriesProvider(key).future);
    expect(groups.first, 'cat:a|b');
    final notifier = container.read(simEntriesProvider(key).notifier);
    await notifier.loadMore();
    final end = container.read(simEntriesProvider(key)).value!;
    // The total is corrected to what exists, so nothing asks again
    expect(end.total, 50);
    expect(end.hasMore, isFalse);
    await notifier.loadMore();
    expect(asked, <int>[0, 50]);
  });

  test('pages of entries join up, a repeat is dropped, and a failed page keeps the rows', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    var failAt = -1;
    final asked = <int>[];
    Map<String, Object?> entry(int i) => <String, Object?>{
      'id': 'r$i',
      'source': 'recorded',
      'kind': 'out',
      'currency': 'PHP',
      'amount': 100,
    };
    final api = ApiClient(
      base: 'https://botler.test',
      token: () async => 'tok',
      client: MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, Object?>;
        final offset = body['offset']! as int;
        asked.add(offset);
        if (offset == failAt) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{'code': 'INVALID', 'message': 'No.'},
            }),
            400,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }
        // 120 entries; the second page starts one early, so one row repeats
        final from = offset == 0 ? 0 : offset - 1;
        final rows = <Object?>[
          for (var i = from; i < 120 && i < from + 50; i++) entry(i),
        ];
        return http.Response(
          jsonEncode(<String, Object?>{
            'result': <String, Object?>{
              'from': '2026-03-01',
              'to': '2026-03-31',
              'today': '2026-06-10',
              'currency': 'PHP',
              'periods': <Object?>[],
              'entries': rows,
              'entriesTotal': 120,
            },
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );
    final container = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        apiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    const key = '2026-03-01|2026-03-31|month||';
    container.listen(simEntriesProvider(key), (_, _) {}, fireImmediately: true);
    final first = await container.read(simEntriesProvider(key).future);
    expect(first.rows, hasLength(50));
    expect(first.total, 120);
    final notifier = container.read(simEntriesProvider(key).notifier);
    await notifier.loadMore();
    // The repeated row is dropped
    expect(container.read(simEntriesProvider(key)).value!.rows, hasLength(99));
    failAt = 99;
    await notifier.loadMore();
    final failed = container.read(simEntriesProvider(key)).value!;
    expect(failed.rows, hasLength(99));
    expect(failed.pageError, isNotNull);
    expect(failed.loadingMore, isFalse);
    failAt = -1;
    await notifier.loadMore();
    final done = container.read(simEntriesProvider(key)).value!;
    expect(done.pageError, isNull);
    expect(done.rows.map((r) => r.id).toSet(), hasLength(done.rows.length));
    expect(asked.first, 0);
  });
}
