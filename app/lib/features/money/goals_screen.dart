// SAVINGS GOALS: WHAT YOU ARE SAVING FOR, WHERE IT SITS, AND HOW MUCH IS SET ASIDE EACH PAYDAY. THE PAYDAY SPLIT SETS IT ASIDE AFTER THE BILLS.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/money.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- CONSTANTS -- //

final FutureProvider<List<Json>> _goalsProvider =
    FutureProvider.autoDispose<List<Json>>(
      (ref) => ref.watch(apiProvider).verbList('goals_list'),
    );

// -- TYPES -- //

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final goals = ref.watch(_goalsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Savings goals')),
      body: AsyncBody<List<Json>>(
        value: goals,
        onRetry: () => ref.invalidate(_goalsProvider),
        data: (list) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (list.isEmpty)
              const Note('No goals yet. What would you like to save for?'),
            for (final g in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PaperCard(
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              str(g['name']),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${intOf(g['perPayday']) > 0 ? '${formatPhp(intOf(g['perPayday']))} each payday' : 'Only what your rules give it'}${g['targetAmount'] == null ? '' : ' · aim ${formatPhp(intOf(g['targetAmount']))}'}',
                              style: TextStyle(color: c.muted),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: boolOf(g['active']),
                        onChanged: (on) async {
                          try {
                            await ref.read(apiProvider).verb(
                              'goal_update',
                              <String, Object?>{
                                'goalId': str(g['id']),
                                'active': on,
                              },
                            );
                            ref.invalidate(_goalsProvider);
                          } catch (e) {
                            if (context.mounted) say(context, errorWords(e));
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add a goal'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final per = TextEditingController();
    final target = TextEditingController();
    final accounts = await ref.read(balancesProvider.future);
    var accountId = str(accounts.firstOrNull?['id']);
    if (!context.mounted) return;
    final done = await showFormSheet<bool>(
      context,
      title: 'Add a goal',
      builder: (sheet, close) => StatefulBuilder(
        builder: (_, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Field(
              controller: name,
              label: 'What are you saving for?',
              hint: 'Emergency fund',
            ),
            Text(
              'Where does it sit?',
              style: TextStyle(color: sheet.colors.muted),
            ),
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
            Field(
              controller: per,
              label: 'Set aside each payday (pesos, optional)',
              keyboard: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            if (parsePesos(per.text) != null && (parsePesos(per.text) ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'In a year (24 paydays) that is ${formatPhp((parsePesos(per.text) ?? 0) * 24)}.',
                  style: TextStyle(color: sheet.colors.muted),
                ),
              ),
            Field(
              controller: target,
              label: 'The amount you want to reach (pesos, optional)',
              keyboard: TextInputType.number,
            ),
            FilledButton(
              onPressed: () async {
                final perCents = per.text.trim().isEmpty
                    ? 0
                    : parsePesos(per.text);
                final aim = target.text.trim().isEmpty
                    ? null
                    : parsePesos(target.text);
                if (name.text.trim().isEmpty ||
                    accountId.isEmpty ||
                    perCents == null) {
                  say(
                    sheet,
                    'Give it a name, a place, and amounts as numbers.',
                  );
                  return;
                }
                try {
                  await ref.read(apiProvider).verb(
                    'goal_create',
                    <String, Object?>{
                      'name': name.text.trim(),
                      'accountId': accountId,
                      'perPayday': perCents,
                      'targetAmount': aim,
                    },
                  );
                  close(true);
                } catch (e) {
                  if (sheet.mounted) say(sheet, errorWords(e));
                }
              },
              child: const Text('Add the goal'),
            ),
          ],
        ),
      ),
    );
    if (done == true) ref.invalidate(_goalsProvider);
  }
}
