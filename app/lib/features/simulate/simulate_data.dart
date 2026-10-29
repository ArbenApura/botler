// TIME TRAVEL'S DATA: THE BALANCE TIMELINE FROM THE SERVER'S balance_simulate VERB (BTL-20261029-0117).
// The server does every sum: what was recorded, the replay of the plan in the past, the simulation of the future and what-ifs. The phone
// only asks for a window of dates, reads the answer and keeps the last plain one (no what-if) so it shows offline, marked with its date.
// Every number keeps its source (recorded, replay, simulated, missed) so the screen can never show a simulated number as real.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/json.dart';
import '../../state/providers.dart';
import '../calendar/calendar_data.dart';

// -- TYPES -- //

enum Zoom { day, week, month, year }

enum SimSource { recorded, replay, simulated, missed }

enum SimPart { past, mixed, future }

SimSource _source(Object? v) => switch (str(v)) {
  'recorded' => SimSource.recorded,
  'replay' => SimSource.replay,
  'missed' => SimSource.missed,
  _ => SimSource.simulated,
};

SimPart _part(Object? v) => switch (str(v)) {
  'past' => SimPart.past,
  'mixed' => SimPart.mixed,
  _ => SimPart.future,
};

int? _intOrNull(Object? v) => v is num ? v.toInt() : null;

/// One wallet at the end of a period, by source. A null is a source that has nothing for it (not open yet, or not that part of time).
class SimWallet {
  SimWallet(Json j)
    : accountId = str(j['accountId']),
      accountName = str(j['accountName']),
      currency = str(j['currency']),
      archived = boolOf(j['archived']),
      recorded = _intOrNull(j['recorded']),
      replay = _intOrNull(j['replay']),
      simulated = _intOrNull(j['simulated']),
      recordedMain = _intOrNull(j['recordedMain']),
      replayMain = _intOrNull(j['replayMain']),
      simulatedMain = _intOrNull(j['simulatedMain']),
      mainKnown =
          j.containsKey('recordedMain') || j.containsKey('simulatedMain');

  final String accountId;
  final String accountName;
  final String currency;
  final bool archived;
  final int? recorded;
  final int? replay;
  final int? simulated;

  /// The same balances in the main currency at the stored rates, worked out by the server. A null with a balance beside it is a
  /// currency with no rate.
  final int? recordedMain;
  final int? replayMain;
  final int? simulatedMain;

  /// False for an older saved answer that has no main-currency figures at all (nothing can be said about rates then).
  final bool mainKnown;

  /// The balance for the past or for after today, and its main-currency twin.
  int? amountFor({required bool past}) => past ? recorded : simulated;
  int? mainFor({required bool past}) => past ? recordedMain : simulatedMain;

  /// A balance exists but could not be converted: its currency has no rate.
  bool noRate({required bool past}) =>
      mainKnown && amountFor(past: past) != null && mainFor(past: past) == null;
}

/// One period: its dates, which part of time it is, and its totals in the main currency by source.
class SimPeriod {
  SimPeriod(Json j)
    : from = str(j['from']),
      to = str(j['to']),
      part = _part(j['part']),
      beforeFirstRecord = boolOf(j['beforeFirstRecord']),
      recordedStart = _intOrNull(j['recordedStart']),
      recordedEnd = _intOrNull(j['recordedEnd']),
      replayEnd = _intOrNull(j['replayEnd']),
      simulatedStart = _intOrNull(j['simulatedStart']),
      simulatedEnd = _intOrNull(j['simulatedEnd']),
      gap = _intOrNull(j['gap']),
      missed = intOf(j['missed']),
      low = boolOf(j['low']),
      below = boolOf(j['below']),
      wallets = <SimWallet>[
        for (final w in asJsonList(j['wallets'])) SimWallet(w),
      ];

  final String from;
  final String to;
  final SimPart part;
  final bool beforeFirstRecord;
  final int? recordedStart;
  final int? recordedEnd;
  final int? replayEnd;
  final int? simulatedStart;
  final int? simulatedEnd;
  final int? gap;
  final int missed;
  final bool low;
  final bool below;
  final List<SimWallet> wallets;

  bool holds(String day) => day.compareTo(from) >= 0 && day.compareTo(to) <= 0;

