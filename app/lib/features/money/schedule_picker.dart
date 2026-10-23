// "WHEN?" FOR A BILL OR A PAYDAY, IN PLAIN CHOICES THAT SAY WHAT THEY MEAN: ON A DAY, ON THE 1ST WEDNESDAY, IN THE FIRST WEEK, BETWEEN TWO DAYS, EVERY FEW WEEKS.
// Under the choices the person reads the schedule back as a sentence and sees the next dates, which the server works out (schedule_preview), so a wrong
// schedule shows before it is saved. A bill can be paid any day inside a window. The server checks the schedule again and explains any problem in words.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/schedule_text.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';

// -- TYPES -- //

/// The patterns the person can pick.
enum SchedulePattern {
  monthlyDay,
  semiMonthly,
  nthWeekday,
  weekOfMonth,
  dayRange,
  weekly,
  everyNDays,
  yearly,
  once,
}

/// What the person has chosen so far. The same object is edited by the picker and read by the form that saves it.
class ScheduleValue {
  ScheduleValue({
    this.pattern = SchedulePattern.monthlyDay,
    this.day = 1,
    this.day2 = 15,
    this.n = 14,
    this.nth = 1,
    this.weekday = 3,
    this.basis = 'days',
    this.pick = 'window',
    this.from = 5,
    this.to = 10,
    this.everyMonths = 1,
    this.everyWeeks = 1,
    this.month = 1,
    Set<int>? weekdays,
    DateTime? anchor,
  }) : weekdays = weekdays ?? <int>{5},
       anchor = anchor ?? DateTime.now();

  SchedulePattern pattern;

  /// A day of the month, 1 to 31, or -1 for the last day.
  int day;
  int day2;

  /// Every n days.
  int n;

  /// 1 to 5, or -1 for the last.
  int nth;

  /// 0 is Sunday.
  int weekday;

  /// 'days' (days 1 to 7, 8 to 14 ...) or 'calendar'.
  String basis;

  /// 'window' (any day of the week) or 'weekday'.
  String pick;
  int from;

  /// A day of the month, or -1 for the end of the month.
  int to;
  int everyMonths;
  int everyWeeks;
  int month;
  Set<int> weekdays;
  DateTime anchor;

  /// A schedule from the server that a person opens to edit. A kind this version does not know is left alone: null.
  static ScheduleValue? fromJson(Json s) {
    final kind = str(s['kind']);
    if (!knownScheduleKinds.contains(kind)) return null;
    final v = ScheduleValue(everyMonths: intOf(s['everyMonths'], 1));
    switch (kind) {
      case 'monthly':
        v.pattern = SchedulePattern.monthlyDay;
        v.day = intOf(s['day'], 1);
      case 'semi_monthly':
        v.pattern = SchedulePattern.semiMonthly;
        final d = asList(s['days']);
        v.day = d.isNotEmpty ? intOf(d[0], 1) : 1;
        v.day2 = d.length > 1 ? intOf(d[1], 15) : 15;
      case 'every_n_days':
        v.pattern = SchedulePattern.everyNDays;
        v.n = intOf(s['n'], 14);
        v.anchor = DateTime.tryParse(str(s['anchor'])) ?? DateTime.now();
      case 'weekly':
        v.pattern = SchedulePattern.weekly;
        v.weekdays = asList(s['days']).map((d) => intOf(d)).toSet();
        v.everyWeeks = intOf(s['everyWeeks'], 1);
        final a = DateTime.tryParse(str(s['anchor']));
        if (a != null) v.anchor = a;
      case 'nth_weekday':
        v.pattern = SchedulePattern.nthWeekday;
        v.nth = intOf(s['n'], 1);
        v.weekday = intOf(s['weekday'], 3);
      case 'week_of_month':
        v.pattern = SchedulePattern.weekOfMonth;
        v.nth = intOf(s['n'], 1);
        v.basis = str(s['basis'], 'days');
        v.pick = str(s['pick'], 'window');
        v.weekday = intOf(s['weekday'], 3);
      case 'day_range':
        v.pattern = SchedulePattern.dayRange;
        v.from = intOf(s['from'], 5);
        v.to = intOf(s['to'], 10);
      case 'yearly':
        v.pattern = SchedulePattern.yearly;
        v.month = intOf(s['month'], 1);
        v.day = intOf(s['day'], 1);
      case 'once':
        v.pattern = SchedulePattern.once;
        v.anchor = DateTime.tryParse(str(s['date'])) ?? DateTime.now();
    }
    return v;
  }

