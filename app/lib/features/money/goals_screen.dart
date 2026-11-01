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
import 'payday_count.dart';

// -- CONSTANTS -- //

final FutureProvider<List<Json>> _goalsProvider =
    FutureProvider.autoDispose<List<Json>>(
      (ref) => ref.watch(apiProvider).verbList('goals_list'),
    );

/// One key per goal switch (the intent names the target state) and per goal delete, and no second call while one runs.
final Once _goalOnce = Once();

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
                              '${intOf(g['perPayday']) > 0 ? context.t.goalsEachPayday(context.moneyMain(intOf(g['perPayday']))) : context.t.goalsOnlyRules}${g['targetAmount'] == null ? '' : context.t.goalsAim(context.moneyMain(intOf(g['targetAmount'])))}',
                              style: TextStyle(color: c.muted),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: boolOf(g['active']),
                        onChanged: (on) async {
                          try {
                            final id = str(g['id']);
                            await _goalOnce.run((key) async {
                              await ref.read(apiProvider).verb(
                                'goal_update',
                                <String, Object?>{'goalId': id, 'active': on},
                                key,
                              );
                            }, intent: 'switch:$id:$on');
                            ref.invalidate(_goalsProvider);
                          } catch (e) {
                            if (context.mounted)
                              say(context, errorWords(e, context));
                          }
                        },
                      ),
                      PopupMenuButton<String>(
                        tooltip: context.t.goalsMenu,
                        onSelected: (_) => _delete(context, ref, g),
                        itemBuilder: (_) => <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Text(
                              context.t.goalsDelete,
                              style: TextStyle(color: c.danger),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 4),
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

  /// Removes a goal for good, after asking. Its payday rules go with it; the money saved for it stays where it is.
  Future<void> _delete(BuildContext context, WidgetRef ref, Json g) async {
    final deleted = context.t.goalsDeleted;
    final ok = await confirm(
      context,
      title: context.t.goalsDeleteTitle,
      body: context.t.goalsDeleteBody(str(g['name'])),
      yes: context.t.goalsDeleteYes,
      danger: true,
    );
    if (!ok) return;
    try {
      final id = str(g['id']);
      await _goalOnce.run((key) async {
        await ref.read(apiProvider).verb('goal_delete', <String, Object?>{
          'goalId': id,
        }, key);
      }, intent: 'delete:$id');
      ref.invalidate(_goalsProvider);
      if (context.mounted) say(context, deleted);
    } catch (e) {
      if (context.mounted) say(context, errorWords(e, context));
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    // The accounts and the paydays are read first; a failure (offline) is said, never silent
    final List<Json> accounts;
    int? paydays;
    try {
      accounts = await ref.read(balancesProvider.future);
      try {
        paydays = paydaysPerYearOf(
          await ref.read(apiProvider).verbList('income_list'),
        );
      } on Object {
        // Without the paydays only the yearly line is left out
        paydays = null;
      }
    } catch (e) {
      if (context.mounted) say(context, errorWords(e, context));
      return;
    }
    var accountId = str(accounts.firstOrNull?['id']);
    if (!context.mounted) return;
    final done = await showFormSheet<bool>(
      context,
      title: context.t.goalsAdd,
      builder: (sheet, close) => SheetScope(
        texts: const <String>['', '', ''],
        builder: (_, s) => StatefulBuilder(
          builder: (_, setState) {
            final name = s.c[0];
            final per = s.c[1];
            final target = s.c[2];
            return Column(
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
                        avatar: AccountBadge(
                          accountId: str(a['id']),
                          name: str(a['name']),
                          size: 24,
                        ),
                        label: Text(str(a['name'])),
                        selected: str(a['id']) == accountId,
                        onSelected: (_) =>
                            setState(() => accountId = str(a['id'])),
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
                if (paydays != null &&
                    (context.parseAmountMain(per.text) ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      sheet.t.goalsYear(
                        paydays,
                        context.moneyMain(
                          (context.parseAmountMain(per.text) ?? 0) * paydays,
                        ),
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
                  onPressed: s.once.running()
                      ? null
                      : () async {
                          final perCents = per.text.trim().isEmpty
                              ? 0
                              : context.parseAmountMain(per.text);
                          final aim = target.text.trim().isEmpty
                              ? null
                              : context.parseAmountMain(target.text);
                          if (name.text.trim().isEmpty ||
                              accountId.isEmpty ||
                              perCents == null) {
                            say(sheet, sheet.t.goalsAddInvalid);
                            return;
                          }
                          try {
                            if (!await s.once.ok((key) async {
                              await ref.read(apiProvider).verb(
                                'goal_create',
                                <String, Object?>{
                                  'name': name.text.trim(),
                                  'accountId': accountId,
                                  'perPayday': perCents,
                                  'targetAmount': aim,
                                },
                                key,
                              );
                            })) {
                              return;
                            }
                            close(true);
                          } catch (e) {
                            if (sheet.mounted)
                              say(sheet, errorWords(e, context));
                          }
                        },
                  child: Text(sheet.t.goalsAddButton),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (done == true) ref.invalidate(_goalsProvider);
  }
}
