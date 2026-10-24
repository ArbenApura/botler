// PAYDAY: WHEN YOUR PAY ARRIVES, THE SPLIT FOR EACH PAYDAY (PLAN IT, THEN APPROVE IT), AND THE RULES FOR WHERE THE REST GOES.
// A rule you write in words ("20% to emergency fund") is shown as a sentence and applies only after you approve it. A pay that is too small is
// shown with the gap and what could be cut, and there is nothing to approve until you decide.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/money_scope.dart';
import '../../core/schedule_text.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../money/bills_parts.dart' show niceDate;
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
      appBar: AppBar(title: Text(context.t.paydayTitle)),
      body: ListView(
        padding: pagePadding(context),
        children: <Widget>[
          SectionTitle(context.t.paydayYours),
          AsyncBody<List<Json>>(
            value: ref.watch(_incomeProvider),
            skeleton: const SkeletonRows(count: 2),
            onRetry: () => ref.invalidate(_incomeProvider),
            data: (list) => Column(
              children: <Widget>[
                if (list.isEmpty) Note(context.t.paydayEmpty),
                for (final i in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(str(i['label'])),
                    subtitle: Text(
                      i['expectedAmount'] == null
                          ? context.t.paydayDifferent
                          : '${context.t.paydayUsually(context.moneyMain(intOf(i['expectedAmount'])))} · ${describeSchedule(context.t, Localizations.localeOf(context).toString(), asJson(i['schedule'])) ?? context.t.schedUnknown}',
                      style: TextStyle(color: c.muted),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _addIncome(context, ref),
                  icon: const Icon(Icons.add),
                  label: Text(context.t.paydayAdd),
                ),
              ],
            ),
          ),
          SectionTitle(context.t.paydayComingUp),
          AsyncBody<List<Json>>(
            value: ref.watch(_upcomingProvider),
            skeleton: const SkeletonRows(count: 2),
            onRetry: () => ref.invalidate(_upcomingProvider),
            data: (list) => Column(
              children: <Widget>[
                if (list.isEmpty) Note(context.t.paydayNoneAhead),
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
                                  niceDate(context, str(u['payday'])),
                                  style: TextStyle(color: c.muted),
                                ),
                              ],
                            ),
                          ),
                          FilledButton(
                            onPressed: () => _plan(context, ref, u),
                            child: Text(context.t.paydayPlan),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SectionTitle(context.t.paydayRulesTitle),
          AsyncBody<List<Json>>(
            value: ref.watch(_rulesProvider),
            skeleton: const SkeletonRows(count: 2),
            onRetry: () => ref.invalidate(_rulesProvider),
            data: (list) => Column(
              children: <Widget>[
                if (list.where((r) => str(r['status']) != 'retired').isEmpty)
                  Note(context.t.paydayRulesEmpty),
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
                                  context.t.paydayWaiting,
                                  style: TextStyle(color: c.warning),
                                ),
                            ],
                          ),
                        ),
                        if (str(r['status']) == 'proposed')
                          FilledButton(
                            onPressed: () =>
                                _do(context, ref, 'rule_approve', r),
                            child: Text(context.t.paydayApprove),
                          ),
                        TextButton(
                          onPressed: () => _do(context, ref, 'rule_retire', r),
                          child: Text(
                            str(r['status']) == 'proposed'
                                ? context.t.paydayDecline
                                : context.t.paydayStop,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _addRule(context, ref),
                  icon: const Icon(Icons.add),
                  label: Text(context.t.paydayAddRule),
                ),
              ],
            ),
          ),
          SectionTitle(context.t.paydayEarlier),
          AsyncBody<List<Json>>(
            value: ref.watch(_splitsProvider),
            skeleton: const SkeletonRows(count: 2),
            onRetry: () => ref.invalidate(_splitsProvider),
            data: (list) => Column(
              children: <Widget>[
                if (!list.any((p) => str(p['status']) != 'superseded'))
                  Note(context.t.paydayNoEarlier),
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
      if (context.mounted) say(context, errorWords(e, context));
    }
  }

  Future<void> _plan(BuildContext context, WidgetRef ref, Json upcoming) async {
    final pay = TextEditingController();
    final result = await showFormSheet<Json>(
      context,
      title: context.t.paydayPlanTitle(
        str(upcoming['label']),
        str(upcoming['payday']),
      ),
      builder: (sheet, close) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Field(
            controller: pay,
            label: sheet.t.paydayPayLabel,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          FilledButton(
            onPressed: () async {
              final cents = pay.text.trim().isEmpty
                  ? null
                  : context.parseAmountMain(pay.text);
              if (pay.text.trim().isNotEmpty && cents == null) {
                say(sheet, sheet.t.paydayPayInvalid(sheet.currencyCode));
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
                if (sheet.mounted) say(sheet, errorWords(e, context));
              }
            },
            child: Text(sheet.t.paydayMakeSplit),
          ),
        ],
      ),
    );
    if (result == null || !context.mounted) return;
    if (str(result['status']) == 'needs_amounts') {
      final names = asJsonList(result['bills'])
          .map((b) => str(b['name']))
          .join(', ');
      say(context, context.t.paydayNeedsAmounts(names));
      return;
    }
    _refresh(ref);
  }

  Future<void> _addRule(BuildContext context, WidgetRef ref) async {
    final words = TextEditingController();
    final done = await showFormSheet<bool>(
      context,
      title: context.t.paydayRuleTitle,
      builder: (sheet, close) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Field(
            controller: words,
            label: sheet.t.paydayRuleLabel,
            hint: sheet.t.paydayRuleHint,
          ),
          Text(
            sheet.t.paydayRuleExamples,
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
                if (sheet.mounted) say(sheet, errorWords(e, context));
              }
            },
            child: Text(sheet.t.paydayRuleAddButton),
          ),
        ],
      ),
    );
    if (done == true) _refresh(ref);
  }

  Future<void> _addIncome(BuildContext context, WidgetRef ref) async {
    final label = TextEditingController(text: context.t.paydayIncomeDefault);
    final amount = TextEditingController();
    final schedule = ScheduleValue(
      pattern: SchedulePattern.semiMonthly,
      day: 15,
      day2: 30,
    );
    final accounts = await ref.read(balancesProvider.future);
    var accountId = str(accounts.firstOrNull?['id']);
    if (!context.mounted) return;
    final done = await showFormSheet<bool>(
      context,
      title: context.t.paydayIncomeTitle,
      builder: (sheet, close) => StatefulBuilder(
        builder: (_, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Field(
              controller: label,
              label: sheet.t.paydayIncomeLabel,
              capitalization: TextCapitalization.words,
            ),
            Field(
              controller: amount,
              label: sheet.t.paydayIncomeAmountLabel(sheet.currencyCode),
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            Text(
              sheet.t.paydayLandsIn,
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
            // A payday is one day, so the patterns that give a window of days are not offered
            SchedulePicker(
              value: schedule,
              weekend: 'before',
              singleDayOnly: true,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                final cents = amount.text.trim().isEmpty
                    ? null
                    : context.parseAmountMain(amount.text);
                if (label.text.trim().isEmpty ||
                    accountId.isEmpty ||
                    (amount.text.trim().isNotEmpty && cents == null)) {
                  say(sheet, sheet.t.paydayIncomeInvalid);
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
                  if (sheet.mounted) say(sheet, errorWords(e, context));
                }
              },
              child: Text(sheet.t.save),
            ),
          ],
        ),
      ),
    );
    if (done == true) _refresh(ref);
  }
}