  /// The number the chart draws for the period's end, with its source: recorded in the past, simulated after today.
  ({int? amount, SimSource source}) get headline => switch (part) {
    SimPart.past => (amount: recordedEnd, source: SimSource.recorded),
    _ => (amount: simulatedEnd, source: SimSource.simulated),
  };
}

/// One entry of the detail view: real, replayed, simulated or missed.
class SimEntry {
  SimEntry(Json j)
    : source = _source(j['source']),
      kind = str(j['kind']),
      date = str(j['date']),
      label = str(j['label']),
      accountName = str(j['accountName']),
      toAccountName = str(j['toAccountName']),
      currency = str(j['currency']),
      amount = _intOrNull(j['amount']),
      amountMain = _intOrNull(j['amountMain']),
      pretend = boolOf(j['pretend']);

  final SimSource source;

  /// in, out or move.
  final String kind;
  final String date;
  final String label;
  final String accountName;
  final String toAccountName;
  final String currency;
  final int? amount;

  /// The amount in the main currency at the stored rates; null for a currency with no rate (or no amount).
  final int? amountMain;

  /// A one-off entry of a what-if.
  final bool pretend;
}

class SimWarning {
  SimWarning(Json j)
    : source = _source(j['source']),
      belowZero = str(j['kind']) == 'below_zero',
      date = str(j['date']),
      accountName = str(j['accountName']),
      currency = str(j['currency']),
      balance = intOf(j['balance']);

  final SimSource source;
  final bool belowZero;
  final String date;
  final String accountName;
  final String currency;
  final int balance;
}

class SimUnknown {
  SimUnknown(Json j)
    : label = str(j['label']),
      count = intOf(j['count']),
      first = str(j['first']);

  final String label;
  final int count;
  final String first;
}

/// The server's answer.
class SimResult {
  SimResult(Json j)
    : from = str(j['from']),
      to = str(j['to']),
      today = str(j['today']),
      currency = str(j['currency'], 'PHP'),
      firstRecord = j['firstRecord'] is String ? str(j['firstRecord']) : null,
      periods = <SimPeriod>[
        for (final p in asJsonList(j['periods'])) SimPeriod(p),
      ],
      entries = <SimEntry>[
        for (final e in asJsonList(j['entries'])) SimEntry(e),
      ],
      entriesOmitted = intOf(j['entriesOmitted']),
      warnings = <SimWarning>[
        for (final w in asJsonList(j['warnings'])) SimWarning(w),
      ],
      unknown = <SimUnknown>[
        for (final u in asJsonList(j['unknown'])) SimUnknown(u),
      ],
      notes = <String>[for (final n in asList(j['notes'])) str(n)],
      missing = <String>[for (final m in asList(j['missing'])) str(m)],
      ratesStale = boolOf(asJson(j['rates'])['stale']);

  final String from;
  final String to;
  final String today;
  final String currency;
  final String? firstRecord;
  final List<SimPeriod> periods;
  final List<SimEntry> entries;
  final int entriesOmitted;
  final List<SimWarning> warnings;
  final List<SimUnknown> unknown;
  final List<String> notes;
  final List<String> missing;
  final bool ratesStale;

  /// The period that holds a day, or the nearest one.
  SimPeriod? periodOf(String day) {
    if (periods.isEmpty) return null;
    for (final p in periods) {
      if (p.holds(day)) return p;
    }
    return day.compareTo(periods.first.from) < 0 ? periods.first : periods.last;
  }
}

/// A loaded answer, and when it was saved if it came from the phone's own copy because the server could not be reached.
class SimLoad {
  SimLoad(this.sim, {this.savedAt});

  final SimResult sim;
  final DateTime? savedAt;

  bool get offline => savedAt != null;
}

/// A pretend entry of a what-if, in the main currency.
class PretendEntry {
  const PretendEntry({
    required this.date,
    required this.income,
    required this.accountId,
    required this.amount,
    required this.label,
  });

  final String date;
  final bool income;
  final String accountId;
  final int amount;
  final String label;

  Json toJson() => <String, Object?>{
    'date': date,
    'kind': income ? 'in' : 'out',
    'accountId': accountId,
    'amount': amount,
    'label': label,
  };
}

/// A what-if: changes to the plan that are never saved. It only changes the replay and the simulation.
class WhatIf {
  const WhatIf({
    this.off = const <String>{},
    this.amounts = const <String, int>{},
    this.skipDates = const <String>{},
    this.lateDays = 0,
    this.defer = false,
    this.extra = const <PretendEntry>[],
  });

