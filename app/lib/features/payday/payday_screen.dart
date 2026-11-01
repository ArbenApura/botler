// PAYDAY: THE NEXT PAYDAYS WITH THEIR SPLIT RIGHT UNDER THEM (PLAN IT, CHECK IT, APPROVE IT), YOUR PAYDAYS, THE RULES FOR WHERE THE REST GOES, AND THE EARLIER SPLITS.
// A rule you write in words ("20% to emergency fund") is shown as a sentence and applies only after you approve it. A pay that is too small is
// shown with the gap and what could be cut, and there is nothing to approve until you decide. Everything here can be changed or deleted:
// paydays, rules and splits each have a menu, and every delete says first what it does.

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
import 'payday_actions.dart';
import 'rule_funding.dart';
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
final FutureProvider<List<Json>> _billsProvider =
    FutureProvider.autoDispose<List<Json>>(
      (ref) => ref.watch(apiProvider).verbList('bills_list'),
    );
final FutureProvider<List<Json>> _splitsProvider =
    FutureProvider.autoDispose<List<Json>>(
      (ref) => ref.watch(apiProvider).verbList('split_list', <String, Object?>{
        'limit': 30,
      }),
    );

/// The statuses of a split that is still being worked on: shown right under its payday rather than among the earlier ones.
const Set<String> _openStatuses = <String>{'proposed', 'shortfall', 'approved'};

// -- FUNCTIONS -- //

/// The split being worked on for this payday of this income, or null.
Json? _openPlanFor(List<Json> plans, Json upcoming) {
  for (final p in plans) {
    if (_openStatuses.contains(str(p['status'])) &&
        str(p['incomeScheduleId']) == str(upcoming['incomeId']) &&
        str(p['payday']) == str(upcoming['payday'])) {
      return p;
    }
  }
  return null;
}

/// One key per rule approve or decline, until it works, and no second call of the same one while it runs.
final Once _ruleOnce = Once();

// -- TYPES -- //

