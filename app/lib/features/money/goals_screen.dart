// SAVINGS GOALS: WHAT YOU ARE SAVING FOR, WHERE IT SITS, AND HOW MUCH IS SET ASIDE EACH PAYDAY. THE PAYDAY SPLIT SETS IT ASIDE AFTER THE BILLS.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/money_scope.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
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
      appBar: AppBar(title: Text(context.t.goalsTitle)),
      body: AsyncBody<List<Json>>(
        value: goals,
        skeleton: const SkeletonPage(
          child: SkeletonRows(count: 3, kind: SkeletonKind.tile),
        ),
        onRetry: () => ref.invalidate(_goalsProvider),
        data: (list) => ListView(
          padding: pagePadding(context),
          children: <Widget>[
            if (list.isEmpty) Note(context.t.goalsEmpty),
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
                              '${intOf(g['perPayday']) > 0 ? context.t.goalsEachPayday(context.money(intOf(g['perPayday']))) : context.t.goalsOnlyRules}${g['targetAmount'] == null ? '' : context.t.goalsAim(context.money(intOf(g['targetAmount'])))}',
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
                            if (context.mounted)
                              say(context, errorWords(e, context));
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
              label: Text(context.t.goalsAdd),
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
      title: context.t.goalsAdd,
      builder: (sheet, close) => StatefulBuilder(
        builder: (_, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Field(
              controller: name,
              label: sheet.t.goalsNameLabel,
              hint: sheet.t.goalsNameHint,
              capitalization: TextCapitalization.words,
            ),
            Text(
              sheet.t.goalsWhere,
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
              label: sheet.t.goalsPerLabel(sheet.currencyCode),
              keyboard: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            if (context.parseAmount(per.text) != null &&
                (context.parseAmount(per.text) ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  sheet.t.goalsYear(
                    context.money((context.parseAmount(per.text) ?? 0) * 24),
                  ),
                  style: TextStyle(color: sheet.colors.muted),
                ),
              ),
            Field(
              controller: target,
              label: sheet.t.goalsTargetLabel(sheet.currencyCode),
              keyboard: TextInputType.number,
            ),
            FilledButton(
              onPressed: () async {
                final perCents = per.text.trim().isEmpty
                    ? 0
                    : context.parseAmount(per.text);
                final aim = target.text.trim().isEmpty
                    ? null
                    : context.parseAmount(target.text);
                if (name.text.trim().isEmpty ||
                    accountId.isEmpty ||
                    perCents == null) {
                  say(sheet, sheet.t.goalsAddInvalid);
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
                  if (sheet.mounted) say(sheet, errorWords(e, context));
                }
              },
              child: Text(sheet.t.goalsAddButton),
            ),
          ],
        ),
      ),
    );
    if (done == true) ref.invalidate(_goalsProvider);
  }
}
