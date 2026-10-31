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

/// "October 2026", or "Overdue" for the late bills.
class MonthHeader extends StatelessWidget {
  const MonthHeader({required this.month, super.key});

  /// yyyy-MM, or an empty text for the late bills.
  final String month;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final late = month.isEmpty;
    final day = late ? null : dayOf('$month-01');
    final label = late || day == null
        ? context.t.billsOverdue
        : DateFormat.yMMMM(_locale(context)).format(day);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: late ? c.warning : c.ink),
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
    super.key,
  });

  final Json due;

  /// The mark of the bill (its own, or its account's), drawn before the name.
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
                label: '$name, $when, $cost',
                hint: t.billsEditHint,
                excludeSemantics: true,
                child: InkWell(
                  onTap: onEdit,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: _tap.height),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        children: <Widget>[
                          MarkBadge(name: name, mark: mark, size: 36),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(when, style: TextStyle(color: c.muted)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              cost,
                              textAlign: TextAlign.end,
                              style: const TextStyle(fontFeatures: tabular),
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
                    Icon(Icons.check, size: 18, color: c.muted),
                    const SizedBox(width: 4),
                    Text(t.billsPaid, style: TextStyle(color: c.muted)),
                  ],
                ),
              )
            else
              Semantics(
                button: true,
                label: t.billsMarkPaidFor(name),
                excludeSemantics: true,
                child: TextButton(
                  style: TextButton.styleFrom(minimumSize: _tap),
                  onPressed: onPay,
                  child: Text(t.billsMarkPaid),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One bill in "All bills": tap to change it, the switch to turn it off or on.
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: _tap.height,
      leading: MarkBadge(name: str(bill['name']), mark: mark),
      title: Text(str(bill['name'])),
      subtitle: Text(
        describeBill(context, bill),
        style: TextStyle(color: c.muted),
      ),
      onTap: onEdit,
      trailing: Semantics(
        label: str(bill['name']),
        child: Switch(value: boolOf(bill['active']), onChanged: onActive),
      ),
    );
  }
}
