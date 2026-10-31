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
import '../../core/marks.dart';
import '../../state/providers.dart';
import '../../ui/manila_clock.dart';
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

/// The marks of a map of id to {icon, imageId}; an older server sends none.
Map<String, Mark> _marksOf(Object? v) => <String, Mark>{
  for (final e in asJson(v).entries) e.key: markOf(asJson(e.value)),
};

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
      totalsKnown = j.containsKey('recordedSpent'),
      recordedSpent = _intOrNull(j['recordedSpent']),
      recordedReceived = _intOrNull(j['recordedReceived']),
      recordedUntracked = _intOrNull(j['recordedUntracked']),
      replaySpent = _intOrNull(j['replaySpent']),
      replayReceived = _intOrNull(j['replayReceived']),
      simulatedSpent = _intOrNull(j['simulatedSpent']),
      simulatedReceived = _intOrNull(j['simulatedReceived']),
      leftOut = <String>[for (final c in asList(j['leftOut'])) str(c)],
      spanFrom = j['spanFrom'] is String ? str(j['spanFrom']) : null,
      spanTo = j['spanTo'] is String ? str(j['spanTo']) : null,
      spanSimulated = j['spanSource'] == 'simulated',
      spanSpent = _intOrNull(j['spanSpent']),
      spanReceived = _intOrNull(j['spanReceived']),
      spanLeftOut = <String>[for (final c in asList(j['spanLeftOut'])) str(c)],
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

  /// False for an older saved answer that has no spent and received at all: then no card is drawn (never zeros).
  final bool totalsKnown;

  /// Money out and in during the period in the main currency, worked out by the server: spent is expenses plus transfer fees minus
  /// refunds, received is income, untracked is a negative balance count. Null when that source has nothing for the period.
  final int? recordedSpent;
  final int? recordedReceived;
  final int? recordedUntracked;
  final int? replaySpent;
  final int? replayReceived;
  final int? simulatedSpent;
  final int? simulatedReceived;

  /// Currencies of this period's money that have no exchange rate: left out of the figures above.
  final List<String> leftOut;

  /// The running total across the span between this period and today, worked out by the server: a past period from its start to
  /// today (recorded), a future one from today to its end (simulated). Absent or null for the period of today, a period before the
  /// first record and an older saved answer: then no card is drawn (never zeros).
  final String? spanFrom;
  final String? spanTo;
  final bool spanSimulated;
  final int? spanSpent;
  final int? spanReceived;

  /// Currencies with no rate left out of the span figures only; `leftOut` stays the period's own.
  final List<String> spanLeftOut;
  final List<SimWallet> wallets;

  /// True when the server sent a span for this period.
  bool get spanKnown =>
      spanFrom != null &&
      spanTo != null &&
      spanSpent != null &&
      spanReceived != null;

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
    : id = str(j['id']),
      source = _source(j['source']),
      kind = str(j['kind']),
      date = str(j['date']),
      label = str(j['label']),
      accountId = str(j['accountId']),
      accountName = str(j['accountName']),
      toAccountName = str(j['toAccountName']),
      currency = str(j['currency']),
      amount = _intOrNull(j['amount']),
      amountMain = _intOrNull(j['amountMain']),
      groupKey = j['groupKey'] is String ? str(j['groupKey']) : null,
      refund = boolOf(j['refund']),
      pretend = boolOf(j['pretend']);

  /// Stable across requests, so a page that overlaps the one before is not listed twice.
  final String id;
  final SimSource source;

  /// in, out or move.
  final String kind;
  final String date;
  final String label;
  final String accountId;
  final String accountName;
  final String toAccountName;
  final String currency;
  final int? amount;

  /// The amount in the main currency at the stored rates; null for a currency with no rate (or no amount).
  final int? amountMain;

  /// The bill, category or other it counts under in the spending breakdown; null for money in, moves and what was missed.
  final String? groupKey;

  /// Money back for an earlier expense: it lowers spending.
  final bool refund;

  /// A one-off entry of a what-if.
  final bool pretend;
}

