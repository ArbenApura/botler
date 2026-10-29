// THE WHAT-IF SHEET: SWITCH PAYDAYS, BILLS, RULES AND GOALS OFF, CHANGE AN AMOUNT, PAY BILLS LATE, DEFER WHAT CAN WAIT, OR ADD PRETEND MONEY
// (BTL-20261029-0117). Nothing here is saved: it edits the what-if in memory, the screen asks the server again after a short pause, and Reset
// on the band brings back the plan as it is. Ready-made chips fill the same what-if and can be changed after. The one primary action is Done.

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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(t.simWhatIfLine, style: TextStyle(color: c.muted)),
            const SizedBox(height: 12),
            Text(t.simPresets, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                ActionChip(
                  label: Text(t.simPresetSkipNext),
                  onPressed: () => edit.set(presetSkipNext(w, p)),
                ),
                ActionChip(
                  label: Text(t.simPresetLate),
                  onPressed: () => edit.set(presetLate(w)),
                ),
                ActionChip(
                  label: Text(t.simPresetNoRules),
                  onPressed: () => edit.set(presetNoRules(w, p)),
                ),
                ActionChip(
                  label: Text(t.simPresetPayUp),
                  onPressed: () => edit.set(presetPay(w, p, 10)),
                ),
                ActionChip(
                  label: Text(t.simPresetPayDown),
                  onPressed: () => edit.set(presetPay(w, p, -10)),
                ),
                ActionChip(
                  label: Text(t.simPresetDefer),
                  onPressed: () => edit.set(presetDefer(w)),
                ),
              ],
            ),
            if (incomes.isNotEmpty) ...<Widget>[
              _Heading(t.simPaydays),
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
                spacing: 8,
                children: <Widget>[
                  for (final u in asJsonList(p['upcoming']))
                    FilterChip(
                      label: Text(
                        '${str(u['label'])} · ${shortDay(context, str(u['payday']))}',
                      ),
                      selected: w.skipDates.contains(str(u['payday'])),
                      onSelected: (_) => edit.toggleSkip(str(u['payday'])),
                    ),
                ],
              ),
            ],
            if (bills.isNotEmpty) ...<Widget>[
              _Heading(t.simBills),
              for (final b in bills)
                _ItemSwitch(
                  id: str(b['id']),
                  name: str(b['name']),
                  usual: b['amount'] is num ? intOf(b['amount']) : null,
                  currency: str(b['currency'], context.currencyCode),
                ),
            ],
            if (rules.isNotEmpty) ...<Widget>[
              _Heading(t.simRules),
              for (final r in rules)
                _ItemSwitch(
                  id: str(r['id']),
                  name: str(r['label']).isNotEmpty
                      ? str(r['label'])
                      : ruleSentence(r),
                ),
            ],
            if (goals.isNotEmpty) ...<Widget>[
              _Heading(t.simGoals),
              for (final g in goals)
                _ItemSwitch(id: str(g['id']), name: str(g['name'])),
            ],
            _Heading(t.simLateDays(w.lateDays)),
            Slider(
              value: w.lateDays.toDouble(),
              max: 60,
              divisions: 60,
              label: '${w.lateDays}',
              semanticFormatterCallback: (v) => t.simLateDays(v.round()),
              onChanged: (v) => edit.setLateDays(v.round()),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.simDefer),
              value: w.defer,
              onChanged: edit.setDefer,
            ),
            _Heading(t.simPretend),
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
            const SizedBox(height: 16),
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

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
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
          DropdownButton<String>(
            isExpanded: true,
            value: chosen,
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
