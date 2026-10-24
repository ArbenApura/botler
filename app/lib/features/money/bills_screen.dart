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
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'bill_editor.dart';
import 'bills_logic.dart';
import 'accounts_screen.dart' show hasWalletIn, walletsOf;
import 'bills_parts.dart';

// -- CONSTANTS -- //

final FutureProvider<List<Json>> _billsProvider =
    FutureProvider.autoDispose<List<Json>>(
      (ref) => ref.watch(apiProvider).verbList('bills_list'),
    );

// Late bills from the last month, and what is due over the next four months
final FutureProvider<List<Json>> _dueProvider =
    FutureProvider.autoDispose<List<Json>>((ref) async {
      final range = billsRange(manilaToday());
      final api = ref.watch(apiProvider);
      // Both are asked together, so the list never flashes months a new bill never owed
      final results = await Future.wait<List<Json>>(<Future<List<Json>>>[
        api.verbList('bills_due', <String, Object?>{
          'from': range.from,
          'to': range.to,
        }),
        ref.watch(_billsProvider.future),
      ]);
      return withoutBeforeAdded(results[0], results[1]);
    });

// -- TYPES -- //

class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref
      ..invalidate(_billsProvider)
      ..invalidate(_dueProvider)
      ..invalidate(balancesProvider)
      ..invalidate(assetsProvider)
      ..invalidate(syncProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(_billsProvider);
    final due = ref.watch(_dueProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t.billsTitle)),
      body: ListView(
        padding: pagePadding(context),
        children: <Widget>[
          SectionTitle(context.t.billsComingUp),
          AsyncBody<List<Json>>(
            value: due,
            skeleton: const SkeletonRows(),
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
            skeleton: const SkeletonRows(),
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
    // The bill's amounts are in its own currency; the account it is paid from may hold others
    final billCode = str(due['currency'], context.currencyCode);
    final amount = TextEditingController(
      text: boolOf(due['unknownAmount'])
          ? ''
          : plainAmountIn(intOf(due['amount']), billCode),
    );
    final charged = TextEditingController();
    final accounts = ref.read(balancesProvider).value ?? <Json>[];
    var accountId = str(due['accountId']);
    // Paid in the bill's own currency when the account holds it, else in the account's own: never a new wallet by a plain tap
    String startIn(String id) {
      final a = accounts.firstWhere(
        (x) => str(x['id']) == id,
        orElse: () => <String, Object?>{},
      );
      if (a.isEmpty || hasWalletIn(a, billCode)) return billCode;
      return str(a['currency'], billCode);
    }

    var paidIn = startIn(accountId);
    final result = await showFormSheet<String>(
      context,
      title: context.t.billsPaidTitle(str(due['name'])),
      builder: (sheet, close) => StatefulBuilder(
        builder: (_, setState) {
          final account = accounts.firstWhere(
            (a) => str(a['id']) == accountId,
            orElse: () => <String, Object?>{},
          );
          final held = <String>[
            if (account.isNotEmpty)
              for (final w in walletsOf(account)) str(w['currency']),
          ];
          // The wallets to pay in: what the account holds, and the currency of the bill itself
          final options = <String>{billCode, ...held}.toList();
          final foreign = paidIn != billCode;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Field(
                controller: amount,
                label: sheet.t.billsPayLabel(billCode),
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              if (accounts.length > 1) ...<Widget>[
                Text(
                  sheet.t.billsPaidFrom,
                  style: TextStyle(color: sheet.colors.muted),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: <Widget>[
                    for (final a in accounts)
                      ChoiceChip(
                        label: Text(str(a['name'])),
                        selected: str(a['id']) == accountId,
                        onSelected: (_) => setState(() {
                          accountId = str(a['id']);
                          paidIn = startIn(accountId);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (options.length > 1) ...<Widget>[
                Text(
                  sheet.t.billsWalletLabel,
                  style: TextStyle(color: sheet.colors.muted),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: <Widget>[
                    for (final code in options)
                      ChoiceChip(
                        label: Text(code),
                        selected: code == paidIn,
                        onSelected: (_) => setState(() => paidIn = code),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (foreign) ...<Widget>[
                Field(
                  controller: charged,
                  label: sheet.t.billsChargedLabel(paidIn),
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                Text(
                  sheet.t.billsChargedNote(billCode, paidIn),
                  style: TextStyle(color: sheet.colors.muted),
                ),
                const SizedBox(height: 4),
                Text(
                  sheet.t.billsReserveNote,
                  style: TextStyle(color: sheet.colors.muted),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                onPressed: () async {
                  final t = sheet.t;
                  final cents = parseMoney(amount.text, billCode);
                  if (cents == null || cents <= 0) {
                    say(sheet, t.billsPayInvalid(billCode));
                    return;
                  }
                  final paid = foreign
                      ? parseMoney(charged.text, paidIn)
                      : null;
                  if (foreign && (paid == null || paid <= 0)) {
                    say(sheet, t.billsPayInvalid(paidIn));
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
                          if (accountId != str(due['accountId']))
                            'accountId': accountId,
                          if (foreign) 'paidCurrency': paidIn,
                          'paidAmount': ?paid,
                        },
                      ),
                    );
                    final hint = r['savingsHint'];
                    close(
                      hint is num
                          ? t.billsMarkedPaidHint(
                              formatMoney(hint.toInt(), billCode),
                            )
                          : t.billsMarkedPaid,
                    );
                  } catch (e) {
                    if (sheet.mounted) say(sheet, errorWords(e, context));
                  }
                },
                child: Text(sheet.t.billsMarkPaid),
              ),
            ],
          );
        },
      ),
    );
    if (result != null) {
      if (context.mounted) say(context, result);
      _refresh(ref);
    }
  }
}
