// THE PIECES OF THE BILLS LIST: A MONTH HEADER, A ROW FOR A DUE DATE AND A ROW FOR A BILL. EACH ROW OPENS THE BILL SHEET WHEN TAPPED.
// A due row keeps "Mark paid" as its own 48 dp button beside the tappable body, so paying and editing never compete for the same tap.

// -- DEP-MODULES -- //

import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/marks.dart';
import '../../core/money_scope.dart';
import '../../core/schedule_text.dart';
import '../../l10n/l10n.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/mark_badge.dart';
import '../../ui/skeleton.dart';
import '../../core/clock.dart';

// -- CONSTANTS -- //

const Size _tap = Size(48, 48);

// -- FUNCTIONS -- //

String _locale(BuildContext context) =>
    Localizations.localeOf(context).toString();

/// A date as "Sun, Oct 25" in the app's language. Text that is not a date is shown as it is.
String niceDate(BuildContext context, String iso) {
  final d = dayOf(iso);
  return d == null ? iso : fmtDate(d, DateKind.monthDayWeekday);
}

/// What a due row says about when: the window when a bill can be paid over several days, else the day.
String _when(BuildContext context, Json d) {
  final start = str(d['windowStart']);
  final end = str(d['windowEnd']);
  final text = start.isNotEmpty && start != end
      ? context.t.schedPayWindow(
          niceDate(context, start),
          niceDate(context, end),
        )
      // The date tile already shows the day and month, so a single day is just its weekday
      : (dayOf(str(d['dueDate'])) == null
            ? str(d['dueDate'])
            : fmtWeekday(dayOf(str(d['dueDate']))!, long: true));
  return boolOf(d['overridden']) &&
          str(d['originalDueDate']) != str(d['dueDate'])
      ? '$text · ${context.t.billsMovedTag}'
      : text;
}

/// An amount in the bill's own currency, and in brackets what it comes to in the main currency at the latest rate. A bill in the main
/// currency is just its amount; a bill whose currency has no rate yet says so instead of showing a made-up value.
String billAmountText(
  BuildContext context,
  int amount,
  String currency,
  Object? inMain, {
  bool missingRate = false,
}) {
  final own = context.moneyIn(amount, currency);
  if (currency == context.currencyCode) return own;
  if (missingRate || inMain is! num) {
    return '$own (${context.t.billsMissingRateTag})';
  }
  return '$own (${context.t.billsAboutMain(context.moneyMain(inMain.toInt()))})';
}

/// What a due row costs: the amount, or a question mark when a bill that varies has none yet.
String _cost(BuildContext context, Json d) => boolOf(d['unknownAmount'])
    ? context.t.billsAmountUnknown
    : billAmountText(
        context,
        intOf(d['amount']),
        str(d['currency'], context.currencyCode),
        d['amountMain'],
        missingRate: boolOf(d['missingRate']),
      );

/// What a bill is expected to cost and how it repeats, in one line.
String describeBill(BuildContext context, Json b) {
  final t = context.t;
  final est = asJson(b['estimate']);
  final shown = est['amount'] == null
      ? ''
      : billAmountText(
          context,
          intOf(est['amount']),
          str(b['currency'], context.currencyCode),
          b['estimateMain'],
          missingRate:
              b['estimateMain'] == null &&
              str(b['currency'], context.currencyCode) != context.currencyCode,
        );
  final amount = est['amount'] == null
      ? t.billsAmountNotKnown
      : (str(b['kind']) == 'variable' ? t.billsUsualSuffix(shown) : shown);
  // The schedule is read back as a sentence on the phone; a kind this version does not know is said plainly
  final when =
      describeSchedule(t, _locale(context), asJson(b['schedule'])) ??
      t.schedUnknown;
  return '$amount · $when${str(b['category']) == 'parents' ? ' · ${t.billsParentsTag}' : ''}';
}

// -- TYPES -- //

/// "October 2026", "Oct 26 – Nov 1" or "Overdue", with how many bills it holds: plain muted words, no rule.
class MonthHeader extends StatelessWidget {
  const MonthHeader({required this.month, this.count, super.key});

  /// yyyy-MM for a month, yyyy-MM-dd (its first day) for a week, or an empty text for the late bills.
  final String month;