  /// Ids of paydays, bills, rules and goals switched off.
  final Set<String> off;

  /// Another amount for a payday or a bill, by id, in minor units.
  final Map<String, int> amounts;

  /// Dates whose paydays do not come.
  final Set<String> skipDates;
  final int lateDays;
  final bool defer;
  final List<PretendEntry> extra;

  /// How many changes the band counts.
  int get changes =>
      off.length +
      amounts.length +
      skipDates.length +
      (lateDays > 0 ? 1 : 0) +
      (defer ? 1 : 0) +
      extra.length;

  bool get isEmpty => changes == 0;

  WhatIf copyWith({
    Set<String>? off,
    Map<String, int>? amounts,
    Set<String>? skipDates,
    int? lateDays,
    bool? defer,
    List<PretendEntry>? extra,
  }) => WhatIf(
    off: off ?? this.off,
    amounts: amounts ?? this.amounts,
    skipDates: skipDates ?? this.skipDates,
    lateDays: lateDays ?? this.lateDays,
    defer: defer ?? this.defer,
    extra: extra ?? this.extra,
  );

  /// The scenario the server reads, with sorted lists so the same what-if always gives the same request.
  Json toJson() => <String, Object?>{
    if (off.isNotEmpty) 'off': (off.toList()..sort()),
    if (amounts.isNotEmpty)
      'amounts': <Json>[
        for (final id in (amounts.keys.toList()..sort()))
          <String, Object?>{'id': id, 'amount': amounts[id]},
      ],
    if (skipDates.isNotEmpty) 'skipDates': (skipDates.toList()..sort()),
    if (lateDays > 0) 'lateDays': lateDays,
    if (defer) 'defer': true,
    if (extra.isNotEmpty) 'extra': <Json>[for (final e in extra) e.toJson()],
  };
}

/// What the screen shows: the zoom, the day it is anchored on (the selected period holds it).
class SimView {
  const SimView({required this.zoom, required this.anchor});

  final Zoom zoom;
  final DateTime anchor;
}

/// The dates one zoom asks the server for, and the grouping.
class SimWindow {
  const SimWindow(this.from, this.to, this.group);

  final String from;
  final String to;
  final String group;

  /// The provider key: the window and the what-if.
  String key(WhatIf w) =>
      '$from|$to|$group|${w.isEmpty ? '' : jsonEncode(w.toJson())}';
}

// -- CONSTANTS -- //

/// How far a jump may reach from today, in days: 5 years each way, as the server allows.
const int reachDays = 1827;

/// The phone's saved copy of the last plain answer per zoom. Cleared by a data reset.
const String simulateCachePrefix = 'simulate.overview.v1.';

/// Set once the person has seen the short explanation of Time travel. A data reset clears it with the saved answers.
const String simulateIntroKey = 'simulate.intro.seen';
List<String> get simulateCacheKeys => <String>[
  for (final z in Zoom.values) '$simulateCachePrefix${z.name}',
  simulateIntroKey,
];

const Duration whatIfDebounce = Duration(milliseconds: 400);

// -- FUNCTIONS -- //

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// The earliest and latest day a jump may reach.
DateTime earliestDay(DateTime today) =>
    _dayOnly(today).subtract(const Duration(days: reachDays - 1));
DateTime latestDay(DateTime today) =>
    _dayOnly(today).add(const Duration(days: reachDays - 1));

DateTime clampDay(DateTime d, DateTime today) {
  final day = _dayOnly(d);
  if (day.isBefore(earliestDay(today))) return earliestDay(today);
  if (day.isAfter(latestDay(today))) return latestDay(today);
  return day;
}