class PaydayScreen extends ConsumerWidget {
  const PaydayScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref
      ..invalidate(_incomeProvider)
      ..invalidate(_upcomingProvider)
      ..invalidate(_rulesProvider)
      ..invalidate(_billsProvider)
      ..invalidate(_splitsProvider)
      ..invalidate(balancesProvider)
      ..invalidate(syncProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    // The bills a rule can save for; while they load or if they fail, the rule cards just show no "Saves for" row
    final bills = ref.watch(_billsProvider).value ?? const <Json>[];
    final plans = ref.watch(_splitsProvider).value ?? const <Json>[];
    return Scaffold(
      appBar: AppBar(title: Text(context.t.paydayTitle)),
      body: ListView(
        padding: pagePadding(context),
        children: <Widget>[
          SectionTitle(context.t.paydayComingUp),
          AsyncBody<List<Json>>(
            value: ref.watch(_upcomingProvider),
            skeleton: const SkeletonRows(count: 2),
            onRetry: () => ref.invalidate(_upcomingProvider),
            data: (list) => Column(
              children: <Widget>[
                if (list.isEmpty) Note(context.t.paydayNoneAhead),
                for (final u in list) _upcoming(context, ref, u, plans, c),
              ],
            ),
          ),
          SectionTitle(context.t.paydayYours),
          AsyncBody<List<Json>>(
            value: ref.watch(_incomeProvider),
            skeleton: const SkeletonRows(count: 2),
            onRetry: () => ref.invalidate(_incomeProvider),
            data: (list) => Column(
              children: <Widget>[
                if (list.isEmpty) Note(context.t.paydayEmpty),
                for (final i in list) _incomeTile(context, ref, i, c),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: () async {
                    if (await incomeSheet(context, ref)) _refresh(ref);
                  },
                  icon: const Icon(Icons.add),
                  label: Text(context.t.paydayAdd),
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
                if (list.isEmpty) Note(context.t.paydayRulesEmpty),
                // Rules in force and waiting first, stopped ones after them
                for (final r in <Json>[
                  ...list.where((r) => str(r['status']) != 'retired'),
                  ...list.where((r) => str(r['status']) == 'retired'),
                ])
                  _ruleCard(context, ref, r, bills, c),
                const SizedBox(height: 4),
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
            data: (list) {
              final upcoming = ref.watch(_upcomingProvider).value ?? const [];
              final shown = <String>{
                for (final u in upcoming)
                  if (_openPlanFor(list, u) case final p?) str(p['id']),
              };
              final earlier = <Json>[
                for (final p in list)
                  if (!shown.contains(str(p['id']))) p,
              ];
              return Column(
                children: <Widget>[
                  if (earlier.isEmpty) Note(context.t.paydayNoEarlier),
                  for (final p in earlier)
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
                  if (earlier.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () async {
                          if (await deleteSplitSheet(context, ref)) {
                            _refresh(ref);
                          }
                        },
                        child: Text(
                          context.t.splitClearAll,
                          style: TextStyle(color: c.danger),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// One coming payday: its name and date with the button that plans it, or, once planned, the split itself with its own buttons.
  Widget _upcoming(
    BuildContext context,
    WidgetRef ref,
    Json u,
    List<Json> plans,
    BotlerColors c,
  ) {
    final plan = _openPlanFor(plans, u);
    final head = Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                str(u['label']),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                niceDate(context, str(u['payday'])),
                style: TextStyle(color: c.muted),
              ),
            ],
          ),
        ),
        if (plan == null)
          FilledButton(
            onPressed: () => _plan(context, ref, u),
            child: Text(context.t.paydayPlan),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: plan == null
          ? PaperCard(child: head)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: head,
                ),
                SplitCard(
                  key: ValueKey<String>(
                    '${str(plan['id'])}${str(plan['status'])}',
                  ),
                  plan: plan,
                  onChanged: () => _refresh(ref),
                  // An approved split is not planned again: it is deleted first, which the card's menu does
                  onPlanAgain: str(plan['status']) == 'approved'
                      ? null
                      : () => _plan(context, ref, u),
                ),
              ],
            ),
    );
  }

  /// One payday of yours. A tap opens it to change or delete.
  Widget _incomeTile(
    BuildContext context,
    WidgetRef ref,
    Json i,
    BotlerColors c,
  ) {
    final off = i['active'] == false;
    return Semantics(
      button: true,
      label: context.t.paydayEditMenu,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            minTileHeight: 56,
            title: Text(str(i['label'])),
            subtitle: Text(
              [
                if (off) context.t.paydayOff,
                if (i['expectedAmount'] == null)
                  context.t.paydayDifferent
                else
                  context.t.paydayUsually(
                    context.moneyMain(intOf(i['expectedAmount'])),
                  ),
                describeSchedule(
                      context.t,
                      Localizations.localeOf(context).toString(),
                      asJson(i['schedule']),
                    ) ??
                    context.t.schedUnknown,
              ].join(' · '),
              style: TextStyle(color: off ? c.warning : c.muted),
            ),
            trailing: Icon(Icons.chevron_right, color: c.muted),
            onTap: () async {
              if (await incomeSheet(context, ref, existing: i)) _refresh(ref);
            },
          ),
        ),
      ),
    );
  }

  /// One rule: its sentence, what it saves for, and the buttons that fit where it is. A waiting rule is approved or declined; one in force
  /// can be stopped or deleted; a stopped one can be deleted.
  Widget _ruleCard(
    BuildContext context,
    WidgetRef ref,
    Json r,
    List<Json> bills,
    BotlerColors c,
  ) {
    final status = str(r['status']);
    final stopped = status == 'retired';
    final waiting = status == 'proposed';
    final name = str(r['label']).isNotEmpty ? str(r['label']) : ruleSentence(r);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PaperCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (str(r['label']).isNotEmpty)
                        Text(
                          str(r['label']),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      Text(
                        ruleSentence(r),
                        style: TextStyle(color: stopped ? c.muted : null),
                      ),
                      if (waiting)
                        Text(
                          context.t.paydayWaiting,
                          style: TextStyle(color: c.warning),
                        ),
                      if (stopped)
                        Text(
                          context.t.paydayRuleStopped,
                          style: TextStyle(color: c.muted),
                        ),
                    ],
                  ),
                ),
                if (!waiting)
                  PopupMenuButton<String>(
                    tooltip: context.t.paydayRuleMenu,
                    onSelected: (v) async {
                      if (v == 'stop') {
                        final yes = await confirm(
                          context,
                          title: context.t.paydayStopTitle,
                          body: context.t.paydayStopBody,
                          yes: context.t.paydayStopYes,
                        );
                        if (yes && context.mounted) {
                          await _do(
                            context,
                            ref,
                            'rule_retire',
                            r,
                            context.t.paydayStopped,
                          );
                        }
                      } else if (v == 'delete') {
                        final yes = await confirm(
                          context,
                          title: context.t.paydayRuleDeleteTitle,
                          body: context.t.paydayRuleDeleteBody(name),
                          yes: context.t.paydayRuleDeleteYes,
                          danger: true,
                        );
                        if (yes && context.mounted) {
                          await _do(
                            context,
                            ref,
                            'rule_delete',
                            r,
                            context.t.paydayRuleDeleted,
                          );
                        }
                      }
                    },
                    itemBuilder: (_) => <PopupMenuEntry<String>>[
                      if (!stopped)
                        PopupMenuItem<String>(
                          value: 'stop',
                          child: Text(context.t.paydayStop),
                        ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text(context.t.paydayRuleDeleteButton),
                      ),
                    ],
                  ),
              ],
            ),
            // A rule that can save for a bill offers it; one that already does names the bill
            if (!stopped &&
                (str(r['fundsBillName']).isNotEmpty ||
                    billsForRule(r, bills, context.currencyCode).isNotEmpty))
              SavesForRow(
                billName: str(r['fundsBillName']),
                onTap: () async {
                  if (await pickSavesFor(
                    context,
                    ref,
                    r,
                    billsForRule(r, bills, context.currencyCode),
                  )) {
                    _refresh(ref);
                  }
                },
              ),
            if (waiting)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton(
                      onPressed: () => _do(
                        context,
                        ref,
                        'rule_retire',
                        r,
                        context.t.paydayDeclined,
                      ),
                      child: Text(context.t.paydayDecline),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () =>
                          _do(context, ref, 'rule_approve', r, null),
                      child: Text(context.t.paydayApprove),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _do(
    BuildContext context,
    WidgetRef ref,
    String verb,
    Json rule,
    String? done,
  ) async {
    try {
      final id = str(rule['id']);
      final ran = await _ruleOnce.ok((key) async {
        await ref.read(apiProvider).verb(verb, <String, Object?>{
          'ruleId': id,
        }, key);
      }, intent: '$verb:$id');
      if (!ran) return;
      _refresh(ref);
      if (done != null && context.mounted) say(context, done);
    } catch (e) {
      if (context.mounted) say(context, errorWords(e, context));
    }
  }

  Future<void> _plan(BuildContext context, WidgetRef ref, Json upcoming) async {
    // The usual pay is filled in, so the common case is one tap
    final usual = _usualPay(ref, upcoming);
    final startPay = usual == null ? '' : context.plainAmountMain(usual);
    final result = await showFormSheet<Json>(
      context,
      title: context.t.paydayPlanTitle(
        str(upcoming['label']),
        niceDate(context, str(upcoming['payday'])),
      ),
      builder: (sheet, close) => SheetScope(
        texts: <String>[startPay],
        builder: (_, s) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Field(
              controller: s.c[0],
              label: sheet.t.paydayPayThisTime(sheet.currencyCode),
              hint: sheet.t.paydayPayEmptyHint,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            FilledButton(
              onPressed: s.once.running()
                  ? null
                  : () async {
                      final pay = s.c[0];
                      final cents = pay.text.trim().isEmpty
                          ? null
                          : context.parseAmountMain(pay.text);
                      if (pay.text.trim().isNotEmpty && cents == null) {
                        say(
                          sheet,
                          sheet.t.paydayPayInvalid(sheet.currencyCode),
                        );
                        return;
                      }
                      try {
                        final answer = await s.once.run(
                          (key) => ref.read(apiProvider).verb(
                            'split_propose',
                            <String, Object?>{
                              'incomeScheduleId': str(upcoming['incomeId']),
                              'payday': str(upcoming['payday']),
                              'pay': cents,
                            },
                            key,
                          ),
                          intent: 'plan:$cents',
                        );
                        if (answer == null) return;
                        close(asJson(answer));
                      } catch (e) {
                        if (sheet.mounted) say(sheet, errorWords(e, context));
                      }
                    },
              child: Text(sheet.t.paydayMakeSplit),
            ),
          ],
        ),
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
    // The split now sits right under its payday, so say where to look
    say(context, context.t.paydaySplitReady);
  }

  /// What this income usually pays, in minor units, or null when it varies.
  int? _usualPay(WidgetRef ref, Json upcoming) {
    final incomes = ref.read(_incomeProvider).value ?? const <Json>[];
    for (final i in incomes) {
      if (str(i['id']) == str(upcoming['incomeId'])) {
        return i['expectedAmount'] is int ? intOf(i['expectedAmount']) : null;
      }
    }
    return null;
  }

  Future<void> _addRule(BuildContext context, WidgetRef ref) async {
    final done = await showFormSheet<bool>(
      context,
      title: context.t.paydayRuleTitle,
      builder: (sheet, close) => SheetScope(
        texts: const <String>['', ''],
        builder: (_, s) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Field(
              controller: s.c[0],
              label: sheet.t.paydayRuleNameLabel,
              hint: sheet.t.paydayRuleNameHint,
            ),
            Field(
              controller: s.c[1],
              label: sheet.t.paydayRuleLabel,
              hint: sheet.t.paydayRuleHint,
            ),
            Text(
              sheet.t.paydayRuleExamples,
              style: TextStyle(color: sheet.colors.muted),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: s.once.running()
                  ? null
                  : () async {
                      final words = s.c[1].text.trim();
                      final name = s.c[0].text.trim();
                      try {
                        final ran = await s.once.ok((key) async {
                          await ref.read(apiProvider).verb(
                            'rule_from_text',
                            <String, Object?>{
                              'text': words,
                              if (name.isNotEmpty) 'label': name,
                            },
                            key,
                          );
                        }, intent: 'rule:$name:$words');
                        if (!ran) return;
                        close(true);
                      } catch (e) {
                        if (sheet.mounted) say(sheet, errorWords(e, context));
                      }
                    },
              child: Text(sheet.t.paydayRuleAddButton),
            ),
          ],
        ),
      ),
    );
    if (done == true) _refresh(ref);
  }
}
