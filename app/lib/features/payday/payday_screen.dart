// PAYDAY: WHEN YOUR PAY ARRIVES, THE SPLIT FOR EACH PAYDAY (PLAN IT, THEN APPROVE IT), AND THE RULES FOR WHERE THE REST GOES.
// A rule you write in words ("20% to emergency fund") is shown as a sentence and applies only after you approve it. A pay that is too small is
// shown with the gap and what could be cut, and there is nothing to approve until you decide.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/money.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../money/schedule_picker.dart';
import 'split_card.dart';

// -- CONSTANTS -- //

final FutureProvider<List<Json>> _incomeProvider =
    FutureProvider.autoDispose<List<Json>>(
      (ref) => ref.watch(apiProvider).verbList('income_list'),
    );
final FutureProvider<List<Json>> _upcomingProvider =
    FutureProvider.autoDispose<List<Json>>(
      (ref) => ref.watch(apiProvider).verbList('split_upcoming'),
    );
final FutureProvider<List<Json>> _rulesProvider =
    FutureProvider.autoDispose<List<Json>>(
      (ref) => ref.watch(apiProvider).verbList('rules_list'),
    );
final FutureProvider<List<Json>> _splitsProvider =
    FutureProvider.autoDispose<List<Json>>(
      (ref) => ref.watch(apiProvider).verbList('split_list', <String, Object?>{
        'limit': 8,
      }),
    );

// -- TYPES -- //