/// Day: the anchor's month by day. Week: the block of 13 weeks that holds it, by week. Month: its year by month. Year: the block of 5
/// years that holds it, by year (the server allows 1827 days in one answer). Blocks are fixed on the calendar, so picking another period
/// inside the window never moves the window (a tap on the chart never refetches or slides it). Every window stays inside the reach of 5
/// years each way.
SimWindow windowFor(
  Zoom zoom,
  DateTime anchor,
  int weekStartsOn,
  DateTime today,
) {
  final a = _dayOnly(anchor);
  late DateTime from;
  late DateTime to;
  late String group;
  switch (zoom) {
    case Zoom.day:
      from = DateTime(a.year, a.month);
      to = DateTime(a.year, a.month + 1, 0);
      group = 'day';
    case Zoom.week:
      // Blocks of 13 weeks counted from a fixed week start, so every week of a block asks for the same window
      final epoch = weekStart(DateTime(2000, 1, 3), weekStartsOn);
      final weeks = weekStart(a, weekStartsOn).difference(epoch).inDays ~/ 7;
      final block = weeks >= 0 ? weeks ~/ 13 : -((-weeks + 12) ~/ 13);
      from = DateTime(epoch.year, epoch.month, epoch.day + block * 91);
      to = DateTime(from.year, from.month, from.day + 90);
      group = 'week';
    case Zoom.month:
      from = DateTime(a.year);
      to = DateTime(a.year, 12, 31);
      group = 'month';
    case Zoom.year:
      // Blocks of 5 years: 2025 to 2029, 2030 to 2034
      from = DateTime(a.year - a.year % 5);
      to = DateTime(from.year + 4, 12, 31);
      group = 'year';
  }
  final lo = earliestDay(today);
  final hi = latestDay(today);
  if (from.isBefore(lo)) from = lo;
  if (to.isAfter(hi)) to = hi;
  // A year window of 5 whole years can pass 1827 days with two leap days: trim the far end
  while (to.difference(from).inDays + 1 > reachDays) {
    to = to.subtract(const Duration(days: 1));
  }
  return SimWindow(dayOf(from), dayOf(to), group);
}

/// The anchor moved by one zoom unit, forward or back.
DateTime stepAnchor(Zoom zoom, DateTime anchor, int by) => switch (zoom) {
  Zoom.day => DateTime(anchor.year, anchor.month, anchor.day + by),
  Zoom.week => DateTime(anchor.year, anchor.month, anchor.day + 7 * by),
  Zoom.month => _addMonths(anchor, by),
  Zoom.year => _addMonths(anchor, 12 * by),
};

DateTime _addMonths(DateTime d, int months) {
  final first = DateTime(d.year, d.month + months);
  final last = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, d.day > last ? last : d.day);
}

/// A quick jump by months (a negative number goes back).
DateTime jumpMonths(DateTime anchor, int months) => _addMonths(anchor, months);

// -- STATES -- //

class SimViewNotifier extends Notifier<SimView> {
  @override
  SimView build() =>
      SimView(zoom: Zoom.month, anchor: _dayOnly(DateTime.now()));

  DateTime get _today => _dayOnly(DateTime.now());

  void setZoom(Zoom zoom) => state = SimView(zoom: zoom, anchor: state.anchor);

  void go(DateTime day) =>
      state = SimView(zoom: state.zoom, anchor: clampDay(day, _today));

  void step(int by) => go(stepAnchor(state.zoom, state.anchor, by));

  void jump(int months) => go(jumpMonths(state.anchor, months));

  void today() => go(_today);
}

final NotifierProvider<SimViewNotifier, SimView> simViewProvider =
    NotifierProvider.autoDispose<SimViewNotifier, SimView>(SimViewNotifier.new);

/// Whether the short explanation was already seen, kept on the phone.
class SimIntroNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(prefsProvider).getBool(simulateIntroKey) ?? false;

  Future<void> markSeen() async {
    state = true;
    try {
      await ref.read(prefsProvider).setBool(simulateIntroKey, true);
    } on Object {
      // Not being able to remember it only shows the note once more
    }
  }
}

final NotifierProvider<SimIntroNotifier, bool> simIntroSeenProvider =
    NotifierProvider.autoDispose<SimIntroNotifier, bool>(SimIntroNotifier.new);

/// The what-if as the person edits it. Never saved anywhere.
class WhatIfNotifier extends Notifier<WhatIf> {
  @override
  WhatIf build() => const WhatIf();

  void set(WhatIf next) => state = next;

  void reset() => state = const WhatIf();

  void toggleOff(String id) {
    final next = <String>{...state.off};
    if (!next.remove(id)) next.add(id);
    state = state.copyWith(off: next);
  }

  void setAmount(String id, int? amount) {
    final next = <String, int>{...state.amounts};
    if (amount == null) {
      next.remove(id);
    } else {
      next[id] = amount;
    }
    state = state.copyWith(amounts: next);
  }

