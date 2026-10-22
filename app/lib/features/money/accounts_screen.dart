// ACCOUNTS: WHAT IS IN EACH ONE, ADD ONE, AND "I COUNTED THIS" TO CORRECT THE BALANCE.
// A count that differs a lot from what Botler expected is shown for a yes first; one ten times off asks twice. Money that went missing between two
// counts is shown as "untracked", never hidden.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/money.dart';
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
      appBar: AppBar(title: const Text('Accounts')),
      body: AsyncBody<List<Json>>(
        value: accounts,
        onRetry: () => ref.invalidate(balancesProvider),
        data: (list) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (list.isEmpty)
              const Note('No accounts yet. Add RCBC, GCash, Maya or cash.'),
            for (final a in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PaperCard(
                  onTap: () => _count(context, ref, a),
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
                                  ? 'Never counted'
                                  : 'Counted ${_ago(str(a['countedAt']))}',
                              style: TextStyle(color: c.muted),
                            ),
                            if (boolOf(a['belowMinimum']))
                              Text(
                                'Below the minimum you set',
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
              label: const Text('Add an account'),
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
      title: 'Add an account',
      builder: (sheet, close) => StatefulBuilder(
        builder: (_, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Field(controller: name, label: 'Name', hint: 'GCash'),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final (k, label) in <(String, String)>[
                  ('bank', 'Bank'),
                  ('ewallet', 'E-wallet'),
                  ('cash', 'Cash'),
                  ('other', 'Other'),
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
              label: 'Keep at least (pesos, optional)',
              hint: '500',
              keyboard: TextInputType.number,
            ),
            FilledButton(
              onPressed: () async {
                final minimum = min.text.trim().isEmpty
                    ? 0
                    : parsePesos(min.text);
                if (name.text.trim().isEmpty || minimum == null) {
                  say(sheet, 'Give it a name, and the minimum as an amount.');
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
                  if (sheet.mounted) say(sheet, errorWords(e));
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (done == true) ref.invalidate(balancesProvider);
  }

  Future<void> _count(BuildContext context, WidgetRef ref, Json account) async {
    final amount = TextEditingController();
    final result = await showFormSheet<String>(
      context,
      title: 'I counted ${str(account['name'])}',
      builder: (sheet, close) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Botler thinks there is ${formatPhp(intOf(account['balance']))}.',
            style: TextStyle(color: sheet.colors.muted),
          ),
          const SizedBox(height: 12),
          Field(
            controller: amount,
            label: 'How much is really there? (pesos)',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          FilledButton(
            onPressed: () async {
              final cents = parsePesos(amount.text);
              if (cents == null) {
                say(sheet, 'Type the amount in pesos.');
                return;
              }
              close(await _record(sheet, ref, account, cents));
            },
            child: const Text('Save the count'),
          ),
        ],
      ),
    );
    if (result != null && context.mounted) say(context, result);
    ref.invalidate(balancesProvider);
  }

  /// Saves a count, asking for a yes (twice for a ten-times difference) when the server wants it.
  Future<String> _record(
    BuildContext sheet,
    WidgetRef ref,
    Json account,
    int cents,
  ) async {
    final api = ref.read(apiProvider);
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
          title: large ? 'That is a big difference' : 'Is this right?',
          body:
              'You counted ${formatPhp(cents)}${expected == null ? '' : ' and Botler expected ${formatPhp(expected)}'}.${large ? ' It is more than ten times different, so please check the digits.' : ''}',
          yes: 'Yes, that is right',
        );
        if (!yes) return 'Not saved.';
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
          ? 'Saved. ${formatPhp(untracked)} went untracked since the last count.'
          : 'Saved.';
    } catch (e) {
      return errorWords(e);
    }
  }
}

// -- FUNCTIONS -- //

String _ago(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final days = DateTime.now().difference(d).inDays;
  return days <= 0
      ? 'today'
      : days == 1
      ? 'yesterday'
      : '$days days ago';
}
