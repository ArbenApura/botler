// THE CALENDAR'S SMALL PIECES: THE MARKS ON A DAY, THE CASH-FLOW STRIP, THE DAY SHEET AND THE QUICK ADD.
// A mark's shape says what it is, so the grid reads without colour alone: a ring is a bill, an arrow a payday, a dot an event, a tick a routine,
// a square a task, a bar a reminder. Overdue is a danger ring and paid is a tick inside. Every colour comes from the tokens.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/money_scope.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/manila_clock.dart';
import '../../ui/ui.dart';
import 'calendar_data.dart';
import '../../core/clock.dart' show DateKind, fmtDate, fmtTime, fmtTimeOfDay;

// -- CONSTANTS -- //

/// The due dates marked paid while offline and not yet sent ("billId:dueDate"). The row shows them as paid at once and, living here, keeps doing
/// so when the day sheet is rebuilt before the outbox has sent the payment.
final Set<String> _paidWhileOffline = <String>{};

// -- FUNCTIONS -- //

/// The words for the things on a day, such as "2 bills, 1 event", or "nothing planned".
String dayParts(BuildContext context, List<CalItem> items) {
  final t = context.t;
  int n(CalLayer l) => items.where((i) => i.layer == l).length;
  final parts = <String>[
    if (n(CalLayer.bills) > 0) t.calCountBills(n(CalLayer.bills)),
    if (n(CalLayer.paydays) > 0) t.calCountPaydays(n(CalLayer.paydays)),
    if (n(CalLayer.events) > 0) t.calCountEvents(n(CalLayer.events)),
    if (n(CalLayer.routines) > 0) t.calCountRoutines(n(CalLayer.routines)),
    if (n(CalLayer.tasks) > 0) t.calCountTasks(n(CalLayer.tasks)),
    if (n(CalLayer.workouts) > 0) t.calCountWorkouts(n(CalLayer.workouts)),
    if (n(CalLayer.reminders) > 0) t.calCountReminders(n(CalLayer.reminders)),
  ];
  return parts.isEmpty ? t.calDayNothing : parts.join(', ');
}

String layerName(BuildContext context, CalLayer l) => switch (l) {
  CalLayer.bills => context.t.calLayerBills,
  CalLayer.paydays => context.t.calLayerPaydays,
  CalLayer.events => context.t.calLayerEvents,
  CalLayer.routines => context.t.calLayerRoutines,
  CalLayer.tasks => context.t.calLayerTasks,
  CalLayer.reminders => context.t.calLayerReminders,
  CalLayer.workouts => context.t.calLayerWorkouts,
};

// -- TYPES -- //

/// One mark: its shape, its colour and whether it is overdue or paid.
class _Mark extends CustomPainter {
  _Mark(
    this.kind,
    this.color, {
    required this.overdue,
    required this.paid,
    required this.ring,
  });

  final String kind;
  final Color color;
  final bool overdue;
  final bool paid;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final fill = Paint()..color = color;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    switch (kind) {
      case 'bill':
        canvas.drawCircle(c, r - 1, line);
        if (paid) canvas.drawCircle(c, r - 4, fill);
        if (overdue) {
          canvas.drawCircle(
            c,
            r + 1,
            Paint()
              ..color = ring
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6,
          );
        }
      case 'payday':
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - r)
            ..lineTo(c.dx + r, c.dy + r * 0.7)
            ..lineTo(c.dx - r, c.dy + r * 0.7)
            ..close(),
          fill,
        );
      case 'event':
        canvas.drawCircle(c, r * 0.75, fill);
      case 'routine':
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - r * 0.8, c.dy)
            ..lineTo(c.dx - r * 0.2, c.dy + r * 0.6)
            ..lineTo(c.dx + r * 0.8, c.dy - r * 0.6),
          line,
        );
      case 'task':
        canvas.drawRect(Rect.fromCircle(center: c, radius: r * 0.7), fill);
      case 'workout':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: r * 1.8, height: r),
            Radius.circular(r / 2),
          ),
          fill,
        );
      default:
        canvas.drawLine(
          Offset(c.dx - r * 0.8, c.dy),
          Offset(c.dx + r * 0.8, c.dy),
          line..strokeWidth = 2.4,
        );
    }
  }

  @override
  bool shouldRepaint(_Mark old) =>
      old.kind != kind ||
      old.color != color ||
      old.overdue != overdue ||
      old.paid != paid;
}

