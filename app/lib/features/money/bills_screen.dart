// BILLS: WHAT IS COMING UP (TAP "PAID" WHEN IT IS), THE LIST OF ALL BILLS WITH WHAT EACH IS EXPECTED TO COST, AND ADDING ONE.
// A bill whose amount varies learns its usual amount from what you pay; when it has no history yet you are asked for a starting estimate.
// The parents' share is just a bill marked as such, so the payday split sets it aside first.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/money.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'schedule_picker.dart';

// -- CONSTANTS -- //

final FutureProvider<List<Json>> _billsProvider =
    FutureProvider.autoDispose<List<Json>>(
      (ref) => ref.watch(apiProvider).verbList('bills_list'),
    );

final FutureProvider<List<Json>> _dueProvider =
    FutureProvider.autoDispose<List<Json>>((ref) {
      final now = DateTime.now();
      final f = DateFormat('yyyy-MM-dd');
      return ref.watch(apiProvider).verbList('bills_due', <String, Object?>{
        'from': f.format(now),
        'to': f.format(now.add(const Duration(days: 45))),
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
    final c = context.colors;
    final bills = ref.watch(_billsProvider);
    final due = ref.watch(_dueProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Bills')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const SectionTitle('Coming up'),
          AsyncBody<List<Json>>(
            value: due,
            onRetry: () => ref.invalidate(_dueProvider),
            data: (list) {
              final open = list.where((d) => !boolOf(d['paid'])).toList();
              if (open.isEmpty)
                return const Note('Nothing is due in the next 6 weeks.');
              return Column(
                children: <Widget>[
                  for (final d in open)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PaperCard(
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    str(d['name']),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  Text(
                                    _nice(str(d['dueDate'])),
                                    style: TextStyle(color: c.muted),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              boolOf(d['unknownAmount'])
                                  ? 'amount?'
                                  : formatPhp(intOf(d['amount'])),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => _pay(context, ref, d),
                              child: const Text('Paid'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SectionTitle('All bills'),
          AsyncBody<List<Json>>(
            value: bills,
            onRetry: () => ref.invalidate(_billsProvider),
            data: (list) => Column(
              children: <Widget>[
                if (list.isEmpty)
                  const Note(
                    'No bills yet. Add rent, internet, electricity...',
                  ),
                for (final b in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(str(b['name'])),
                    subtitle: Text(
                      _describe(b),
                      style: TextStyle(color: c.muted),
                    ),
                    trailing: Switch(
                      value: boolOf(b['active']),
                      onChanged: (on) async {
                        try {
                          await ref.read(apiProvider).verb(
                            'bill_update',
                            <String, Object?>{
                              'billId': str(b['id']),
                              'active': on,
                            },
                          );
                          _refresh(ref);
                        } catch (e) {
                          if (context.mounted) say(context, errorWords(e));
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _add(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Add a bill'),
          ),
        ],
      ),
    );
  }

  Future<void> _pay(BuildContext context, WidgetRef ref, Json due) async {
    final amount = TextEditingController(
      text: boolOf(due['unknownAmount']) ? '' : pesosText(intOf(due['amount'])),
    );
    final result = await showFormSheet<String>(
      context,
      title: '${str(due['name'])} paid',
      builder: (sheet, close) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Field(
            controller: amount,
            label: 'How much was it this time? (pesos)',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          FilledButton(
            onPressed: () async {
              final cents = parsePesos(amount.text);
              if (cents == null || cents <= 0) {
                say(sheet, 'Type the amount in pesos.');
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
                      ? 'Marked paid. It came in ${formatPhp(hint.toInt())} under the usual: you could set that aside.'
                      : 'Marked paid.',
                );
              } catch (e) {
                if (sheet.mounted) say(sheet, errorWords(e));
              }
            },
            child: const Text('Mark paid'),
          ),
        ],
      ),
    );
    if (result != null) {
      if (context.mounted) say(context, result);
      _refresh(ref);
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final amount = TextEditingController();
    final schedule = ScheduleValue();
    var varies = false;
    var parents = false;
    var accountId = '';
    final accounts = await ref.read(balancesProvider.future);
    accountId = str(accounts.firstOrNull?['id']);
    if (!context.mounted) return;
    final done = await showFormSheet<bool>(
      context,
      title: 'Add a bill',
      builder: (sheet, close) => StatefulBuilder(
        builder: (_, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Field(controller: name, label: 'What is it?', hint: 'Rent'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('The amount is different every time'),
              value: varies,
              onChanged: (v) => setState(() => varies = v),
            ),
            Field(
              controller: amount,
              label: varies ? 'About how much? (pesos)' : 'How much? (pesos)',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            Text('Paid from', style: TextStyle(color: sheet.colors.muted)),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final a in accounts)
                  ChoiceChip(
                    label: Text(str(a['name'])),
                    selected: str(a['id']) == accountId,
                    onSelected: (_) => setState(() => accountId = str(a['id'])),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SchedulePicker(value: schedule, onChanged: () => setState(() {})),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('This is my parents’ share'),
              value: parents,
              onChanged: (v) => setState(() => parents = v),
            ),
            FilledButton(
              onPressed: () async {
                final cents = amount.text.trim().isEmpty
                    ? null
                    : parsePesos(amount.text);
                if (name.text.trim().isEmpty ||
                    accountId.isEmpty ||
                    (!varies && cents == null)) {
                  say(sheet, 'Give it a name, an amount and an account.');
                  return;
                }
                try {
                  await ref.read(apiProvider).verb(
                    'bill_create',
                    <String, Object?>{
                      'name': name.text.trim(),
                      'category': parents ? 'parents' : 'bills',
                      'accountId': accountId,
                      'kind': varies ? 'variable' : 'fixed',
                      'amount': cents,
                      'schedule': schedule.toJson(),
                      'weekendRule': 'none',
                      'deferrable': false,
                    },
                  );
                  close(true);
                } catch (e) {
                  if (sheet.mounted) say(sheet, errorWords(e));
                }
              },
              child: const Text('Add the bill'),
            ),
          ],
        ),
      ),
    );
    if (done == true) _refresh(ref);
  }
}

// -- FUNCTIONS -- //

String _nice(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : DateFormat('EEE, MMM d').format(d);
}

String _describe(Json b) {
  final est = asJson(b['estimate']);
  final amount = est['amount'] == null
      ? 'amount not known yet'
      : '${formatPhp(intOf(est['amount']))}${str(b['kind']) == 'variable' ? ' (usual)' : ''}';
  final s = asJson(b['schedule']);
  final when = switch (str(s['kind'])) {
    'monthly' => 'every month on the ${s['day']}th',
    'semi_monthly' => 'twice a month',
    'every_n_days' => 'every ${s['n']} days',
    _ => '',
  };
  return '$amount · $when${str(b['category']) == 'parents' ? ' · parents’ share' : ''}';
}
