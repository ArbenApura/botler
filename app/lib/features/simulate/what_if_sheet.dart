// THE WHAT-IF SHEET: SIX READY-MADE CHOICES AS TILES THAT TURN ON AND OFF, AND UNDER ONE COLLAPSED PART EVERYTHING BY HAND (PAYDAYS, BILLS, RULES, GOALS,
// TIMING AND PRETEND MONEY, EACH WITH ITS COUNT OF CHANGES) (BTL-20261029-0117, BTL-20261029-0509). Nothing here is saved: it edits the what-if in memory,
// the screen asks the server again after a short pause, and Reset on the screen brings back the plan as it is. Pretend money is always in the
// main currency (the server reads it so). The one primary action is Done.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/money.dart';
import '../../core/money_scope.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../calendar/calendar_data.dart';
import 'simulate_data.dart';
import 'simulate_parts.dart';

// -- CONSTANTS -- //

/// The plan the sheet lists: paydays, bills, active rules, goals and the next paydays, read once when it opens.
final FutureProvider<Json> whatIfPlanProvider =
    FutureProvider.autoDispose<Json>((ref) async {
      final api = ref.watch(apiProvider);
      final results = await Future.wait(<Future<List<Json>>>[
        api.verbList('income_list'),
        api.verbList('bills_list'),
        api.verbList('rules_list', <String, Object?>{'status': 'active'}),
        api.verbList('goals_list'),
        api.verbList('split_upcoming'),
      ]);
      return <String, Object?>{
        'incomes': results[0],
        'bills': results[1],
        'rules': results[2],
        'goals': results[3],
        'upcoming': results[4],
      };
    });

// -- FUNCTIONS -- //

Future<void> showWhatIfSheet(BuildContext context) => showFormSheet<void>(
  context,
  title: context.t.simWhatIfTitle,
  builder: (sheet, close) => _WhatIfForm(close: () => close(null)),
);

/// The ready-made what-ifs: each one is the same shape as a hand-made one.
WhatIf presetSkipNext(WhatIf w, Json plan) {
  final next = asJsonList(plan['upcoming']);
  if (next.isEmpty) return w;
  return w.copyWith(
    skipDates: <String>{...w.skipDates, str(next.first['payday'])},
  );
}

WhatIf presetLate(WhatIf w) => w.copyWith(lateDays: 7);

WhatIf presetNoRules(WhatIf w, Json plan) => w.copyWith(
  off: <String>{
    ...w.off,
    for (final r in asJsonList(plan['rules'])) str(r['id']),
  },
);

/// Every payday with a known amount, changed by a percent (10 or -10), rounded down to the minor unit.
WhatIf presetPay(WhatIf w, Json plan, int percent) => w.copyWith(
  amounts: <String, int>{
    ...w.amounts,
    for (final i in asJsonList(plan['incomes']))
      if (boolOf(i['active'], true) && i['expectedAmount'] is num)
        str(i['id']): (intOf(i['expectedAmount']) * (100 + percent)) ~/ 100,
  },
);

WhatIf presetDefer(WhatIf w) => w.copyWith(defer: true);

// -- READY-MADE CHOICES -- //

/// The six ready-made what-ifs. Each is the same shape as a hand-made one, and each can be turned on and off again.
enum Preset { skipNext, late, noRules, payUp, payDown, defer }

Json _next(Json plan) {
  final next = asJsonList(plan['upcoming']);
  return next.isEmpty ? const <String, Object?>{} : next.first;
}

List<String> _ruleIds(Json plan) => <String>[
  for (final r in asJsonList(plan['rules'])) str(r['id']),
];

/// The new amount of every payday with a known amount, changed by a percent.
Map<String, int> _payAmounts(Json plan, int percent) => <String, int>{
  for (final i in asJsonList(plan['incomes']))
    if (boolOf(i['active'], true) && i['expectedAmount'] is num)
      str(i['id']): (intOf(i['expectedAmount']) * (100 + percent)) ~/ 100,
};

/// False when the plan has nothing for it to act on (no next payday, no rule, no pay with an amount).
bool presetAvailable(Preset p, Json plan) => switch (p) {
  Preset.skipNext => asJsonList(plan['upcoming']).isNotEmpty,
  Preset.noRules => asJsonList(plan['rules']).isNotEmpty,
  Preset.payUp => _payAmounts(plan, 10).isNotEmpty,
  Preset.payDown => _payAmounts(plan, -10).isNotEmpty,
  Preset.late || Preset.defer => true,
};