/// One group of spending: a bill, a category or other. The amount is in the main currency (refunds count below zero).
class SpendGroup {
  SpendGroup(Json j)
    : key = str(j['key']),
      label = str(j['label']),
      kind = str(j['kind']),
      amount = intOf(j['amount']),
      count = intOf(j['count']);

  final String key;

  /// Empty for other: the screen words it in the person's language.
  final String label;

  /// bill, category or other.
  final String kind;
  final int amount;
  final int count;
}

/// The spending of one source by group: the biggest ones one by one and the rest together.
class SpendBreakdown {
  SpendBreakdown(Json j)
    : groups = <SpendGroup>[
        for (final g in asJsonList(j['groups'])) SpendGroup(g),
      ],
      moreAmount = j['more'] is Map ? intOf(asJson(j['more'])['amount']) : 0,
      moreCount = j['more'] is Map ? intOf(asJson(j['more'])['count']) : 0,
      moreGroups = j['more'] is Map ? intOf(asJson(j['more'])['groups']) : 0;

  final List<SpendGroup> groups;
  final int moreAmount;
  final int moreCount;

  /// How many groups are in the rest; 0 when every group is listed.
  final int moreGroups;
}

/// Where the money went, by source.
class SimBreakdowns {
  SimBreakdowns(Json j)
    : recorded = SpendBreakdown(asJson(j['recorded'])),
      replay = SpendBreakdown(asJson(j['replay'])),
      simulated = SpendBreakdown(asJson(j['simulated']));

  final SpendBreakdown recorded;
  final SpendBreakdown replay;
  final SpendBreakdown simulated;
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
      entriesTotal = _intOrNull(j['entriesTotal']),
      breakdown = j['breakdown'] is Map
          ? SimBreakdowns(asJson(j['breakdown']))
          : null,
      warnings = <SimWarning>[
        for (final w in asJsonList(j['warnings'])) SimWarning(w),
      ],
      unknown = <SimUnknown>[
        for (final u in asJsonList(j['unknown'])) SimUnknown(u),
      ],
      notes = <String>[for (final n in asList(j['notes'])) str(n)],
      missing = <String>[for (final m in asList(j['missing'])) str(m)],
      ratesStale = boolOf(asJson(j['rates'])['stale']),
      billMarks = _marksOf(asJson(j['marks'])['bills']);

  final String from;
  final String to;
  final String today;
  final String currency;
  final String? firstRecord;
  final List<SimPeriod> periods;
  final List<SimEntry> entries;
  final int entriesOmitted;

  /// With a page: how many entries there are (of the group asked for). Null for the older answer.
  final int? entriesTotal;

  /// The detail view only: the spending of the whole range by group.
  final SimBreakdowns? breakdown;
  final List<SimWarning> warnings;
  final List<SimUnknown> unknown;
  final List<String> notes;
  final List<String> missing;
  final bool ratesStale;

  /// The icon or picture of each bill by id, to draw beside a bill in the spending breakdown. Empty from an older server.
  final Map<String, Mark> billMarks;

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
    addCalendarDays(_dayOnly(today), -(reachDays - 1));
DateTime latestDay(DateTime today) =>
    addCalendarDays(_dayOnly(today), reachDays - 1);

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
      final weeks = calendarDaysBetween(epoch, weekStart(a, weekStartsOn)) ~/ 7;
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
  while (calendarDaysBetween(from, to) + 1 > reachDays) {
    to = addCalendarDays(to, -1);
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
  SimView build() => SimView(zoom: Zoom.month, anchor: manilaTodayPicker());

  DateTime get _today => manilaTodayPicker();

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

/// The group of spending the entries are limited to (a bill, a category or other), or null for all. Cleared when the period, the zoom or
/// the what-if changes.
class SimGroupNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void pick(String? key) => state = key;
}

final NotifierProvider<SimGroupNotifier, String?> simGroupProvider =
    NotifierProvider.autoDispose<SimGroupNotifier, String?>(
      SimGroupNotifier.new,
    );

/// How many entries one page asks for.
const int simPageSize = 50;

/// The entries shown so far for one period (and group), the total there are, and where the spending went.
class SimEntries {
  const SimEntries({
    required this.rows,
    required this.total,
    required this.sim,
    this.loadingMore = false,
    this.pageError,
  });