  /// Whether this schedule falls on a single day (a weekend rule makes sense) rather than a window of days.
  bool get isSingleDay =>
      pattern != SchedulePattern.dayRange &&
      !(pattern == SchedulePattern.weekOfMonth && pick == 'window');

  String get _anchorMonth => DateFormat('yyyy-MM').format(DateTime.now());

  Json get _cycle => everyMonths > 1
      ? <String, Object?>{
          'everyMonths': everyMonths,
          'anchorMonth': _anchorMonth,
        }
      : <String, Object?>{};

  /// The schedule as the server takes it.
  Json toJson() {
    switch (pattern) {
      case SchedulePattern.monthlyDay:
        return <String, Object?>{'kind': 'monthly', 'day': day, ..._cycle};
      case SchedulePattern.semiMonthly:
        return <String, Object?>{
          'kind': 'semi_monthly',
          'days': <int>[day, day2],
        };
      case SchedulePattern.nthWeekday:
        return <String, Object?>{
          'kind': 'nth_weekday',
          'n': nth,
          'weekday': weekday,
          ..._cycle,
        };
      case SchedulePattern.weekOfMonth:
        return <String, Object?>{
          'kind': 'week_of_month',
          'n': nth,
          'basis': basis,
          'pick': pick,
          if (pick == 'weekday') 'weekday': weekday,
          ..._cycle,
        };
      case SchedulePattern.dayRange:
        return <String, Object?>{
          'kind': 'day_range',
          'from': from,
          'to': to,
          ..._cycle,
        };
      case SchedulePattern.weekly:
        final days = (weekdays.isEmpty ? <int>{5} : weekdays).toList()..sort();
        return <String, Object?>{
          'kind': 'weekly',
          'days': days,
          if (everyWeeks > 1) ...<String, Object?>{
            'everyWeeks': everyWeeks,
            'anchor': DateFormat('yyyy-MM-dd').format(anchor),
          },
        };
      case SchedulePattern.everyNDays:
        return <String, Object?>{
          'kind': 'every_n_days',
          'anchor': DateFormat('yyyy-MM-dd').format(anchor),
          'n': n,
        };
      case SchedulePattern.yearly:
        return <String, Object?>{'kind': 'yearly', 'month': month, 'day': day};
      case SchedulePattern.once:
        return <String, Object?>{
          'kind': 'once',
          'date': DateFormat('yyyy-MM-dd').format(anchor),
        };
    }
  }
}

class SchedulePicker extends ConsumerStatefulWidget {
  const SchedulePicker({
    required this.value,
    required this.onChanged,
    this.weekend,
    this.singleDayOnly = false,
    super.key,
  });

  final ScheduleValue value;
  final VoidCallback onChanged;

  /// The weekend rule that goes with the schedule, used by the preview ('none', 'before' or 'after').
  final String? weekend;

  /// A payday is one day: the patterns that give a window are not offered.
  final bool singleDayOnly;

  @override
  ConsumerState<SchedulePicker> createState() => _SchedulePickerState();
}

class _SchedulePickerState extends ConsumerState<SchedulePicker> {
  // -- STATES -- //

  Timer? _debounce;
  int _ticket = 0;
  List<Json> _windows = const <Json>[];
  bool _offline = false;
  String? _problem;

  // -- FUNCTIONS -- //

  ScheduleValue get v => widget.value;

  @override
  void initState() {
    super.initState();
    _preview();
  }