/// Whether the what-if holds exactly this ready-made choice now.
bool presetIsOn(Preset p, WhatIf w, Json plan) {
  if (!presetAvailable(p, plan)) return false;
  bool pays(int percent) => _payAmounts(
    plan,
    percent,
  ).entries.every((e) => w.amounts[e.key] == e.value);
  return switch (p) {
    Preset.skipNext => w.skipDates.contains(str(_next(plan)['payday'])),
    Preset.late => w.lateDays == 7,
    Preset.noRules => _ruleIds(plan).every(w.off.contains),
    Preset.payUp => pays(10),
    Preset.payDown => pays(-10),
    Preset.defer => w.defer,
  };
}

/// Turns a ready-made choice on, or takes just its own changes away when it is already on.
WhatIf presetToggle(Preset p, WhatIf w, Json plan) {
  if (!presetAvailable(p, plan)) return w;
  if (!presetIsOn(p, w, plan)) {
    return switch (p) {
      Preset.skipNext => presetSkipNext(w, plan),
      Preset.late => presetLate(w),
      Preset.noRules => presetNoRules(w, plan),
      Preset.payUp => presetPay(w, plan, 10),
      Preset.payDown => presetPay(w, plan, -10),
      Preset.defer => presetDefer(w),
    };
  }
  return switch (p) {
    Preset.skipNext => w.copyWith(
      skipDates: <String>{...w.skipDates}..remove(str(_next(plan)['payday'])),
    ),
    Preset.late => w.copyWith(lateDays: 0),
    Preset.noRules => w.copyWith(
      off: <String>{...w.off}..removeAll(_ruleIds(plan)),
    ),
    Preset.payUp || Preset.payDown => w.copyWith(
      amounts: <String, int>{...w.amounts}
        ..removeWhere((k, _) => _payAmounts(plan, 0).containsKey(k)),
    ),
    Preset.defer => w.copyWith(defer: false),
  };
}

/// How many of these ids the what-if switches off or gives another amount.
int _changesIn(WhatIf w, Iterable<String> ids) =>
    ids.where((id) => w.off.contains(id) || w.amounts.containsKey(id)).length;

// -- TYPES -- //

class _WhatIfForm extends ConsumerWidget {
  const _WhatIfForm({required this.close});