  final List<SimEntry> rows;
  final int total;

  /// The first page's answer: the period, its breakdown and the main currency.
  final SimResult sim;
  final bool loadingMore;

  /// A later page that could not be loaded: the rows already shown stay and a retry row is drawn.
  final Object? pageError;

  bool get hasMore => rows.length < total;

  SimEntries copyWith({
    List<SimEntry>? rows,
    int? total,
    bool? loadingMore,
    Object? pageError,
    bool clearError = false,
  }) => SimEntries(
    rows: rows ?? this.rows,
    total: total ?? this.total,
    sim: sim,
    loadingMore: loadingMore ?? this.loadingMore,
    pageError: clearError ? null : (pageError ?? this.pageError),
  );
}

/// One page of a period's entries, from "from|to|group|groupKey|scenario json" (groupKey empty for all). The first page comes with the
/// state; loadMore appends the next one, and a page that fails keeps the rows already there.
class SimEntriesNotifier extends AsyncNotifier<SimEntries> {
  SimEntriesNotifier(this.key);

  final String key;

  Future<SimResult> _page(int offset) async {
    final parts = key.split('|');
    // The group is encoded in the key, since a category name may hold the separator
    final groupKey = parts.length > 3 ? Uri.decodeComponent(parts[3]) : '';
    final scenario = parts.length > 4 && parts[4].isNotEmpty
        ? asJson(jsonDecode(parts.sublist(4).join('|')))
        : null;
    final answer = asJson(
      await ref.read(apiProvider).verb('balance_simulate', <String, Object?>{
        'from': parts[0],
        'to': parts[1],
        'group': parts[2],
        'view': 'detail',
        'offset': offset,
        'limit': simPageSize,
        if (groupKey.isNotEmpty) 'groupKey': groupKey,
        'scenario': ?scenario,
      }),
    );
    return SimResult(answer);
  }

  @override
  Future<SimEntries> build() async {
    final first = await _retrying(() => _page(0));
    return SimEntries(
      rows: first.entries,
      total: first.entriesTotal ?? first.entries.length,
      sim: first,
    );
  }

  /// A lost connection is asked again a few times; a refusal is shown at once.
  Future<SimResult> _retrying(Future<SimResult> Function() ask) async {
    for (var tries = 0; ; tries++) {
      try {
        return await ask();
      } on Object catch (e) {
        final wait = simRetry(tries, e);
        if (wait == null) rethrow;
        await Future<void>.delayed(wait);
      }
    }
  }

  /// Asks for the next page, once at a time; rows already shown are kept and a repeat of one is dropped.
  Future<void> loadMore() async {
    final now = state.value;
    if (now == null || now.loadingMore || !now.hasMore) return;
    state = AsyncData<SimEntries>(
      now.copyWith(loadingMore: true, clearError: true),
    );
    try {
      final page = await _page(now.rows.length);
      // The period or the what-if changed while the page was on its way: this list is gone and nothing is written to it
      if (!ref.mounted) return;
      final seen = <String>{for (final r in now.rows) r.id};
      final added = <SimEntry>[
        for (final r in page.entries)
          if (seen.add(r.id)) r,
      ];
      final rows = <SimEntry>[...now.rows, ...added];
      state = AsyncData<SimEntries>(
        now.copyWith(
          rows: rows,
          // A page that brings nothing new means the total is stale: stop asking instead of asking again and again
          total: added.isEmpty ? rows.length : (page.entriesTotal ?? now.total),
          loadingMore: false,
          clearError: true,
        ),
      );
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = AsyncData<SimEntries>(
        now.copyWith(loadingMore: false, pageError: e),
      );
    }
  }
}

/// No retry of its own: a lost connection is asked again inside the notifier, and a refusal is shown at once.
final simEntriesProvider = AsyncNotifierProvider.autoDispose
    .family<SimEntriesNotifier, SimEntries, String>(
      SimEntriesNotifier.new,
      retry: (_, _) => null,
    );
