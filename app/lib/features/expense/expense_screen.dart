// ADD AN EXPENSE YOURSELF: THE AMOUNT, WHERE IT CAME FROM, AN OPTIONAL NOTE. IT WORKS WITH NO CONNECTION AND WHEN THE ASSISTANT IS DOWN OR OVER ITS CAP.
// Written down on the phone first if the server cannot be reached, with the request id it already used, so it lands exactly once when the phone is back online.
// This is also where the home screen widget leads (botler://quickadd).

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/money_scope.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- CONSTANTS -- //

const String _lastAccountKey = 'expense.last_account';

// -- TYPES -- //

class ExpenseScreen extends ConsumerStatefulWidget {
  const ExpenseScreen({this.amount, this.note, super.key});

  /// Filled in when fixing an entry.
  final String? amount;
  final String? note;

  @override
  ConsumerState<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends ConsumerState<ExpenseScreen> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.amount,
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.note,
  );
  String? _accountId;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Back to where the person came from; the home screen when this was the first screen (the widget opens it directly).
  void _close() => context.canPop() ? context.pop() : context.go('/');

  Future<void> _save(String id) async {
    final cents = context.parseAmount(_amount.text);
    if (cents == null || cents <= 0) {
      say(context, context.t.expenseAmountError(context.currencyCode));
      return;
    }
    if (id.isEmpty) {
      say(context, context.t.expensePickAccount);
      return;
    }
    setState(() => _busy = true);
    final args = <String, Object?>{
      'accountId': id,
      'amount': cents,
      'note': _note.text.trim(),
      'source': 'manual',
    };
    final key = newRequestId();
    final prefs = ref.read(prefsProvider);
    try {
      await ref.read(apiProvider).verb('expense_log', args, key);
      await prefs.setString(_lastAccountKey, id);
      ref
        ..invalidate(balancesProvider)
        ..invalidate(syncProvider);
      if (!mounted) return;
      say(context, context.t.expenseLogged(context.money(cents)));
      _close();
    } on ApiException catch (e) {
      if (e.isNetwork) {
        // Kept on the phone under the same id: if the first try did arrive, the server knows the id and does not double it
        await ref.read(outboxProvider).add('expense_log', args, key: key);
        ref.read(outboxCountProvider.notifier).refresh();
        if (!mounted) return;
        say(context, context.t.expenseOffline);
        _close();
      } else if (mounted) {
        say(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(balancesProvider);
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text(context.t.expenseTitle)),
      body: AsyncBody<List<Json>>(
        value: accounts,
        skeleton: const SkeletonPage(
          padding: EdgeInsets.all(20),
          child: SkeletonRows(count: 3, kind: SkeletonKind.form),
        ),
        onRetry: () => ref.invalidate(balancesProvider),
        data: (list) {
          final last = ref.read(prefsProvider).getString(_lastAccountKey);
          final selected =
              _accountId ??
              (list.any((a) => str(a['id']) == last)
                  ? (last ?? '')
                  : str(list.firstOrNull?['id']));
          return ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              Field(
                controller: _amount,
                label: context.t.expenseHowMuch(context.currencyCode),
                hint: '180',
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              Text(
                context.t.expenseFromAccount,
                style: TextStyle(color: c.muted),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  for (final a in list)
                    ChoiceChip(
                      label: Text(str(a['name'])),
                      selected: str(a['id']) == selected,
                      onSelected: (_) =>
                          setState(() => _accountId = str(a['id'])),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Field(
                controller: _note,
                label: context.t.expenseNoteLabel,
                hint: context.t.expenseNoteHint,
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : () => _save(selected),
                child: Text(context.t.expenseLogIt),
              ),
            ],
          );
        },
      ),
    );
  }
}
