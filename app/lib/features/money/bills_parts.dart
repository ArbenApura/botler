// THE PIECES OF THE BILLS LIST: A MONTH HEADER, A ROW FOR A DUE DATE AND A ROW FOR A BILL. EACH ROW OPENS THE BILL SHEET WHEN TAPPED.
// A due row keeps "Mark paid" as its own 48 dp button beside the tappable body, so paying and editing never compete for the same tap.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/manila.dart';
import '../../core/marks.dart';
import '../../core/money_scope.dart';
import '../../core/schedule_text.dart';
import '../../l10n/l10n.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/mark_badge.dart';
import 'money_parts.dart';

// -- CONSTANTS -- //

const Size _tap = Size(48, 48);

// -- FUNCTIONS -- //

String _locale(BuildContext context) =>
    Localizations.localeOf(context).toString();

/// A date as "Sun, Oct 25" in the app's language. Text that is not a date is shown as it is.
String niceDate(BuildContext context, String iso) {
  final d = dayOf(iso);
  return d == null ? iso : DateFormat('EEE, MMM d', _locale(context)).format(d);
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
      : niceDate(context, str(d['dueDate']));
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

/// "October 2026", or "Overdue" for the late bills, with a rule that runs to the edge.
class MonthHeader extends StatelessWidget {
  const MonthHeader({required this.month, super.key});

  /// yyyy-MM, or an empty text for the late bills.
  final String month;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final late = month.isEmpty;
    // A month is yyyy-MM; a week is its first day, yyyy-MM-dd, and reads as "Oct 26 – Nov 1"
    final week = month.length == 10;
    final day = late ? null : dayOf(week ? month : '$month-01');
    final loc = _locale(context);
    final label = late || day == null
        ? context.t.billsOverdue
        : week
        ? '${DateFormat.MMMd(loc).format(day)} – ${DateFormat.MMMd(loc).format(DateTime(day.year, day.month, day.day + 6))}'
        : DateFormat.yMMMM(loc).format(day);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(
          children: <Widget>[
            if (late) ...<Widget>[
              Icon(Icons.schedule, size: 18, color: c.warning),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: late ? c.warning : c.ink),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Divider()),
          ],
        ),
      ),
    );
  }
}

/// The day and month of a due date in a small tinted square: warning when late, success when paid, quiet otherwise.
class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.iso, required this.tint});

  final String iso;

  /// The status colour, or null for an ordinary due date.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = dayOf(iso);
    if (d == null) return const SizedBox(width: 8);
    final ink = tint ?? c.ink;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 48),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tint == null ? c.chip : tint!.withValues(alpha: tintAlpha),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '${d.day}',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: ink, fontFeatures: tabular),
              ),
              Text(
                DateFormat.MMM(_locale(context)).format(d),
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: tint ?? c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One due date: tap the body to change it, or the button to mark it paid.
class DueRow extends StatelessWidget {
  const DueRow({
    required this.due,
    required this.onEdit,
    required this.onPay,
    this.mark = const Mark(),
    this.overdue = false,
    super.key,
  });

  final Json due;

  /// The mark of the bill (its own, or its account's), drawn before the name.
  final Mark mark;

  /// The row sits in the late group (from the grouping, not worked out again here).
  final bool overdue;
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
    final tint = paid ? c.success : (overdue ? c.warning : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Semantics(
                button: true,
                label: overdue && !paid
                    ? '$name, ${t.billsOverdue}, $when, $cost'
                    : '$name, $when, $cost',
                hint: t.billsEditHint,
                excludeSemantics: true,
                child: InkWell(
                  onTap: onEdit,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: _tap.height),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _DateBlock(iso: str(due['dueDate']), tint: tint),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    MarkBadge(name: name, mark: mark, size: 22),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(when, style: TextStyle(color: c.muted)),
                                const SizedBox(height: 2),
                                Text(
                                  cost,
                                  style: const TextStyle(fontFeatures: tabular),
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
            if (paid)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.check_circle, size: 18, color: c.success),
                    const SizedBox(width: 4),
                    Text(t.billsPaid, style: TextStyle(color: c.success)),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Semantics(
                  button: true,
                  label: t.billsMarkPaidFor(name),
                  excludeSemantics: true,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: _tap,
                      backgroundColor: c.accentSoft,
                      foregroundColor: c.accentText,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: onPay,
                    child: Text(t.billsMarkPaid),
                  ),
                ),
              ),
          ],
        ),
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