  void toggleSkip(String date) {
    final next = <String>{...state.skipDates};
    if (!next.remove(date)) next.add(date);
    state = state.copyWith(skipDates: next);
  }

  void setLateDays(int days) => state = state.copyWith(lateDays: days);

  void setDefer(bool on) => state = state.copyWith(defer: on);

  void addEntry(PretendEntry e) =>
      state = state.copyWith(extra: <PretendEntry>[...state.extra, e]);

  void removeEntry(int index) => state = state.copyWith(
    extra: <PretendEntry>[
      for (var i = 0; i < state.extra.length; i++)
        if (i != index) state.extra[i],
    ],
  );
}

final NotifierProvider<WhatIfNotifier, WhatIf> whatIfProvider =
    NotifierProvider.autoDispose<WhatIfNotifier, WhatIf>(WhatIfNotifier.new);

/// The what-if the answers are asked with: it follows the edited one after a short pause, so typing an amount sends one request.
class AppliedWhatIfNotifier extends Notifier<WhatIf> {
  Timer? _timer;

  @override
  WhatIf build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen<WhatIf>(whatIfProvider, (_, next) {
      _timer?.cancel();
      // Clearing it is shown at once; edits wait for the pause
      if (next.isEmpty) {
        state = next;
        return;
      }
      _timer = Timer(whatIfDebounce, () => state = next);
    });
    return ref.read(whatIfProvider);
  }
}

final NotifierProvider<AppliedWhatIfNotifier, WhatIf> appliedWhatIfProvider =
    NotifierProvider.autoDispose<AppliedWhatIfNotifier, WhatIf>(
      AppliedWhatIfNotifier.new,
    );

/// Asks the server. A plain overview (no what-if) is kept per zoom, so it shows offline with the date it was saved.
Future<SimLoad> _load(
  Ref ref,
  String key, {
  required bool detail,
  String? cacheKey,
}) async {
  final prefs = ref.watch(prefsProvider);
  final parts = key.split('|');
  final scenario = parts.length > 3 && parts[3].isNotEmpty
      ? asJson(jsonDecode(parts.sublist(3).join('|')))
      : null;
  try {
    final answer = asJson(
      await ref.watch(apiProvider).verb('balance_simulate', <String, Object?>{
        'from': parts[0],
        'to': parts[1],
        'group': parts[2],
        'view': detail ? 'detail' : 'overview',
        'scenario': ?scenario,
      }),
    );
    if (cacheKey != null && scenario == null) {
      try {
        await prefs.setString(
          cacheKey,
          jsonEncode(<String, Object?>{
            'key': key,
            'savedAt': DateTime.now().toIso8601String(),
            'data': answer,
          }),
        );
      } on Object {
        // A full disk must not throw away an answer that just arrived
      }
    }
    return SimLoad(SimResult(answer));
  } on ApiException catch (e) {
    // Only a missing connection falls back to the copy, and only for the same window with no what-if
    if (e.code != 'NETWORK' || cacheKey == null || scenario != null) rethrow;
    final saved = decodeJson(prefs.getString(cacheKey) ?? '');
    if (str(saved['key']) != key) rethrow;
    return SimLoad(
      SimResult(asJson(saved['data'])),
      savedAt: dateOf(saved['savedAt']) ?? DateTime.now(),
    );
  }
}

/// A refusal (a range too long, a what-if out of bounds) is shown at once and never asked again; only a lost connection is retried, a few times.
Duration? simRetry(int count, Object error) {
  if (error is ApiException && error.code != 'NETWORK') return null;
  if (count >= 3) return null;
  return Duration(milliseconds: 400 * (1 << count));
}

/// The overview of a window: "from|to|group|scenario json", with the zoom name after a last "#" for the offline copy.
final simOverviewProvider = FutureProvider.autoDispose.family<SimLoad, String>(
  retry: simRetry,
  (ref, keyAndZoom) {
    final at = keyAndZoom.lastIndexOf('#');
    final key = keyAndZoom.substring(0, at);
    final zoom = keyAndZoom.substring(at + 1);
    return _load(
      ref,
      key,
      detail: false,
      cacheKey: '$simulateCachePrefix$zoom',
    );
  },
);

/// Every entry of one period: "from|to|group|scenario json".
final simDetailProvider = FutureProvider.autoDispose.family<SimLoad, String>(
  retry: simRetry,
  (ref, key) => _load(ref, key, detail: true),
);