  final VoidCallback close;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    final plan = ref.watch(whatIfPlanProvider);
    final w = ref.watch(whatIfProvider);
    final edit = ref.read(whatIfProvider.notifier);
    return AsyncBody<Json>(
      value: plan,
      onRetry: () => ref.invalidate(whatIfPlanProvider),
      skeleton: const SkeletonRows(count: 5),
      data: (p) {
        final incomes = <Json>[
          for (final i in asJsonList(p['incomes']))
            if (boolOf(i['active'], true)) i,
        ];
        final bills = <Json>[
          for (final b in asJsonList(p['bills']))
            if (boolOf(b['active'], true)) b,
        ];
        final rules = asJsonList(p['rules']);
        final goals = <Json>[
          for (final g in asJsonList(p['goals']))
            if (boolOf(g['active'], true)) g,
        ];
        final words = <Preset, (String, String)>{
          Preset.skipNext: (t.simPresetSkipNext, t.simPresetSkipNextLine),
          Preset.late: (t.simPresetLate, t.simPresetLateLine),
          Preset.noRules: (t.simPresetNoRules, t.simPresetNoRulesLine),
          Preset.payUp: (t.simPresetPayUp, t.simPresetPayUpLine),
          Preset.payDown: (t.simPresetPayDown, t.simPresetPayDownLine),
          Preset.defer: (t.simPresetDefer, t.simPresetDeferLine),
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: gapL,
          children: <Widget>[
            Text(t.simWhatIfLine, style: TextStyle(color: c.muted)),
            Text(t.simPresets, style: Theme.of(context).textTheme.titleSmall),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: gapM,
              children: <Widget>[
                for (final k in Preset.values)
                  _PresetTile(
                    title: words[k]?.$1 ?? '',
                    line: words[k]?.$2 ?? '',
                    on: presetIsOn(k, w, p),
                    enabled: presetAvailable(k, p),
                    onTap: () => edit.set(presetToggle(k, w, p)),
                  ),
              ],
            ),
            // Everything the ready-made choices do can also be done by hand, a part at a time
            _Section(
              title: t.simChangeSelf,
              count: w.changes,
              children: <Widget>[
                if (incomes.isNotEmpty)
                  _Section(
                    title: t.simPaydays,
                    count:
                        _changesIn(w, incomes.map((i) => str(i['id']))) +
                        w.skipDates.length,
                    children: <Widget>[
                      for (final i in incomes)
                        _ItemSwitch(
                          id: str(i['id']),
                          name: str(i['label']),
                          usual: i['expectedAmount'] is num
                              ? intOf(i['expectedAmount'])
                              : null,
                          currency: context.currencyCode,
                        ),
                      // The next paydays: tap one to have it not come
                      Text(t.simSkipPayday, style: TextStyle(color: c.muted)),
                      Wrap(
                        spacing: gapM,
                        runSpacing: gapS,
                        children: <Widget>[
                          for (final u in asJsonList(p['upcoming']))
                            FilterChip(
                              label: Text(
                                '${str(u['label'])} · ${shortDay(context, str(u['payday']))}',
                              ),
                              selected: w.skipDates.contains(str(u['payday'])),
                              onSelected: (_) =>
                                  edit.toggleSkip(str(u['payday'])),
                            ),
                        ],
                      ),
                    ],
                  ),
                if (bills.isNotEmpty)
                  _Section(
                    title: t.simBills,
                    count: _changesIn(w, bills.map((b) => str(b['id']))),
                    children: <Widget>[
                      for (final b in bills)
                        _ItemSwitch(
                          id: str(b['id']),
                          name: str(b['name']),
                          usual: b['amount'] is num ? intOf(b['amount']) : null,
                          currency: str(b['currency'], context.currencyCode),
                        ),
                    ],
                  ),
                if (rules.isNotEmpty)
                  _Section(
                    title: t.simRules,
                    count: _changesIn(w, rules.map((r) => str(r['id']))),
                    children: <Widget>[
                      for (final r in rules)
                        _ItemSwitch(
                          id: str(r['id']),
                          name: str(r['label']).isNotEmpty
                              ? str(r['label'])
                              : ruleSentence(r),
                        ),
                    ],
                  ),
                if (goals.isNotEmpty)
                  _Section(
                    title: t.simGoals,
                    count: _changesIn(w, goals.map((g) => str(g['id']))),
                    children: <Widget>[
                      for (final g in goals)
                        _ItemSwitch(id: str(g['id']), name: str(g['name'])),
                    ],
                  ),
                _Section(
                  title: t.simTiming,
                  count: (w.lateDays > 0 ? 1 : 0) + (w.defer ? 1 : 0),
                  children: <Widget>[
                    Text(t.simLateDays(w.lateDays)),
                    Slider(
                      value: w.lateDays.toDouble(),
                      max: 60,
                      divisions: 60,
                      label: '${w.lateDays}',
                      semanticFormatterCallback: (v) =>
                          t.simLateDays(v.round()),
                      onChanged: (v) => edit.setLateDays(v.round()),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.simDefer),
                      value: w.defer,
                      onChanged: edit.setDefer,
                    ),
                  ],
                ),
                _Section(
                  title: t.simPretend,
                  count: w.extra.length,
                  children: <Widget>[
                    for (var i = 0; i < w.extra.length; i++)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(w.extra[i].label),
                        subtitle: Text(
                          '${w.extra[i].income ? t.simPretendIn : t.simPretendOut} · '
                          '${shortDay(context, w.extra[i].date)} · '
                          '${context.moneyMain(w.extra[i].amount)}',
                        ),
                        trailing: IconButton(
                          tooltip: t.simRemove(w.extra[i].label),
                          icon: const Icon(Icons.close),
                          onPressed: () => edit.removeEntry(i),
                        ),
                      ),
                    const _PretendForm(),
                  ],
                ),
              ],
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: close, child: Text(t.simDone)),
            ),
          ],
        );
      },
    );
  }
}

/// One ready-made choice as a full-width tile: what it does in a line, and a check mark (not only a colour) when it is on.
class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.title,
    required this.line,
    required this.on,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String line;
  final bool on;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: on,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      label: '$title. $line',
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.all(gapL),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? c.accent : c.line),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: gapS,
                    children: <Widget>[
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(color: enabled ? c.ink : c.muted),
                      ),
                      Text(line, style: TextStyle(color: c.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: gapM),
                Icon(
                  on ? Icons.check_circle : Icons.circle_outlined,
                  color: on ? c.accent : c.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A collapsed part of the form with the number of changes in it.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.count,
    required this.children,
  });

  final String title;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: gapM),
      shape: const Border(),
      collapsedShape: const Border(),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: count > 0
          ? Text(
              t.simSectionChanges(count),
              style: TextStyle(color: context.colors.info),
            )
          : null,
      children: children,
    );
  }
}

/// One payday, bill, rule or goal: on or off, and for a payday or bill another amount.
class _ItemSwitch extends ConsumerStatefulWidget {
  const _ItemSwitch({
    required this.id,
    required this.name,
    this.usual,
    this.currency,
  });

