// ADD AN EXPENSE YOURSELF: THE AMOUNT, WHERE IT CAME FROM, AN OPTIONAL NOTE. IT WORKS WITH NO CONNECTION AND WHEN THE ASSISTANT IS DOWN OR OVER ITS CAP.
// Written down on the phone first if the server cannot be reached, with the request id it already used, so it lands exactly once when the phone is back online.
// This is also where the home screen widget leads (botler://quickadd).

// -- DEP-MODULES -- //
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/money_scope.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../money/accounts_screen.dart';
import '../money/currency_picker.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- CONSTANTS -- //

const String _lastAccountKey = 'expense.last_account';

// -- TYPES -- //

class ExpenseScreen extends ConsumerStatefulWidget {
  const ExpenseScreen({this.amount, this.note, this.currency, super.key});

  /// Filled in when fixing an entry.
  final String? amount;
  final String? note;

  /// The currency of the entry being fixed. Left out, the account's own.
  final String? currency;

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

  /// The wallet it is spent from. Null until picked: then the account's own currency.
  String? _currency;
  bool _busy = false;
  // One key per entry (the intent is the whole request): a second tap or a retry after a timeout is the same request
  final Once _once = Once();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Back to where the person came from; the home screen when this was the first screen (the widget opens it directly).
  /// Pops `true` when the entry reached the server, 'queued' when it waits in the outbox (the old entry of a fix then stays), false otherwise.
  void _close({bool saved = false, bool queued = false}) => context.canPop()
      ? context.pop<Object>(queued ? 'queued' : saved)
      : context.go('/');

  /// The currency of the entry: the one picked, else the one being fixed, else the account's own.
  String _code(Json? account) =>
      _currency ??
      widget.currency ??
      str(account?['currency'], context.currencyCode);

  Future<void> _save(String id, Json? account) async {
    if (_busy) return;
    final code = _code(account);
    final cents = context.parseAmountIn(_amount.text, code);
    if (cents == null || cents <= 0) {
      say(context, context.t.expenseAmountError(code));
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
      // Only when it is not the account's own currency, so an ordinary entry is the same request as before
      if (code != str(account?['currency'], context.currencyCode))
        'currency': code,
      'note': _note.text.trim(),
      'source': 'manual',
    };
    final intent = jsonEncode(args);
    final key = _once.key(intent);
    final prefs = ref.read(prefsProvider);
    try {
      await ref.read(apiProvider).verb('expense_log', args, key);
      _once.done(intent);
      await prefs.setString(_lastAccountKey, id);
      ref
        ..invalidate(balancesProvider)
        ..invalidate(assetsProvider)
        ..invalidate(syncProvider);
      if (!mounted) return;
      say(context, context.t.expenseLogged(context.moneyIn(cents, code)));
      _close(saved: true);
    } on ApiException catch (e) {
      if (e.isNetwork) {
        // Kept on the phone under the same id: if the first try did arrive, the server knows the id and does not double it
        await ref.read(outboxProvider).add('expense_log', args, key: key);
        ref.read(outboxCountProvider.notifier).refresh();
        if (!mounted) return;
        say(context, context.t.expenseOffline);
        _close(saved: true, queued: true);
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
          final account = list.firstWhere(
            (a) => str(a['id']) == selected,
            orElse: () => <String, Object?>{},
          );
          final code = _code(account.isEmpty ? null : account);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              Field(
                controller: _amount,
                label: context.t.expenseHowMuch(code),
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
                      avatar: AccountBadge(
                        accountId: str(a['id']),
                        name: str(a['name']),
                        size: 24,
                      ),
                      label: Text(str(a['name'])),
                      selected: str(a['id']) == selected,
                      onSelected: (_) => setState(() {
                        _accountId = str(a['id']);
                        // Another account starts again in its own currency
                        _currency = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // The wallets of the account, and any other currency (which opens a wallet)
              Text(
                context.t.entryCurrencyLabel,
                style: TextStyle(color: c.muted),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  for (final w
                      in account.isEmpty ? <Json>[] : walletsOf(account))
                    ChoiceChip(
                      label: Text(str(w['currency'])),
                      selected: str(w['currency']) == code,
                      onSelected: (_) =>
                          setState(() => _currency = str(w['currency'])),
                    ),
                  if (code.isNotEmpty &&
                      !(account.isEmpty ? <Json>[] : walletsOf(account)).any(
                        (w) => str(w['currency']) == code,
                      ))
                    ChoiceChip(
                      label: Text(code),
                      selected: true,
                      onSelected: (_) {},
                    ),
                  ActionChip(
                    label: Text(context.t.entryCurrencyOther),
                    onPressed: () async {
                      final picked = await pickCurrency(
                        context,
                        current: code,
                        first: <String>{context.currencyCode},
                      );
                      if (picked != null) setState(() => _currency = picked);
                    },
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
                onPressed: _busy
                    ? null
                    : () => _save(selected, account.isEmpty ? null : account),
                child: Text(context.t.expenseLogIt),
              ),
            ],
          );
        },
      ),
    );
  }
}