  @override
  void didUpdateWidget(SchedulePicker old) {
    super.didUpdateWidget(old);
    if (old.weekend != widget.weekend) _preview();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _set(VoidCallback change) {
    setState(change);
    widget.onChanged();
    _preview();
  }

  /// Asks the server for the next dates a moment after the person stops changing things. A late answer to an old question is dropped.
  void _preview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final ticket = ++_ticket;
      try {
        final out = await ref.read(apiProvider).verbJson(
          'schedule_preview',
          <String, Object?>{
            'schedule': v.toJson(),
            'weekend': widget.weekend ?? 'none',
            'count': 6,
          },
        );
        if (!mounted || ticket != _ticket) return;
        setState(() {
          _windows = asJsonList(out['windows']);
          _offline = false;
          _problem = null;
        });
      } on ApiException catch (e) {
        if (!mounted || ticket != _ticket) return;
        setState(() {
          _windows = const <Json>[];
          _offline = e.isNetwork;
          _problem = e.isNetwork ? null : e.message;
        });
      }
    });
  }

  List<DropdownMenuItem<int>> _days({bool withLast = false}) =>
      <DropdownMenuItem<int>>[
        for (var d = 1; d <= 31; d++)
          DropdownMenuItem<int>(value: d, child: Text('$d')),
        if (withLast)
          DropdownMenuItem<int>(value: -1, child: Text(context.t.schedLastDay)),
      ];

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T> onPick,
  }) => DropdownButtonFormField<T>(
    // ignore: deprecated_member_use
    value: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: items,
    onChanged: (x) => x == null ? null : _set(() => onPick(x)),
  );

  String _patternLabel(SchedulePattern p) {
    final t = context.t;
    return switch (p) {
      SchedulePattern.monthlyDay => t.schedPatMonthlyDay,
      SchedulePattern.semiMonthly => t.schedPatSemi,
      SchedulePattern.nthWeekday => t.schedPatNthWeekday,
      SchedulePattern.weekOfMonth => t.schedPatWeek,
      SchedulePattern.dayRange => t.schedPatRange,
      SchedulePattern.weekly => t.schedPatWeekly,
      SchedulePattern.everyNDays => t.schedPatEveryN,
      SchedulePattern.yearly => t.schedPatYearly,
      SchedulePattern.once => t.schedPatOnce,
    };
  }

  Widget _everyMonths() {
    final t = context.t;
    return _dropdown<int>(
      label: t.schedRepeat,
      value: v.everyMonths,
      items: <DropdownMenuItem<int>>[
        DropdownMenuItem<int>(value: 1, child: Text(t.schedEvery1)),
        DropdownMenuItem<int>(value: 2, child: Text(t.schedEvery2)),
        DropdownMenuItem<int>(value: 3, child: Text(t.schedEvery3)),
        DropdownMenuItem<int>(value: 6, child: Text(t.schedEvery6)),
        DropdownMenuItem<int>(value: 12, child: Text(t.schedEvery12)),
      ],
      onPick: (x) => v.everyMonths = x,
    );
  }

  Widget _weekdayPicker(String locale, {String? label}) {
    final names = weekdayNames(locale);
    return _dropdown<int>(
      label: label ?? context.t.schedWeekday,
      value: v.weekday,
      items: <DropdownMenuItem<int>>[
        for (var d = 0; d < 7; d++)
          DropdownMenuItem<int>(value: d, child: Text(names[d])),
      ],
      onPick: (x) => v.weekday = x,
    );
  }

  List<DropdownMenuItem<int>> _nthItems() {
    final t = context.t;
    return <DropdownMenuItem<int>>[
      DropdownMenuItem<int>(value: 1, child: Text(t.schedNth1)),
      DropdownMenuItem<int>(value: 2, child: Text(t.schedNth2)),
      DropdownMenuItem<int>(value: 3, child: Text(t.schedNth3)),
      DropdownMenuItem<int>(value: 4, child: Text(t.schedNth4)),
      DropdownMenuItem<int>(value: 5, child: Text(t.schedNth5)),
      DropdownMenuItem<int>(value: -1, child: Text(t.schedNthLast)),
    ];
  }

  /// The controls of the chosen pattern.
  List<Widget> _controls(String locale) {
    final t = context.t;
    const gap = SizedBox(height: 12);
    switch (v.pattern) {
      case SchedulePattern.monthlyDay:
        return <Widget>[
          _dropdown<int>(
            label: t.schedDay,
            value: v.day,
            items: _days(withLast: true),
            onPick: (x) => v.day = x,
          ),
          gap,
          _everyMonths(),
        ];
      case SchedulePattern.semiMonthly:
        return <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _dropdown<int>(
                  label: t.schedFirstDay,
                  value: v.day,
                  items: _days(),
                  onPick: (x) => v.day = x,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dropdown<int>(
                  label: t.schedSecondDay,
                  value: v.day2,
                  items: _days(),
                  onPick: (x) => v.day2 = x,
                ),
              ),
            ],
          ),
        ];
      case SchedulePattern.nthWeekday:
        return <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _dropdown<int>(
                  label: t.schedWhichOne,
                  value: v.nth,
                  items: _nthItems(),
                  onPick: (x) => v.nth = x,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _weekdayPicker(locale)),
            ],
          ),
          gap,
          _everyMonths(),
        ];
      case SchedulePattern.weekOfMonth:
        return <Widget>[
          _dropdown<int>(
            label: t.schedWhichWeek,
            value: v.nth,
            items: _nthItems(),
            onPick: (x) => v.nth = x,
          ),
          gap,
          _dropdown<String>(
            label: t.schedHow,
            value: v.basis,
            items: <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: 'days',
                child: Text(t.schedBasisDays),
              ),
              DropdownMenuItem<String>(
                value: 'calendar',
                child: Text(t.schedBasisCalendar),
              ),
            ],
            onPick: (x) => v.basis = x,
          ),
          gap,
          if (!widget.singleDayOnly)
            _dropdown<String>(
              label: t.schedWeekday,
              value: v.pick,
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: 'window',
                  child: Text(t.schedPickWindow),
                ),
                DropdownMenuItem<String>(
                  value: 'weekday',
                  child: Text(t.schedPickWeekday),
                ),
              ],
              onPick: (x) => v.pick = x,
            ),
          if (v.pick == 'weekday') ...<Widget>[gap, _weekdayPicker(locale)],
          gap,
          _everyMonths(),
        ];
      case SchedulePattern.dayRange:
        return <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _dropdown<int>(
                  label: t.schedFromDay,
                  value: v.from,
                  items: _days(),
                  onPick: (x) => v.from = x,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dropdown<int>(
                  label: t.schedToDay,
                  value: v.to,
                  items: _days(withLast: true),
                  onPick: (x) => v.to = x,
                ),
              ),
            ],
          ),
          gap,
          _everyMonths(),
        ];
      case SchedulePattern.weekly:
        final names = DateFormat('EEE', locale).dateSymbols.SHORTWEEKDAYS;
        final week = <int>[
          if (ref.read(settingsProvider).weekStartsOn == 1) ...<int>[
            1,
            2,
            3,
            4,
            5,
            6,
            0,
          ] else ...<int>[0, 1, 2, 3, 4, 5, 6],
        ];
        return <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final d in week)
                FilterChip(
                  label: Text(names[d]),
                  selected: v.weekdays.contains(d),
                  onSelected: (on) => _set(() {
                    if (on) {
                      v.weekdays.add(d);
                    } else if (v.weekdays.length > 1) {
                      v.weekdays.remove(d);
                    }
                  }),
                ),
            ],
          ),
          gap,
          _dropdown<int>(
            label: t.schedRepeat,
            value: v.everyWeeks,
            items: <DropdownMenuItem<int>>[
              DropdownMenuItem<int>(value: 1, child: Text(t.schedEveryWeeks1)),
              DropdownMenuItem<int>(value: 2, child: Text(t.schedEveryWeeks2)),
              DropdownMenuItem<int>(value: 3, child: Text(t.schedEveryWeeks3)),
              DropdownMenuItem<int>(value: 4, child: Text(t.schedEveryWeeks4)),
            ],
            onPick: (x) => v.everyWeeks = x,
          ),
          if (v.everyWeeks > 1) ...<Widget>[gap, _datePicker(locale)],
        ];
      case SchedulePattern.everyNDays:
        return <Widget>[
          _dropdown<int>(
            label: t.schedEveryDays,
            value: v.n.clamp(1, 60),
            items: <DropdownMenuItem<int>>[
              for (final d in <int>[1, 2, 3, 5, 7, 10, 14, 21, 28, 30, 45, 60])
                DropdownMenuItem<int>(value: d, child: Text('$d')),
            ],
            onPick: (x) => v.n = x,
          ),
          gap,
          _datePicker(locale),
        ];
      case SchedulePattern.yearly:
        final months = monthNames(locale);
        return <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _dropdown<int>(
                  label: t.schedMonth,
                  value: v.month,
                  items: <DropdownMenuItem<int>>[
                    for (var m = 1; m <= 12; m++)
                      DropdownMenuItem<int>(
                        value: m,
                        child: Text(months[m - 1]),
                      ),
                  ],
                  onPick: (x) => v.month = x,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dropdown<int>(
                  label: t.schedDay,
                  value: v.day.clamp(1, 31),
                  items: _days(),
                  onPick: (x) => v.day = x,
                ),
              ),
            ],
          ),
        ];
      case SchedulePattern.once:
        return <Widget>[_datePicker(locale, label: t.schedOnDate)];
    }
  }

  Widget _datePicker(String locale, {String? label}) => OutlinedButton.icon(
    icon: const Icon(Icons.event),
    label: Text(
      '${label ?? context.t.schedStartingOn} ${DateFormat.yMMMd(locale).format(v.anchor)}',
    ),
    onPressed: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: v.anchor,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (picked != null) _set(() => v.anchor = picked);
    },
  );

  /// The sentence under the choices and the next dates the server found.
  Widget _readBack(String locale) {
    final c = context.colors;
    final t = context.t;
    final sentence = describeSchedule(t, locale, v.toJson());
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (sentence != null)
            Semantics(
              liveRegion: true,
              child: Text(
                sentence,
                style: TextStyle(
                  color: c.accentText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(t.schedPreviewTitle, style: TextStyle(color: c.muted)),
          const SizedBox(height: 4),
          if (_offline)
            Text(t.schedPreviewOffline, style: TextStyle(color: c.muted))
          else if (_problem != null)
            Text(_problem!, style: TextStyle(color: c.danger))
          else if (_windows.isEmpty)
            Text(t.schedPreviewNone, style: TextStyle(color: c.muted))
          else
            for (final w in _windows)
              Text(_windowText(locale, w), style: TextStyle(color: c.ink)),
        ],
      ),
    );
  }

  String _windowText(String locale, Json w) {
    final start = DateTime.tryParse(str(w['start']));
    final end = DateTime.tryParse(str(w['end']));
    if (start == null || end == null) return str(w['end']);
    final f = DateFormat('EEE, MMM d', locale);
    return start == end
        ? f.format(end)
        : context.t.schedPreviewWindow(f.format(start), f.format(end));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final locale = Localizations.localeOf(context).toString();
    final patterns = SchedulePattern.values.where(
      (p) =>
          // A payday repeats and is one day, so it gets neither a range of days nor a single date
          !(widget.singleDayOnly &&
              (p == SchedulePattern.dayRange || p == SchedulePattern.once)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(context.t.schedHow, style: TextStyle(color: c.muted)),
        const SizedBox(height: 8),
        _dropdown<SchedulePattern>(
          label: context.t.schedHow,
          value: v.pattern,
          items: <DropdownMenuItem<SchedulePattern>>[
            for (final p in patterns)
              DropdownMenuItem<SchedulePattern>(
                value: p,
                child: Text(_patternLabel(p), overflow: TextOverflow.ellipsis),
              ),
          ],
          onPick: (p) => v.pattern = p,
        ),
        const SizedBox(height: 12),
        ..._controls(locale),
        const SizedBox(height: 16),
        _readBack(locale),
      ],
    );
  }
}
