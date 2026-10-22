// THE CALENDAR'S DATA: ONE RANGE OF DAYS FROM THE SERVER'S calendar_range VERB, KEPT ON THE PHONE SO THE LAST ONE SHOWS OFFLINE.
// The server does the date maths and the forecast; the phone only reads the answer and draws it. A range is at most 92 days.

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/json.dart';
import '../../state/providers.dart';

// -- TYPES -- //

enum CalLayer { bills, paydays, events, routines, tasks, reminders }

/// One dated thing. The fields that do not apply to its [kind] stay at their defaults.
class CalItem {
  CalItem(Json j)
    : kind = str(j['type']),
      id = str(j['id']),
      title = str(j['title']),
      date = str(j['date']),
      endDate = str(j['endDate'], str(j['date'])),
      amount = j['amount'] is num ? intOf(j['amount']) : null,
      unknownAmount = boolOf(j['unknownAmount']),
      paid = boolOf(j['paid']) || boolOf(j['done']),
      overdue = boolOf(j['overdue']),
      allDay = boolOf(j['allDay']),
      untrusted = boolOf(j['untrusted']),
      source = str(j['source']),
      accountId = str(j['accountId']),
      at = str(j['startsAt'], str(j['at'], str(j['dueAt'])));

  /// bill, payday, event, routine, task or reminder.
  final String kind;
  final String id;
  final String title;

  /// First and last day, Manila dates as yyyy-MM-dd.
  final String date;
  final String endDate;
  final int? amount;
  final bool unknownAmount;
  final bool paid;
  final bool overdue;
  final bool allDay;
  final bool untrusted;
  final String source;
  final String accountId;

  /// The moment as an ISO text, when the thing has a time of day.
  final String at;

  bool get isWindow => endDate != date;

  bool coversDay(String day) =>
      day.compareTo(date) >= 0 && day.compareTo(endDate) <= 0;

  CalLayer get layer => switch (kind) {
    'bill' => CalLayer.bills,
    'payday' => CalLayer.paydays,
    'event' => CalLayer.events,
    'routine' => CalLayer.routines,
    'task' => CalLayer.tasks,
    _ => CalLayer.reminders,
  };
}

class CalForecastDay {
  CalForecastDay(Json j)
    : date = str(j['date']),
      total = intOf(j['total']),
      low = <String>[for (final a in asList(j['lowAccountIds'])) str(a)];

  final String date;
  final int total;
  final List<String> low;
}

class CalRange {
  CalRange(Json j)
    : from = str(j['from']),
      to = str(j['to']),
      items = <CalItem>[for (final i in asJsonList(j['items'])) CalItem(i)],
      days = <CalForecastDay>[
        for (final d in asJsonList(asJson(j['forecast'])['days']))
          CalForecastDay(d),
      ],
      accountNames = <String, String>{
        for (final a in asJsonList(asJson(j['forecast'])['accounts']))
          str(a['id']): str(a['name']),
      },
      unknownBills = intOf(asJson(j['forecast'])['unknownBills']);

  final String from;
  final String to;
  final List<CalItem> items;
  final List<CalForecastDay> days;
  final Map<String, String> accountNames;
  final int unknownBills;

  List<CalItem> on(String day) => <CalItem>[
    for (final i in items)
      if (i.coversDay(day)) i,
  ];
}

/// A loaded range, and whether it came from the phone's own copy because the server could not be reached.
class CalLoad {
  CalLoad(this.range, {this.offline = false});

  final CalRange range;
  final bool offline;
}

// -- CONSTANTS -- //

final DateFormat dayKey = DateFormat('yyyy-MM-dd');
const String _layersKey = 'calendar.layers.v1';

/// Where the last range is kept on the phone. Cleared by a data reset.
const String calendarCacheKey = 'calendar.range.v1';

// -- FUNCTIONS -- //

String dayOf(DateTime d) => dayKey.format(d);

DateTime parseDay(String day) {
  final p = day.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// The first day shown for the week that holds [d], given the weekday the week starts on (0 Sunday, 1 Monday ...).
DateTime weekStart(DateTime d, int startsOn) {
  final back = (d.weekday % 7 - startsOn + 7) % 7;
  return DateTime(d.year, d.month, d.day - back);
}

// -- STATES -- //

/// The layers switched on, remembered between visits.
class LayersNotifier extends Notifier<Set<CalLayer>> {
  @override
  Set<CalLayer> build() {
    final saved = ref.watch(prefsProvider).getStringList(_layersKey);
    if (saved == null) return CalLayer.values.toSet();
    return <CalLayer>{
      for (final n in saved)
        for (final l in CalLayer.values)
          if (l.name == n) l,
    };
  }

  Future<void> toggle(CalLayer layer) async {
    final next = <CalLayer>{...state};
    if (!next.remove(layer)) next.add(layer);
    state = next;
    await ref.read(prefsProvider).setStringList(_layersKey, <String>[
      for (final l in next) l.name,
    ]);
  }
}

final NotifierProvider<LayersNotifier, Set<CalLayer>> calLayersProvider =
    NotifierProvider<LayersNotifier, Set<CalLayer>>(LayersNotifier.new);

/// A range asked for as "from|to". All layers are asked for, and the screen hides the ones switched off, so a toggle never refetches.
final calRangeProvider = FutureProvider.autoDispose.family<CalLoad, String>((
  ref,
  key,
) async {
  final prefs = ref.watch(prefsProvider);
  final parts = key.split('|');
  try {
    final answer = asJson(
      await ref.watch(apiProvider).verb('calendar_range', <String, Object?>{
        'from': parts[0],
        'to': parts[1],
      }),
    );
    // Only the latest range is kept, so the copy on the phone stays small
    try {
      await prefs.setString(
        calendarCacheKey,
        jsonEncode(<String, Object?>{'key': key, 'data': answer}),
      );
    } on Object {
      // A full disk must not throw away an answer that just arrived
    }
    return CalLoad(CalRange(answer));
  } on ApiException catch (e) {
    // Only a missing connection falls back to the copy, and only for the same days; any other failure is shown as it is
    if (e.code != 'NETWORK') rethrow;
    final saved = decodeJson(prefs.getString(calendarCacheKey) ?? '');
    if (str(saved['key']) != key) rethrow;
    return CalLoad(CalRange(asJson(saved['data'])), offline: true);
  }
});