class PaydayScreen extends ConsumerWidget {
  const PaydayScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref
      ..invalidate(_incomeProvider)
      ..invalidate(_upcomingProvider)
      ..invalidate(_rulesProvider)
      ..invalidate(_splitsProvider)
      ..invalidate(balancesProvider)
      ..invalidate(syncProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Payday')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const SectionTitle('Your paydays'),
          AsyncBody<List<Json>>(
            value: ref.watch(_incomeProvider),
            onRetry: () => ref.invalidate(_incomeProvider),
            data: (list) => Column(
              children: <Widget>[
                if (list.isEmpty) const Note('Tell Botler when you get paid.'),
                for (final i in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(str(i['label'])),
                    subtitle: Text(
                      i['expectedAmount'] == null
                          ? 'Different every time'
                          : 'Usually ${formatPhp(intOf(i['expectedAmount']))}',
                      style: TextStyle(color: c.muted),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _addIncome(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Add a payday'),
                ),
              ],
            ),
          ),
          const SectionTitle('Coming up'),
          AsyncBody<List<Json>>(
            value: ref.watch(_upcomingProvider),
            onRetry: () => ref.invalidate(_upcomingProvider),
            data: (list) => Column(
              children: <Widget>[
                if (list.isEmpty) const Note('No payday ahead yet.'),
                for (final u in list)
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
                                  str(u['label']),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(
                                  str(u['payday']),
                                  style: TextStyle(color: c.muted),
                                ),
                              ],
                            ),
                          ),
                          FilledButton(
                            onPressed: () => _plan(context, ref, u),
                            child: const Text('Plan the split'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SectionTitle('Rules for the rest'),
          AsyncBody<List<Json>>(
            value: ref.watch(_rulesProvider),
            onRetry: () => ref.invalidate(_rulesProvider),
            data: (list) => Column(
              children: <Widget>[
                if (list.where((r) => str(r['status']) != 'retired').isEmpty)
                  const Note(
                    'No rules yet. Say what should happen to what is left, like “20% to emergency fund”.',
                  ),
                for (final r in list.where(
                  (r) => str(r['status']) != 'retired',
                ))
                  PaperCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(str(r['summary'])),
                              if (str(r['status']) == 'proposed')
                                Text(
                                  'Waiting for your yes',
                                  style: TextStyle(color: c.warning),
                                ),
                            ],
                          ),
                        ),
                        if (str(r['status']) == 'proposed')
                          FilledButton(
                            onPressed: () =>
                                _do(context, ref, 'rule_approve', r),
                            child: const Text('Approve'),
                          ),
                        TextButton(
                          onPressed: () => _do(context, ref, 'rule_retire', r),
                          child: Text(
                            str(r['status']) == 'proposed' ? 'Decline' : 'Stop',
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _addRule(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Add a rule'),
                ),
              ],
            ),
          ),
          const SectionTitle('Earlier splits'),
          AsyncBody<List<Json>>(
            value: ref.watch(_splitsProvider),
            onRetry: () => ref.invalidate(_splitsProvider),
            data: (list) => Column(
              children: <Widget>[
                for (final p in list.where(
                  (p) => str(p['status']) != 'superseded',
                ))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SplitCard(
                      key: ValueKey<String>(
                        '${str(p['id'])}${str(p['status'])}',
                      ),
                      plan: p,
                      onChanged: () => _refresh(ref),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _do(
    BuildContext context,
    WidgetRef ref,
    String verb,
    Json rule,
  ) async {
    try {
      await ref.read(apiProvider).verb(verb, <String, Object?>{
        'ruleId': str(rule['id']),
      });
      _refresh(ref);
    } catch (e) {
      if (context.mounted) say(context, errorWords(e));
    }
  }

  Future<void> _plan(BuildContext context, WidgetRef ref, Json upcoming) async {
    final pay = TextEditingController();
    final result = await showFormSheet<Json>(
      context,
      title: 'Plan ${str(upcoming['label'])} on ${str(upcoming['payday'])}',
      builder: (sheet, close) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Field(
            controller: pay,
            label: 'How much is the pay this time? (leave empty for the usual)',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          FilledButton(
            onPressed: () async {
              final cents = pay.text.trim().isEmpty
                  ? null
                  : parsePesos(pay.text);
              if (pay.text.trim().isNotEmpty && cents == null) {
                say(sheet, 'Type the pay in pesos.');
                return;
              }
              try {
                final plan = asJson(
                  await ref.read(apiProvider).verb(
                    'split_propose',
                    <String, Object?>{
                      'incomeScheduleId': str(upcoming['incomeId']),
                      'payday': str(upcoming['payday']),
                      'pay': cents,
                    },
                  ),
                );
                close(plan);
              } catch (e) {
                if (sheet.mounted) say(sheet, errorWords(e));
              }
            },
            child: const Text('Make the split'),
          ),
        ],
      ),
    );
    if (result == null || !context.mounted) return;
    if (str(result['status']) == 'needs_amounts') {
      final names = asJsonList(result['bills'])
          .map((b) => str(b['name']))
          .join(', ');
      say(
        context,
        'How much is $names usually? Add the amount to the bill first.',
      );
      return;
    }
    _refresh(ref);
  }

  Future<void> _addRule(BuildContext context, WidgetRef ref) async {
    final words = TextEditingController();
    final done = await showFormSheet<bool>(
      context,
      title: 'Add a rule',
      builder: (sheet, close) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Field(
            controller: words,
            label: 'Say it in your own words',
            hint: '20% to emergency fund',
          ),
          Text(
            'Examples: “500 to GCash”, “10% of what is left to Maya”, “the rest to RCBC”.',
            style: TextStyle(color: sheet.colors.muted),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              try {
                await ref.read(apiProvider).verb(
                  'rule_from_text',
                  <String, Object?>{'text': words.text.trim()},
                );
                close(true);
              } catch (e) {
                if (sheet.mounted) say(sheet, errorWords(e));
              }
            },
            child: const Text('Add the rule'),
          ),
        ],
      ),
    );
    if (done == true) _refresh(ref);
  }

  Future<void> _addIncome(BuildContext context, WidgetRef ref) async {
    final label = TextEditingController(text: 'Salary');
    final amount = TextEditingController();
    final schedule = ScheduleValue(
      kind: ScheduleKind.semiMonthly,
      day: 15,
      day2: 30,
    );
    final accounts = await ref.read(balancesProvider.future);
    var accountId = str(accounts.firstOrNull?['id']);
    if (!context.mounted) return;
    final done = await showFormSheet<bool>(
      context,
      title: 'When do you get paid?',
      builder: (sheet, close) => StatefulBuilder(
        builder: (_, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Field(controller: label, label: 'What do you call it?'),
            Field(
              controller: amount,
              label: 'How much, usually? (pesos, optional)',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            Text('It lands in', style: TextStyle(color: sheet.colors.muted)),
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
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                final cents = amount.text.trim().isEmpty
                    ? null
                    : parsePesos(amount.text);
                if (label.text.trim().isEmpty ||
                    accountId.isEmpty ||
                    (amount.text.trim().isNotEmpty && cents == null)) {
                  say(
                    sheet,
                    'Give it a name, an account and the amount as a number.',
                  );
                  return;
                }
                try {
                  await ref.read(apiProvider).verb(
                    'income_create',
                    <String, Object?>{
                      'label': label.text.trim(),
                      'accountId': accountId,
                      'expectedAmount': cents,
                      'schedule': schedule.toJson(),
                      'weekendRule': 'before',
                    },
                  );
                  close(true);
                } catch (e) {
                  if (sheet.mounted) say(sheet, errorWords(e));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (done == true) _refresh(ref);
  }
}