  /// How many bills are under it, shown after the name when given.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final late = month.isEmpty;
    final week = month.length == 10;
    final day = late ? null : dayOf(week ? month : '$month-01');
    final label = late || day == null
        ? context.t.billsOverdue
        : week
        ? '${fmtDate(day, DateKind.monthDay)} – ${fmtDate(DateTime(day.year, day.month, day.day + 6), DateKind.monthDay)}'
        : fmtDate(day, DateKind.monthYear);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(
          count == null ? label : '$label · $count',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: late ? c.warning : c.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// One due date, always the same shape: the name (two lines at most) over the amount and weekday, with "Mark paid" or the paid tick at the
/// end, all centred on the row. The body opens the bill sheet; the text button pays it.
class DueRow extends StatelessWidget {
  const DueRow({
    required this.due,
    required this.onEdit,
    required this.onPay,
    this.overdue = false,
    this.mark = const Mark(),
    super.key,
  });

  final Json due;

  /// The row sits in the late group (from the grouping, not worked out again here).
  final bool overdue;

  /// The mark of the bill (its own, or its account's): its logo, icon or first letter, before the name.
  final Mark mark;
  final VoidCallback onEdit;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final paid = boolOf(due['paid']);
    final name = str(due['name']);
    final when = _when(context, due);
    final cost = _cost(context, due);
    final day = dayOf(str(due['dueDate']));
    final tone = paid ? c.success : (overdue ? c.warning : c.ink);
    final text = Theme.of(context).textTheme;
    final costStyle = text.bodyMedium?.copyWith(
      fontFeatures: tabular,
      fontWeight: FontWeight.w500,
    );
    final label = overdue && !paid
        ? '$name, ${t.billsOverdue}, $when, $cost'
        : '$name, $when, $cost';
    // The day and month, plain: warning when late, success when paid
    final dayCell = SizedBox(
      width: 36,
      child: day == null
          ? null
          : Column(
              children: <Widget>[
                Text(
                  '${day.day}',
                  style: text.titleMedium?.copyWith(
                    color: tone,
                    fontFeatures: tabular,
                  ),
                ),
                Text(
                  fmtMonth(day),
                  style: text.labelSmall?.copyWith(color: c.muted),
                ),
              ],
            ),
    );
    // The action column has one width, so "Mark paid" and the paid tick end on the same edge in every row
    final action = SizedBox(
      width: 112,
      child: Align(
        alignment: Alignment.centerRight,
        child: paid
            ? Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.check, size: 16, color: c.success),
                    const SizedBox(width: 4),
                    Text(t.billsPaid, style: TextStyle(color: c.success)),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Semantics(
                  button: true,
                  label: t.billsMarkPaidFor(name),
                  excludeSemantics: true,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: onPay,
                    child: Text(t.billsMarkPaid),
                  ),
                ),
              ),
      ),
    );
    // One shape for every row: name over amount and weekday, the action at the end, all centred on the row
    return Row(
      children: <Widget>[
        Expanded(
          child: Semantics(
            button: true,
            label: label,
            hint: t.billsEditHint,
            excludeSemantics: true,
            child: InkWell(
              onTap: onEdit,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: _tap.height + 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  child: Row(
                    children: <Widget>[
                      dayCell,
                      const SizedBox(width: 12),
                      MarkBadge(name: name, mark: mark, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Wrap(
                              spacing: 8,
                              runSpacing: 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: <Widget>[
                                Text(cost, style: costStyle),
                                Text(
                                  when,
                                  style: text.bodySmall?.copyWith(
                                    color: c.muted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        action,
      ],
    );
  }
}

/// The loading look of the due list: a group header and one card of rows shaped like [DueRow] (day, logo, name over amount, action), so
/// nothing jumps when the bills arrive.
class DueSkeleton extends StatelessWidget {
  const DueSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 20, 4, 8),
            child: Skeleton(width: 120, height: 12),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                for (var i = 0; i < 4; i++) ...<Widget>[
                  if (i > 0) const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: SizedBox(
                      height: _tap.height + 8 - 20,
                      child: const Row(
                        children: <Widget>[
                          SizedBox(width: 36, child: Skeleton(height: 28)),
                          SizedBox(width: 12),
                          Skeleton(width: 36, height: 36, radius: 10),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Skeleton(width: 150, height: 14),
                                SizedBox(height: 6),
                                Skeleton(width: 100, height: 12),
                              ],
                            ),
                          ),
                          SizedBox(width: 12),
                          Skeleton(width: 80, height: 32, radius: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One bill in "All bills": tap to change it, the switch to turn it off or on. A bill that is off reads quieter.
class BillTile extends StatelessWidget {
  const BillTile({
    required this.bill,
    required this.onEdit,
    required this.onActive,
    this.mark = const Mark(),
    super.key,
  });

  final Json bill;

  /// The mark of the bill (its own, or its account's), drawn before the name.
  final Mark mark;
  final VoidCallback onEdit;
  final ValueChanged<bool> onActive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = boolOf(bill['active']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onEdit,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: _tap.height),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: <Widget>[
                  MarkBadge(name: str(bill['name']), mark: mark),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          str(bill['name']),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: on ? c.ink : c.muted),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          describeBill(context, bill),
                          style: TextStyle(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    label: str(bill['name']),
                    child: Switch(value: on, onChanged: onActive),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
