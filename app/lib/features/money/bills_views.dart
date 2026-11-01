// THE WEEK AND MONTH VIEWS OF THE BILLS SCREEN, AND THE SWITCH THAT CHOOSES BETWEEN THEM AND THE LIST.
// Both read the due dates the screen already loaded, so paying or changing a bill works the same here. A day with bills carries small marks: a warning mark when
// one is overdue, a success mark when all are paid. Dates are text (yyyy-MM-dd) from Manila's calendar. The loaded range is limited, so going past it is not offered.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/manila.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../calendar/calendar_data.dart' show parseDay, weekStart;

// -- CONSTANTS -- //

/// The shape of the bills screen.
enum BillsView { list, week, month }

/// The cells are at least this tall (a 48 dp target).
const double _cell = 52;

/// Most marks drawn under a day.
const int _maxMarks = 3;

// -- FUNCTIONS -- //

String _locale(BuildContext context) =>
    Localizations.localeOf(context).toString();

/// The due dates that fall on [iso].
List<Json> _on(List<Json> dues, String iso) => <Json>[
  for (final d in dues)
    if (str(d['dueDate']) == iso) d,
];

// -- TYPES -- //

/// List, Week or Month: one segmented control, remembered by the screen.
class BillsViewSwitch extends StatelessWidget {
  const BillsViewSwitch({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final BillsView value;
  final ValueChanged<BillsView> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<BillsView>(
        showSelectedIcon: false,
        segments: <ButtonSegment<BillsView>>[
          ButtonSegment<BillsView>(
            value: BillsView.list,
            icon: const Icon(Icons.view_agenda_outlined, size: 18),
            label: Text(t.billsViewList),
          ),
          ButtonSegment<BillsView>(
            value: BillsView.week,
            icon: const Icon(Icons.view_week_outlined, size: 18),
            label: Text(t.billsViewWeek),
          ),
          ButtonSegment<BillsView>(
            value: BillsView.month,
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: Text(t.billsViewMonth),
          ),
        ],
        selected: <BillsView>{value},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

/// The week strip or the month grid with the bills of the picked day under it.
class BillsCalendar extends StatefulWidget {
  const BillsCalendar({
    required this.month,
    required this.dues,
    required this.today,
    required this.from,
    required this.to,
    required this.startsOn,
    required this.rowBuilder,
    super.key,
  });

  /// Month grid when true, a week strip when false.
  final bool month;

  /// Every due date loaded (late ones, paid ones and the coming ones).
  final List<Json> dues;
  final String today;

  /// The first and last date the screen loaded: navigation stops there.
  final String from;
  final String to;

  /// The weekday a week starts on (0 Sunday, 1 Monday ...).
  final int startsOn;

  /// One due row, for the picked day. [overdue] is true for an unpaid date before today.
  final Widget Function(Json due, bool overdue) rowBuilder;

  @override
  State<BillsCalendar> createState() => _BillsCalendarState();
}

class _BillsCalendarState extends State<BillsCalendar> {
  // -- STATES -- //

  late String _picked = widget.today;

  // -- FUNCTIONS -- //

  DateTime get _focus => parseDay(_picked);

  /// The first day shown: the week's first day, or the first of the grid's first week.
  DateTime _start() => widget.month
      ? weekStart(DateTime(_focus.year, _focus.month), widget.startsOn)
      : weekStart(_focus, widget.startsOn);

  void _shift(int steps) {
    final f = _focus;
    final DateTime next = widget.month
        ? DateTime(f.year, f.month + steps, 1)
        : DateTime(f.year, f.month, f.day + 7 * steps);
    // A new month opens on today when it is the current one, else on its first day
    final iso = isoOf(next);
    setState(
      () => _picked =
          widget.month && iso.substring(0, 7) == widget.today.substring(0, 7)
          ? widget.today
          : iso,
    );
  }

  bool _canGo(int steps) {
    final f = _focus;
    if (widget.month) {
      final m = DateTime(f.year, f.month + steps);
      final first = isoOf(DateTime(m.year, m.month, 1));
      final last = isoOf(DateTime(m.year, m.month + 1, 0));
      return last.compareTo(widget.from) >= 0 &&
          first.compareTo(widget.to) <= 0;
    }
    final s = weekStart(f, widget.startsOn);
    final first = isoOf(DateTime(s.year, s.month, s.day + 7 * steps));
    final last = isoOf(DateTime(s.year, s.month, s.day + 7 * steps + 6));
    return last.compareTo(widget.from) >= 0 && first.compareTo(widget.to) <= 0;
  }

  String _title(BuildContext context) {
    final loc = _locale(context);
    if (widget.month) return DateFormat.yMMMM(loc).format(_focus);
    final s = _start();
    final e = DateTime(s.year, s.month, s.day + 6);
    return '${DateFormat.MMMd(loc).format(s)} – ${DateFormat.MMMd(loc).format(e)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final loc = _locale(context);
    final start = _start();
    final weeks = widget.month ? 6 : 1;
    final shownMonth = _focus.month;
    final picked = _on(widget.dues, _picked);
    final overdueDay = _picked.compareTo(widget.today) < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(
              tooltip: widget.month ? t.billsPrevMonth : t.billsPrevWeek,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: _canGo(-1) ? () => _shift(-1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  _title(context),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            IconButton(
              tooltip: widget.month ? t.billsNextMonth : t.billsNextWeek,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: _canGo(1) ? () => _shift(1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        // The weekday names, in the week's own order
        Row(
          children: <Widget>[
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    DateFormat.E(
                      loc,
                    ).format(DateTime(start.year, start.month, start.day + i)),
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: c.muted),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var w = 0; w < weeks; w++)
          Row(
            children: <Widget>[
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: _Day(
                    iso: isoOf(
                      DateTime(start.year, start.month, start.day + w * 7 + i),
                    ),
                    today: widget.today,
                    picked: _picked,
                    dimmed:
                        widget.month &&
                        DateTime(
                              start.year,
                              start.month,
                              start.day + w * 7 + i,
                            ).month !=
                            shownMonth,
                    dues: widget.dues,
                    onTap: (iso) => setState(() => _picked = iso),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Text(
            DateFormat.yMMMEd(loc).format(_focus),
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: c.muted),
          ),
        ),
        if (picked.isEmpty)
          Note(t.billsDayEmpty)
        else
          for (final d in picked)
            widget.rowBuilder(d, overdueDay && !boolOf(d['paid'])),
      ],
    );
  }
}

/// One day of the strip or the grid: its number, a ring when it is today, filled when picked, and its marks.
class _Day extends StatelessWidget {
  const _Day({
    required this.iso,
    required this.today,
    required this.picked,
    required this.dimmed,
    required this.dues,
    required this.onTap,
  });

  final String iso;
  final String today;
  final String picked;
  final bool dimmed;
  final List<Json> dues;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final day = parseDay(iso);
    final rows = _on(dues, iso);
    final isPicked = iso == picked;
    final isToday = iso == today;
    final label = context.t.billsDayLabel(
      DateFormat.yMMMEd(_locale(context)).format(day),
      rows.length,
    );
    // Marks: overdue first, then paid, then the rest
    final marks = <Color>[
      for (final d in rows)
        if (!boolOf(d['paid']) && iso.compareTo(today) < 0)
          c.warning
        else if (boolOf(d['paid']))
          c.success
        else
          c.accentText,
    ].take(_maxMarks).toList();
    return Semantics(
      button: true,
      selected: isPicked,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onTap(iso),
        child: SizedBox(
          height: _cell,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isPicked ? c.accent : null,
                  border: isToday && !isPicked
                      ? Border.all(color: c.accent, width: 1.5)
                      : null,
                ),
                child: SizedBox.square(
                  dimension: 34,
                  child: Center(
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                        color: isPicked
                            ? c.onAccent
                            : (dimmed ? c.muted.withValues(alpha: 0.5) : c.ink),
                        fontWeight: isToday ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final m in marks)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: SizedBox.square(
                          dimension: 5,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: m,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