Color markColor(BotlerColors c, CalItem i) => switch (i.kind) {
  'bill' => i.overdue ? c.danger : (i.paid ? c.success : c.ink),
  'payday' => c.success,
  'event' => c.info,
  'routine' => c.accentText,
  'task' => c.warning,
  'workout' => c.accent,
  _ => c.muted,
};

/// A mark of [size] logical pixels for an item.
class MarkIcon extends StatelessWidget {
  const MarkIcon(this.item, {this.size = 10, super.key});

  final CalItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _Mark(
            item.kind,
            markColor(c, item),
            overdue: item.overdue,
            paid: item.paid,
            ring: c.danger,
          ),
        ),
      ),
    );
  }
}

// -- CASH FLOW -- //

/// The estimated money over the days, drawn as one soft line with the payday days and the low days marked. It always says it is an estimate.
class CashflowStrip extends StatelessWidget {
  const CashflowStrip({required this.range, super.key});

  final CalRange range;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final days = range.days;
    if (days.isEmpty) return PaperCard(child: Text(t.calForecastNone));
    final lows = <CalForecastDay>[
      for (final d in days)
        if (d.low.isNotEmpty) d,
    ];
    final first = lows.isEmpty ? null : lows.first;
    final lowText = first == null
        ? t.calForecastOk
        : t.calForecastLowDay(fmtDate(parseDay(first.date), DateKind.monthDay));
    final paydays = <String>{
      for (final i in range.items)
        if (i.kind == 'payday') i.date,
    };
    return Semantics(
      label: t.calForecastSemantics(
        fmtDate(parseDay(days.first.date), DateKind.monthDay),
        fmtDate(parseDay(days.last.date), DateKind.monthDay),
        lowText,
      ),
      child: PaperCard(
        // Opens time travel on the month of the strip (BTL-20261029-0117)
        onTap: () => context.push('/simulate?date=${days.first.date}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    t.calForecastTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: c.chip,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    t.calEstimate,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 72,
              child: ExcludeSemantics(
                child: CustomPaint(
                  size: const Size.fromHeight(72),
                  painter: _Line(
                    days: days,
                    paydays: paydays,
                    line: c.info,
                    grid: c.line,
                    pay: c.success,
                    low: c.warning,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Text(
                  t.calForecastTotal(context.moneyMain(days.last.total)),
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontFeatures: tabular),
                ),
                const Spacer(),
                Text(
                  lowText,
                  style: TextStyle(color: first == null ? c.muted : c.warning),
                ),
              ],
            ),
            if (first != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  t.calForecastLow(
                    first.low
                        .map((id) => range.accountNames[id] ?? '')
                        .where((n) => n.isNotEmpty)
                        .join(', '),
                  ),
                  style: TextStyle(color: c.muted),
                ),
              ),
            if (range.unknownBills > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  t.calForecastUnknown(range.unknownBills),
                  style: TextStyle(color: c.muted),
                ),
              ),
            if (range.unconvertedBills > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  t.calForecastUnconverted(range.unconvertedBills),
                  style: TextStyle(color: c.warning),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Line extends CustomPainter {
  _Line({
    required this.days,
    required this.paydays,
    required this.line,
    required this.grid,
    required this.pay,
    required this.low,
  });

  final List<CalForecastDay> days;
  final Set<String> paydays;
  final Color line;
  final Color grid;
  final Color pay;
  final Color low;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.length < 2) return;
    final totals = <int>[for (final d in days) d.total];
    var lo = totals.reduce((a, b) => a < b ? a : b);
    var hi = totals.reduce((a, b) => a > b ? a : b);
    if (hi == lo) {
      hi += 1;
      lo -= 1;
    }
    double x(int i) => size.width * i / (days.length - 1);
    double y(int v) =>
        size.height - 6 - (size.height - 12) * (v - lo) / (hi - lo);
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );
    final path = Path()..moveTo(x(0), y(totals[0]));
    for (var i = 1; i < days.length; i++) {
      // A step: the money holds until the day something happens to it
      path
        ..lineTo(x(i), y(totals[i - 1]))
        ..lineTo(x(i), y(totals[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < days.length; i++) {
      if (paydays.contains(days[i].date)) {
        canvas.drawCircle(Offset(x(i), y(totals[i])), 4, Paint()..color = pay);
      }
      if (days[i].low.isNotEmpty) {
        canvas.drawCircle(
          Offset(x(i), y(totals[i])),
          4,
          Paint()
            ..color = low
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Line old) => old.days != days || old.line != line;
}

// -- DAY SHEET -- //

/// One row for an item: its mark, its title, its detail line and, for an unpaid bill, the one button.
class ItemRow extends ConsumerStatefulWidget {
  const ItemRow(
    this.item, {
    required this.day,
    required this.onChanged,
    super.key,
  });

  final CalItem item;
  final String day;
  final VoidCallback onChanged;

  @override
  ConsumerState<ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends ConsumerState<ItemRow> {
  // -- STATES -- //
  // One key per mark-paid until it works (also the key of the outbox entry), and no second tap while one runs
  late final Once _once = Once(() {
    if (mounted) setState(() {});
  });

  CalItem get item => widget.item;
  VoidCallback get onChanged => widget.onChanged;

  String get _paidKey => '${item.id}:${item.endDate}';
  bool get _paid => item.paid || _paidWhileOffline.contains(_paidKey);

  String _detail(BuildContext context) {
    final t = context.t;
    final time = item.at.isEmpty || item.allDay
        ? null
        : fmtTime(manilaWall(dateOf(item.at) ?? DateTime.now().toUtc()));
    switch (item.kind) {
      case 'bill':
        final due = fmtDate(parseDay(item.endDate), DateKind.monthDay);
        final amount = item.amount == null || item.unknownAmount
            ? t.calAmountUnknown
            : item.currency.isEmpty
            ? context.moneyMain(item.amount ?? 0)
            : context.moneyIn(item.amount ?? 0, item.currency);
        final state = _paid
            ? t.calBillPaid
            : item.overdue
            ? t.calBillOverdue
            : item.isWindow
            ? t.calBillWindow(
                fmtDate(parseDay(item.date), DateKind.monthDay),
                due,
              )
            : t.calBillDue(due);
        return '$amount · $state';
      case 'payday':
        final amount = item.amount == null
            ? ''
            : '${context.moneyMain(item.amount ?? 0)} · ';
        return '$amount${item.paid ? t.calPaydaySplitDone : t.calPaydayLabel}';
      case 'event':
        return time ?? t.calAllDay;
      case 'routine':
        return <String>[t.calRoutineLabel, ?time].join(' · ');
      case 'task':
        return <String>[t.calTaskLabel, ?time].join(' · ');
      case 'workout':
        return <String>[t.calWorkoutLabel, ?time].join(' · ');
      default:
        return <String>[t.calReminderLabel, ?time].join(' · ');
    }
  }

  Future<void> _pay() async {
    final t = context.t;
    final amount = item.amount;
    // A bill with no amount yet, or in another currency, is paid from the bills screen: there the amount is typed, or the wallet and
    // what was really charged are asked
    if (amount == null ||
        item.unknownAmount ||
        (item.currency.isNotEmpty && item.currency != context.currencyCode)) {
      unawaited(context.push<void>('/bills'));
      return;
    }
    final ok = await confirm(
      context,
      title: t.calMarkPaidTitle(item.title),
      body: t.calMarkPaidBody(
        item.currency.isEmpty
            ? context.moneyMain(amount)
            : context.moneyIn(amount, item.currency),
      ),
      yes: t.calMarkPaid,
    );
    if (!ok || !context.mounted) return;
    final args = <String, Object?>{
      'billId': item.id,
      'dueDate': item.endDate,
      'amount': amount,
    };
    try {
      final ran = await _once.ok((key) async {
        try {
          await ref.read(apiProvider).verb('bill_mark_paid', args, key);
        } on ApiException catch (e) {
          if (e.code != 'NETWORK') rethrow;
          // No connection: the same request id goes into the outbox, so a replay returns the first result, and the row shows it as paid
          await ref.read(outboxProvider).add('bill_mark_paid', args, key: key);
          ref.read(outboxCountProvider.notifier).refresh();
          _paidWhileOffline.add(_paidKey);
        }
      }, intent: _paidKey);
      if (!ran) return;
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
      return;
    }
    if (!mounted) return;
    say(context, t.calPaidDone);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final detail = _detail(context);
    final payable = item.kind == 'bill' && !_paid;
    return Semantics(
      label: '${item.title}, $detail',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: <Widget>[
            SizedBox(width: 24, child: Center(child: MarkIcon(item, size: 14))),
            const SizedBox(width: 12),
            // The bill's (or the payday account's) own icon or picture, when it has one
            if (!item.mark.isEmpty) ...<Widget>[
              MarkBadge(name: item.title, mark: item.mark, size: 32),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    detail,
                    style: TextStyle(
                      color: item.overdue ? c.danger : c.muted,
                      fontFeatures: tabular,
                    ),
                  ),
                ],
              ),
            ),
            if (payable)
              TextButton(
                onPressed: _once.running() ? null : _pay,
                child: Text(context.t.calMarkPaid),
              ),
          ],
        ),
      ),
    );
  }
}

/// The sheet for one day: all-day things first, then the timed ones in order, then the quick add.
Future<void> showDaySheet(
  BuildContext context,
  WidgetRef ref, {
  required DateTime day,
  required List<CalItem> items,
  required VoidCallback onChanged,
}) {
  final key = dayOf(day);
  final allDay = <CalItem>[
    for (final i in items)
      if (i.at.isEmpty || i.allDay || i.kind == 'bill' || i.kind == 'payday') i,
  ];
  final timed = <CalItem>[
    for (final i in items)
      if (!allDay.contains(i)) i,
  ]..sort((a, b) => a.at.compareTo(b.at));
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.colors.paper,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: <Widget>[
          Text(
            fmtDate(day, DateKind.dateLongWeekday),
            style: Theme.of(sheet).textTheme.titleLarge,
          ),
          Text(
            dayParts(sheet, items),
            style: TextStyle(color: sheet.colors.muted),
          ),
          const SizedBox(height: 12),
          if (allDay.isNotEmpty) SectionTitle(sheet.t.calAllDay),
          for (final i in allDay)
            ItemRow(
              i,
              day: key,
              onChanged: () {
                Navigator.of(sheet).pop();
                onChanged();
              },
            ),
          if (timed.isNotEmpty) const SizedBox(height: 8),
          for (final i in timed)
            ItemRow(
              i,
              day: key,
              onChanged: () {
                Navigator.of(sheet).pop();
                onChanged();
              },
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(sheet).pop();
              showQuickAdd(context, ref, day: day, onChanged: onChanged);
            },
            icon: const Icon(Icons.add),
            label: Text(sheet.t.calAdd),
          ),
        ],
      ),
    ),
  );
}

