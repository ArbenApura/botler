// THE CALENDAR: BILLS AS PAYMENT WINDOWS, PAYDAYS, EVENTS, ROUTINES, TASKS AND REMINDERS ON ONE PAPER LEDGER, WITH A MONTH, A WEEK AND AN AGENDA VIEW.
// The server does the dates; this draws them. A window is a soft band across its days. At most three marks sit on a day, the rest are "+n".
// Tapping a day opens its sheet. The one primary action is Add. The last range seen is kept, so it still shows with no connection.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/manila.dart' show addDaysTo, manilaToday;
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/manila_clock.dart';
import '../../ui/ui.dart';
import 'calendar_data.dart';
import 'calendar_parts.dart';

// -- CONSTANTS -- //

const int _maxMarks = 3;

// -- TYPES -- //

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  // -- STATES -- //

  DateTime _focus = _today();
  int _agendaDays = 30;

  /// Today's Manila date as a calendar date.
  static DateTime _today() => manilaTodayPicker();

  // -- FUNCTIONS -- //

  /// The six weeks that show the month of [_focus], from the first week start on or before the 1st.
  DateTime _gridStart(int startsOn) =>
      weekStart(DateTime(_focus.year, _focus.month), startsOn);

  String _key(DateTime from, int days) =>
      '${dayOf(from)}|${dayOf(addCalendarDays(from, days - 1))}';

  void _shiftMonth(int by) =>
      setState(() => _focus = DateTime(_focus.year, _focus.month + by));

  void _shiftWeek(int by) =>
      setState(() => _focus = addCalendarDays(_focus, 7 * by));

  void _refresh(String key) => ref.invalidate(calRangeProvider(key));

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final startsOn = ref.watch(settingsProvider).weekStartsOn;
    return DefaultTabController(
      length: 3,
      child: Builder(
        builder: (context) {
          final tab = DefaultTabController.of(context);
          return AnimatedBuilder(
            animation: tab,
            builder: (context, _) {
              final view = tab.index;
              final DateTime from;
              final int span;
              if (view == 0) {
                from = _gridStart(startsOn);
                span = 42;
              } else if (view == 1) {
                from = weekStart(_focus, startsOn);
                span = 7;
              } else {
                from = _today();
                span = _agendaDays;
              }
              final key = _key(from, span);
              final load = ref.watch(calRangeProvider(key));
              return Scaffold(
                appBar: AppBar(
                  title: Text(t.calTitle),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => setState(() => _focus = _today()),
                      child: Text(t.calToday),
                    ),
                  ],
                  bottom: TabBar(
                    tabs: <Tab>[
                      Tab(text: t.calViewMonth),
                      Tab(text: t.calViewWeek),
                      Tab(text: t.calViewAgenda),
                    ],
                  ),
                ),
                floatingActionButton: FloatingActionButton.extended(
                  onPressed: () => showQuickAdd(
                    context,
                    ref,
                    day: _focus,
                    onChanged: () => _refresh(key),
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(t.calAdd),
                ),
                body: Column(
                  children: <Widget>[
                    const _LayerChips(),
                    Expanded(
                      child: AsyncBody<CalLoad>(
                        value: load,
                        skeleton: const SkeletonPage(
                          child: SkeletonRows(count: 6),
                        ),
                        onRetry: () => _refresh(key),
                        data: (data) => Column(
                          children: <Widget>[
                            if (data.offline) _OfflineBand(text: t.calOffline),
                            Expanded(
                              child: switch (view) {
                                0 => _MonthView(
                                  focus: _focus,
                                  start: from,
                                  range: data.range,
                                  startsOn: startsOn,
                                  onPrev: () => _shiftMonth(-1),
                                  onNext: () => _shiftMonth(1),
                                  onPick: (d) => setState(() => _focus = d),
                                  onChanged: () => _refresh(key),
                                ),
                                1 => _WeekView(
                                  start: from,
                                  focus: _focus,
                                  range: data.range,
                                  onPrev: () => _shiftWeek(-1),
                                  onNext: () => _shiftWeek(1),
                                  onChanged: () => _refresh(key),
                                ),
                                _ => _AgendaView(
                                  range: data.range,
                                  canMore: _agendaDays < 90,
                                  onMore: () => setState(
                                    () => _agendaDays = (_agendaDays + 30)
                                        .clamp(30, 90),
                                  ),
                                  onChanged: () => _refresh(key),
                                ),
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// -- LAYERS -- //

/// The switches for what the calendar shows, remembered between visits.
class _LayerChips extends ConsumerWidget {
  const _LayerChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(calLayersProvider);
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: <Widget>[
          for (final l in CalLayer.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: FilterChip(
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  label: Text(layerName(context, l)),
                  selected: on.contains(l),
                  onSelected: (_) =>
                      ref.read(calLayersProvider.notifier).toggle(l),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OfflineBand extends StatelessWidget {
  const _OfflineBand({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      color: c.chip,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text, style: TextStyle(color: c.muted)),
    );
  }
}

/// The items of a day that the switched-on layers show.
List<CalItem> _visible(CalRange r, Set<CalLayer> on, String day) => <CalItem>[
  for (final i in r.on(day))
    if (on.contains(i.layer)) i,
];

// -- MONTH -- //

class _MonthView extends ConsumerWidget {
  const _MonthView({
    required this.focus,
    required this.start,
    required this.range,
    required this.startsOn,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
    required this.onChanged,
  });

  final DateTime focus;
  final DateTime start;
  final CalRange range;
  final int startsOn;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onPick;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    final locale = Localizations.localeOf(context).toString();
    final on = ref.watch(calLayersProvider);
    final today = manilaToday();
    final names = DateFormat.E(locale).dateSymbols.SHORTWEEKDAYS;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(
              tooltip: t.calPrev,
              onPressed: onPrev,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                DateFormat.yMMMM(locale).format(focus),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: t.calNext,
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    names[(startsOn + i) % 7],
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: c.muted),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        // The grid turns the month on a horizontal swipe, and only the grid does
        GestureDetector(
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -200) onNext();
            if (v > 200) onPrev();
          },
          child: Column(
            children: <Widget>[
              for (var w = 0; w < 6; w++)
                _WeekRow(
                  days: <DateTime>[
                    for (var i = 0; i < 7; i++)
                      DateTime(start.year, start.month, start.day + w * 7 + i),
                  ],
                  month: focus.month,
                  today: today,
                  range: range,
                  on: on,
                  onTap: (d) {
                    onPick(d);
                    showDaySheet(
                      context,
                      ref,
                      day: d,
                      items: _visible(range, on, dayOf(d)),
                      onChanged: onChanged,
                    );
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CashflowStrip(range: range),
      ],
    );
  }
}

/// One week of the grid: the window bands behind, the day cells in front.
class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.days,
    required this.month,
    required this.today,
    required this.range,
    required this.on,
    required this.onTap,
  });

  final List<DateTime> days;
  final int month;
  final String today;
  final CalRange range;
  final Set<CalLayer> on;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (final d in days)
          Expanded(
            child: _DayCell(
              day: d,
              inMonth: d.month == month,
              isToday: dayOf(d) == today,
              items: _visible(range, on, dayOf(d)),
              onTap: () => onTap(d),
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.items,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final List<CalItem> items;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final key = dayOf(day);
    final locale = Localizations.localeOf(context).toString();
    // A payment window shows as a band across its days; the single-day things show as marks
    final windows = <CalItem>[
      for (final i in items)
        if (i.isWindow && i.kind == 'bill') i,
    ];
    final marks = <CalItem>[
      for (final i in items)
        if (!(i.isWindow && i.kind == 'bill')) i,
    ];
    // A window that is the only thing a day has still earns its mark on its last day
    final shown = <CalItem>[
      ...marks,
      for (final w in windows)
        if (w.endDate == key) w,
    ];
    final extra = shown.length - _maxMarks;
    final label = context.t.calDaySemantics(
      DateFormat.MMMMd(locale).format(day),
      dayParts(context, items),
    );
    final text = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontFeatures: tabular,
      color: inMonth ? c.ink : c.muted.withValues(alpha: 0.5),
      fontWeight: isToday ? FontWeight.w700 : null,
    );
    return Semantics(
      button: true,
      selected: isToday,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            // A cell is at least 48 dp so a thumb can find it, and grows with the text size
            constraints: const BoxConstraints(minHeight: 56),
            decoration: BoxDecoration(
              color: windows.isEmpty ? null : c.accentSoft,
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: isToday
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: c.accentText, width: 1.6),
                        )
                      : null,
                  child: Text('${day.day}', style: text),
                ),
                const SizedBox(height: 2),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 3,
                  runSpacing: 2,
                  children: <Widget>[
                    for (final i in shown.take(_maxMarks)) MarkIcon(i, size: 9),
                    if (extra > 0)
                      Text(
                        context.t.calMore(extra),
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: c.muted),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -- WEEK -- //

class _WeekView extends ConsumerWidget {
  const _WeekView({
    required this.start,
    required this.focus,
    required this.range,
    required this.onPrev,
    required this.onNext,
    required this.onChanged,
  });

  final DateTime start;
  final DateTime focus;
  final CalRange range;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    final locale = Localizations.localeOf(context).toString();
    final on = ref.watch(calLayersProvider);
    final today = manilaToday();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(
              tooltip: t.calPrev,
              onPressed: onPrev,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                t.calWeekOf(DateFormat.MMMd(locale).format(start)),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: t.calNext,
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        for (var i = 0; i < 7; i++)
          Builder(
            builder: (context) {
              final d = DateTime(start.year, start.month, start.day + i);
              final key = dayOf(d);
              final items = _visible(range, on, key);
              return InkWell(
                onTap: () => showDaySheet(
                  context,
                  ref,
                  day: d,
                  items: items,
                  onChanged: onChanged,
                ),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 64),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.line)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 56,
                        child: Column(
                          children: <Widget>[
                            Text(
                              DateFormat.E(locale).format(d),
                              style: TextStyle(color: c.muted),
                            ),
                            Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: key == today
                                  ? BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: c.accentText,
                                        width: 1.6,
                                      ),
                                    )
                                  : null,
                              child: Text(
                                '${d.day}',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontFeatures: tabular),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: items.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  t.calDayNothing,
                                  style: TextStyle(color: c.muted),
                                ),
                              )
                            : Column(
                                children: <Widget>[
                                  for (final it in items)
                                    ItemRow(it, day: key, onChanged: onChanged),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

// -- AGENDA -- //

/// A plain list of what is coming, day by day, with the bills still to pay this week first.
class _AgendaView extends ConsumerWidget {
  const _AgendaView({
    required this.range,
    required this.canMore,
    required this.onMore,
    required this.onChanged,
  });

  final CalRange range;
  final bool canMore;
  final VoidCallback onMore;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final locale = Localizations.localeOf(context).toString();
    final on = ref.watch(calLayersProvider);
    final start = parseDay(range.from);
    final end = parseDay(range.to);
    final days = calendarDaysBetween(start, end) + 1;
    final weekEnd = addDaysTo(manilaToday(), 7);
    final due = <CalItem>[
      for (final i in range.items)
        if (on.contains(i.layer) &&
            i.kind == 'bill' &&
            !i.paid &&
            i.endDate.compareTo(weekEnd) <= 0)
          i,
    ];
    final rows = <Widget>[];
    for (var n = 0; n < days; n++) {
      final d = DateTime(start.year, start.month, start.day + n);
      // A window shows on the first day of the list it falls in, not on every day
      final items = <CalItem>[
        for (final i in _visible(range, on, dayOf(d)))
          if (!i.isWindow || i.date == dayOf(d) || n == 0) i,
      ];
      if (items.isEmpty) continue;
      rows
        ..add(SectionTitle(DateFormat.MMMEd(locale).format(d)))
        ..addAll(<Widget>[
          for (final i in items)
            ItemRow(i, day: dayOf(d), onChanged: onChanged),
        ]);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: <Widget>[
        if (due.isNotEmpty) ...<Widget>[
          SectionTitle(t.calAgendaDueThisWeek),
          for (final i in due) ItemRow(i, day: i.endDate, onChanged: onChanged),
        ],
        if (rows.isEmpty) Note(t.calAgendaEmpty) else ...rows,
        if (canMore)
          TextButton(onPressed: onMore, child: Text(t.calAgendaMore)),
      ],
    );
  }
}
