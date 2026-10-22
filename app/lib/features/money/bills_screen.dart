// BILLS: WHAT IS COMING UP BY MONTH (TAP A ROW TO CHANGE IT, "MARK PAID" WHEN IT IS), THE LIST OF ALL BILLS WITH WHAT EACH IS EXPECTED TO COST, AND ADDING ONE.
// A bill whose amount varies learns its usual amount from what you pay; when it has no history yet you are asked for a starting estimate.
// The parents' share is just a bill marked as such, so the payday split sets it aside first.
// A row opens the bill sheet (bill_editor.dart): one date can be moved, skipped or given another amount or account, or the whole bill changed.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/manila.dart';
import '../../core/money.dart';
import '../../core/money_scope.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../ui/ui.dart';
import 'bill_editor.dart';
import 'bills_logic.dart';
import 'bills_parts.dart';

// -- CONSTANTS -- //

final FutureProvider<List<Json>> _billsProvider =
    FutureProvider.autoDispose<List<Json>>(
      (ref) => ref.watch(apiProvider).verbList('bills_list'),
    );

// Late bills from the last month, and what is due over the next four months
final FutureProvider<List<Json>> _dueProvider =
    FutureProvider.autoDispose<List<Json>>((ref) {
      final range = billsRange(manilaToday());
      return ref.watch(apiProvider).verbList('bills_due', <String, Object?>{
        'from': range.from,
        'to': range.to,
      });
    });

// -- TYPES -- //

class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref
      ..invalidate(_billsProvider)
      ..invalidate(_dueProvider)
      ..invalidate(balancesProvider)
      ..invalidate(syncProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(_billsProvider);
    final due = ref.watch(_dueProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t.billsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SectionTitle(context.t.billsComingUp),
          AsyncBody<List<Json>>(
            value: due,
            onRetry: () => ref.invalidate(_dueProvider),
            data: (list) {
              final groups = groupDue(list, manilaToday());
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (!anyUnpaid(groups)) Note(context.t.billsNothingDue),
                  for (final g in groups) ...<Widget>[
                    MonthHeader(month: g.month),
                    for (final d in g.rows)
                      DueRow(
                        due: d,
                        onEdit: () => _editDate(context, ref, d),
                        onPay: () => _pay(context, ref, d),
                      ),
                  ],
                ],
              );
            },
          ),
          SectionTitle(context.t.billsAll),
          AsyncBody<List<Json>>(
            value: bills,
            onRetry: () => ref.invalidate(_billsProvider),
            data: (list) => Column(
              children: <Widget>[
                if (list.isEmpty) Note(context.t.billsEmpty),
                for (final b in list)
                  BillTile(
                    bill: b,
                    onEdit: () => _editBill(context, ref, b),
                    onActive: (on) => _setActive(context, ref, b, on),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _add(context, ref),
            icon: const Icon(Icons.add),
            label: Text(context.t.billsAdd),
          ),
        ],
      ),
    );
  }

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    Json bill,
    bool on,
  ) async {
    try {
      await ref.read(apiProvider).verb('bill_update', <String, Object?>{
        'billId': str(bill['id']),
        'active': on,
      });
      _refresh(ref);
    } catch (e) {
      if (context.mounted) say(context, errorWords(e, context));
    }
  }

  /// Shows what the sheet answered (saved, skipped...) and reloads the lists.
  void _done(BuildContext context, WidgetRef ref, String? message) {
    if (message == null) return;
    if (context.mounted) say(context, message);
    _refresh(ref);
  }

  /// A tap on a due date: its own changes while it is not paid, the whole bill once it is.
  Future<void> _editDate(BuildContext context, WidgetRef ref, Json due) async {
    final bill = await _billOf(ref, str(due['billId']));
    if (bill == null || !context.mounted) return;
    final message = await showBillEditor(context, bill: bill, due: due);
    if (context.mounted) _done(context, ref, message);
  }

  Future<void> _editBill(BuildContext context, WidgetRef ref, Json bill) async {
    final message = await showBillEditor(context, bill: bill);
    if (context.mounted) _done(context, ref, message);
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final message = await showBillEditor(context);
    if (context.mounted) _done(context, ref, message);
  }

  /// The bill a due date belongs to, from the list of bills.
  Future<Json?> _billOf(WidgetRef ref, String id) async {
    final all = await ref.read(_billsProvider.future);
    for (final b in all) {
      if (str(b['id']) == id) return b;
    }
    return null;
  }

  Future<void> _pay(BuildContext context, WidgetRef ref, Json due) async {
    final amount = TextEditingController(
      text: boolOf(due['unknownAmount'])
          ? ''
          : context.plainAmount(intOf(due['amount'])),
    );
    final result = await showFormSheet<String>(
      context,
      title: context.t.billsPaidTitle(str(due['name'])),
      builder: (sheet, close) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Field(
            controller: amount,
            label: sheet.t.billsPayLabel(sheet.currencyCode),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          FilledButton(
            onPressed: () async {
              final code = context.currencyCode;
              final t = sheet.t;
              final cents = parseMoney(amount.text, code);
              if (cents == null || cents <= 0) {
                say(sheet, t.billsPayInvalid(code));
                return;
              }
              try {
                final r = asJson(
                  await ref.read(apiProvider).verb(
                    'bill_mark_paid',
                    <String, Object?>{
                      'billId': str(due['billId']),
                      'dueDate': str(due['dueDate']),
                      'amount': cents,
                    },
                  ),
                );
                final hint = r['savingsHint'];
                close(
                  hint is num
                      ? t.billsMarkedPaidHint(formatMoney(hint.toInt(), code))
                      : t.billsMarkedPaid,
                );
              } catch (e) {
                if (sheet.mounted) say(sheet, errorWords(e, context));
              }
            },
            child: Text(sheet.t.billsMarkPaid),
          ),
        ],
      ),
    );
    if (result != null) {
      if (context.mounted) say(context, result);
      _refresh(ref);
    }
  }
}