  final String id;
  final String name;

  /// The usual amount, as a hint; null when it has none or cannot be changed here.
  final int? usual;

  /// The currency of the amount field; null for a rule or a goal (no amount here).
  final String? currency;

  @override
  ConsumerState<_ItemSwitch> createState() => _ItemSwitchState();
}

class _ItemSwitchState extends ConsumerState<_ItemSwitch> {
  // -- STATES -- //

  late final TextEditingController _amount = TextEditingController(
    text: () {
      final set = ref.read(whatIfProvider).amounts[widget.id];
      final code = widget.currency;
      return set == null || code == null ? '' : plainAmountIn(set, code);
    }(),
  );

  // -- LIFECYCLES -- //

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final w = ref.watch(whatIfProvider);
    final on = !w.off.contains(widget.id);
    final code = widget.currency;
    final usual = widget.usual;
    return Column(
      children: <Widget>[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(widget.name),
          value: on,
          onChanged: (_) =>
              ref.read(whatIfProvider.notifier).toggleOff(widget.id),
        ),
        if (on && code != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: t.simAmountFor(widget.name),
                hintText: usual == null ? null : plainAmountIn(usual, code),
                suffixText: code,
              ),
              onChanged: (text) => ref
                  .read(whatIfProvider.notifier)
                  .setAmount(
                    widget.id,
                    text.trim().isEmpty ? null : parseMoney(text, code),
                  ),
            ),
          ),
      ],
    );
  }
}

/// A pretend entry: in or out, what it is, how much, on which day, in which account. Added to the what-if only, never saved.
class _PretendForm extends ConsumerStatefulWidget {
  const _PretendForm();

  @override
  ConsumerState<_PretendForm> createState() => _PretendFormState();
}

class _PretendFormState extends ConsumerState<_PretendForm> {
  // -- STATES -- //

  final TextEditingController _label = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  bool _income = false;
  DateTime _date = DateTime.now();
  String? _accountId;

  // -- FUNCTIONS -- //

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: earliestDay(today),
      lastDate: latestDay(today),
    );
    if (d != null && mounted) setState(() => _date = d);
  }

  void _add(List<Json> accounts) {
    final amount = context.parseAmountMain(_amount.text);
    final label = _label.text.trim();
    final account =
        _accountId ?? (accounts.isEmpty ? null : str(accounts.first['id']));
    if (amount == null || amount <= 0 || label.isEmpty || account == null)
      return;
    ref
        .read(whatIfProvider.notifier)
        .addEntry(
          PretendEntry(
            date: dayOf(_date),
            income: _income,
            accountId: account,
            amount: amount,
            label: label.length > 40 ? label.substring(0, 40) : label,
          ),
        );
    _label.clear();
    _amount.clear();
  }

  // -- LIFECYCLES -- //

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final accounts = ref.watch(balancesProvider).value ?? <Json>[];
    final chosen =
        _accountId ?? (accounts.isEmpty ? null : str(accounts.first['id']));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: gapM,
      children: <Widget>[
        Text(
          t.simPretendMainNote(context.currencyCode),
          style: TextStyle(color: context.colors.muted),
        ),
        SegmentedButton<bool>(
          segments: <ButtonSegment<bool>>[
            ButtonSegment<bool>(value: false, label: Text(t.simPretendOut)),
            ButtonSegment<bool>(value: true, label: Text(t.simPretendIn)),
          ],
          selected: <bool>{_income},
          onSelectionChanged: (s) => setState(() => _income = s.first),
        ),
        TextField(
          controller: _label,
          maxLength: 40,
          decoration: InputDecoration(labelText: t.simPretendLabel),
        ),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: t.simAmountFor(_label.text.isEmpty ? '…' : _label.text),
            suffixText: context.currencyCode,
          ),
        ),
        if (accounts.length > 1)
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: chosen,
            decoration: InputDecoration(labelText: t.simPretendAccount),
            items: <DropdownMenuItem<String>>[
              for (final a in accounts)
                DropdownMenuItem<String>(
                  value: str(a['id']),
                  child: Text(str(a['name'])),
                ),
            ],
            onChanged: (v) => setState(() => _accountId = v),
          ),
        Row(
          children: <Widget>[
            Expanded(
              child: TextButton(
                onPressed: _pickDate,
                child: Text(t.simPretendDate(shortDay(context, dayOf(_date)))),
              ),
            ),
            OutlinedButton(
              onPressed: () => _add(accounts),
              child: Text(t.simPretendAdd),
            ),
          ],
        ),
      ],
    );
  }
}