// -- QUICK ADD -- //

/// Adds a bill (its own screen, where its schedule is set), an event, a task or a reminder on the chosen day.
Future<void> showQuickAdd(
  BuildContext context,
  WidgetRef ref, {
  required DateTime day,
  required VoidCallback onChanged,
}) async {
  final t = context.t;
  final kind = await showFormSheet<String>(
    context,
    title: t.calAddTitle(fmtDate(day, DateKind.monthDay)),
    builder: (sheet, close) => Column(
      children: <Widget>[
        for (final (k, label, icon) in <(String, String, IconData)>[
          ('bill', t.calAddBill, Icons.receipt_long_outlined),
          ('event', t.calAddEvent, Icons.event_outlined),
          ('task', t.calAddTask, Icons.check_box_outline_blank),
          ('reminder', t.calAddReminder, Icons.notifications_none),
        ])
          ListTile(
            minTileHeight: 48,
            leading: Icon(icon),
            title: Text(label),
            onTap: () => close(k),
          ),
      ],
    ),
  );
  if (kind == null || !context.mounted) return;
  if (kind == 'bill') {
    await context.push('/bills');
    onChanged();
    return;
  }
  var allDay = kind == 'event';
  var time = const TimeOfDay(hour: 9, minute: 0);
  final saved = await showFormSheet<bool>(
    context,
    title: switch (kind) {
      'event' => t.calAddEvent,
      'task' => t.calAddTask,
      _ => t.calAddReminder,
    },
    builder: (sheet, close) => SheetScope(
      builder: (_, sc) => StatefulBuilder(
        builder: (_, set) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: sc.c[0],
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: t.calWhatIsIt),
            ),
            const SizedBox(height: 8),
            if (kind == 'event')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.calAllDayToggle),
                value: allDay,
                onChanged: (v) => set(() => allDay = v),
              ),
            if (!allDay)
              ListTile(
                contentPadding: EdgeInsets.zero,
                minTileHeight: 48,
                title: Text(t.calTimeLabel),
                trailing: Text(fmtTimeOfDay(time)),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: sheet,
                    initialTime: time,
                  );
                  if (picked != null) set(() => time = picked);
                },
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: sc.once.running()
                  ? null
                  : () async {
                      final name = sc.c[0].text.trim();
                      if (name.isEmpty) {
                        say(sheet, t.calNeedTitle);
                        return;
                      }
                      // The picked day is a Manila calendar date and the time is Manila's clock, whatever zone the phone is in
                      final start = manilaInstant(
                        allDay
                            ? DateTime(day.year, day.month, day.day)
                            : DateTime(
                                day.year,
                                day.month,
                                day.day,
                                time.hour,
                                time.minute,
                              ),
                      );
                      final iso = start.toIso8601String();
                      final args = switch (kind) {
                        'event' => <String, Object?>{
                          'title': name,
                          'startsAt': iso,
                          'allDay': allDay,
                        },
                        'task' => <String, Object?>{
                          'title': name,
                          if (!allDay) 'dueAt': iso,
                        },
                        _ => <String, Object?>{'title': name, 'at': iso},
                      };
                      final verb = '${kind}_create';
                      try {
                        // The intent is the whole request: the same one again is the same key, a changed one is new
                        final ran = await sc.once.ok((key) async {
                          try {
                            await ref.read(apiProvider).verb(verb, args, key);
                          } on ApiException catch (e) {
                            if (e.code != 'NETWORK') rethrow;
                            await ref
                                .read(outboxProvider)
                                .add(verb, args, key: key);
                            ref.read(outboxCountProvider.notifier).refresh();
                          }
                        }, intent: '$verb:${jsonEncode(args)}');
                        if (!ran) return;
                      } catch (e) {
                        if (sheet.mounted) say(sheet, errorWords(e, sheet));
                        return;
                      }
                      close(true);
                    },
              child: Text(t.save),
            ),
          ],
        ),
      ),
    ),
  );
  if (saved == true) {
    if (context.mounted) say(context, t.calSaved);
    onChanged();
  }
}
