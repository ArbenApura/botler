// ACCOUNTS: WHAT IS IN EACH ONE, ADD ONE, AND "I COUNTED THIS" TO CORRECT THE BALANCE.
// A count that differs a lot from what Botler expected is shown for a yes first; one ten times off asks twice. Money that went missing between two
// counts is shown as "untracked", never hidden.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/money.dart';
import '../../core/money_scope.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- TYPES -- //

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final accounts = ref.watch(balancesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t.accountsTitle)),
      body: AsyncBody<List<Json>>(
        value: accounts,
        onRetry: () => ref.invalidate(balancesProvider),
        data: (list) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (list.isEmpty) Note(context.t.accountsEmpty),
            for (final a in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PaperCard(
                  onTap: () => context.push('/account/${str(a['id'])}'),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              str(a['name']),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              a['countedAt'] == null
                                  ? context.t.accountsNeverCounted
                                  : context.t.accountsCounted(
                                      _ago(context, str(a['countedAt'])),
                                    ),
                              style: TextStyle(color: c.muted),
                            ),
                            if (boolOf(a['belowMinimum']))
                              Text(
                                context.t.accountsBelowMinimum,
                                style: TextStyle(color: c.warning),
                              ),
                          ],
                        ),
                      ),
                      Amount(intOf(a['balance'])),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add),
              label: Text(context.t.accountsAdd),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final min = TextEditingController();
    var kind = 'bank';
    final done = await showFormSheet<bool>(
      context,
      title: context.t.accountsAdd,
      builder: (sheet, close) => StatefulBuilder(
        builder: (_, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Field(
              controller: name,
              label: context.t.accountsNameLabel,
              hint: sheet.t.accountsNameHint,
            ),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final (k, label) in <(String, String)>[
                  ('bank', sheet.t.accountsKindBank),
                  ('ewallet', sheet.t.accountsKindEwallet),
                  ('cash', sheet.t.accountsKindCash),
                  ('other', sheet.t.accountsKindOther),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: kind == k,
                    onSelected: (_) => setState(() => kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Field(
              controller: min,
              label: sheet.t.accountsMinimumLabel(sheet.currencyCode),
              hint: '500',
              keyboard: TextInputType.number,
            ),
            FilledButton(
              onPressed: () async {
                final minimum = min.text.trim().isEmpty
                    ? 0
                    : context.parseAmount(min.text);
                if (name.text.trim().isEmpty || minimum == null) {
                  say(sheet, sheet.t.accountsAddInvalid);
                  return;
                }
                try {
                  await ref.read(apiProvider).verb(
                    'account_create',
                    <String, Object?>{
                      'name': name.text.trim(),
                      'kind': kind,
                      'minBalance': minimum,
                    },
                  );
                  close(true);
                } catch (e) {
                  if (sheet.mounted) say(sheet, errorWords(e, context));
                }
              },
              child: Text(sheet.t.add),
            ),
          ],
        ),
      ),
    );
    if (done == true) ref.invalidate(balancesProvider);
  }

  /// The count sheet, also opened from an account's own screen.
  static Future<void> count(
    BuildContext context,
    WidgetRef ref,
    Json account,
  ) async {
    final amount = TextEditingController();
    final result = await showFormSheet<String>(
      context,
      title: context.t.accountsCountTitle(str(account['name'])),
      builder: (sheet, close) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            sheet.t.accountsBotlerThinks(
              sheet.money(intOf(account['balance'])),
            ),
            style: TextStyle(color: sheet.colors.muted),
          ),
          const SizedBox(height: 12),
          Field(
            controller: amount,
            label: sheet.t.accountsCountLabel(sheet.currencyCode),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          FilledButton(
            onPressed: () async {
              final cents = context.parseAmount(amount.text);
              if (cents == null) {
                say(sheet, sheet.t.accountsCountInvalid(sheet.currencyCode));
                return;
              }
              close(await _record(sheet, ref, account, cents));
            },
            child: Text(sheet.t.accountsSaveCount),
          ),
        ],
      ),
    );
    if (result != null && context.mounted) say(context, result);
    ref.invalidate(balancesProvider);
  }

  /// Saves a count, asking for a yes (twice for a ten-times difference) when the server wants it.
  static Future<String> _record(
    BuildContext sheet,
    WidgetRef ref,
    Json account,
    int cents,
  ) async {
    final api = ref.read(apiProvider);
    // The currency is read before any await, so no context is used after one
    final code = sheet.currencyCode;
    final t = sheet.t;
    final base = <String, Object?>{
      'accountId': str(account['id']),
      'amount': cents,
    };
    try {
      var answer = asJson(await api.verb('snapshot_record', base));
      if (str(answer['status']) == 'needs_confirmation') {
        final chip = asJson(answer['chip']);
        final large = str(chip['severity']) == 'large';
        final expected = chip['expected'] == null
            ? null
            : intOf(chip['expected']);
        if (!sheet.mounted) return '';
        final yes = await confirm(
          sheet,
          title: large ? t.accountsConfirmBig : t.accountsConfirmRight,
          body:
              '${expected == null ? t.accountsConfirmCounted(formatMoney(cents, code)) : t.accountsConfirmBoth(formatMoney(cents, code), formatMoney(expected, code))}${large ? ' ${t.accountsConfirmLarge}' : ''}',
          yes: t.accountsConfirmYes,
        );
        if (!yes) return t.accountsNotSaved;
        answer = asJson(
          await api.verb('snapshot_record', <String, Object?>{
            ...base,
            'confirmed': true,
            'acknowledgeLarge': large,
          }),
        );
      }
      final untracked = intOf(answer['untracked']);
      return untracked > 0
          ? t.accountsSavedUntracked(formatMoney(untracked, code))
          : t.accountsSaved;
    } catch (e) {
      return errorWords(e);
    }
  }
}

// -- FUNCTIONS -- //

String _ago(BuildContext context, String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final days = DateTime.now().difference(d).inDays;
  return days <= 0
      ? context.t.accountsToday
      : days == 1
      ? context.t.accountsYesterday
      : context.t.accountsDaysAgo(days);
}
