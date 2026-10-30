// THE PAYDAY SCREEN'S ACTIONS THAT CHANGE OR REMOVE THINGS: ADD OR CHANGE A PAYDAY, DELETE A PAYDAY, DELETE ONE SPLIT OR ALL OF THEM.
// Every delete says what it does in words first. Deleting a split never touches money that was already recorded unless the person switches that on,
// and a payday with earlier splits is deleted together with them only after the person has been told so.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/money_scope.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import '../money/schedule_picker.dart';

// -- FUNCTIONS -- //

/// A filled button in the danger colour, for the one destructive action of a sheet.
ButtonStyle _dangerStyle(BuildContext context) => FilledButton.styleFrom(
  backgroundColor: context.colors.danger,
  foregroundColor: context.colors.paper,
);

/// Asks, then deletes one split ([plan]) or every split (no [plan]). True when something was deleted. The switch that also takes the pay and
/// the transfers out of the balances is off to begin with, and is offered only where there can be such entries.
Future<bool> deleteSplitSheet(
  BuildContext context,
  WidgetRef ref, {
  Json? plan,
}) async {
  final all = plan == null;
  final approved = !all && str(plan['status']) == 'approved';
  var entries = false;
  final done = await showFormSheet<bool>(
    context,
    title: all ? context.t.splitClearAllTitle : context.t.splitDeleteTitle,
    builder: (sheet, close) => StatefulBuilder(
      builder: (_, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            all
                ? sheet.t.splitClearAllBody
                : sheet.t.splitDeleteBody(
                    str(plan['payday']),
                    sheet.moneyMain(intOf(plan['pay'])),
                  ),
          ),
          if (all || approved) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              sheet.t.splitDeleteKeepsMoney,
              style: TextStyle(color: sheet.colors.muted),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(sheet.t.splitDeleteEntriesSwitch),
              subtitle: entries ? Text(sheet.t.splitDeleteEntriesHelp) : null,
              value: entries,
              onChanged: (v) => setState(() => entries = v),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            style: _dangerStyle(sheet),
            onPressed: () async {
              try {
                await ref.read(apiProvider).verb(
                  'split_delete',
                  <String, Object?>{
                    if (all) 'all': true else 'splitId': str(plan['id']),
                    if (entries) 'removeEntries': true,
                  },
                );
                close(true);
              } catch (e) {
                if (sheet.mounted) say(sheet, errorWords(e, context));
              }
            },
            child: Text(
              all ? sheet.t.splitClearAllYes : sheet.t.splitDeleteYes,
            ),
          ),
        ],
      ),
    ),
  );
  if (done == true && context.mounted) {
    say(context, all ? context.t.splitCleared : context.t.splitDeleted);
  }
  return done == true;
}

/// Deletes a payday after asking. A payday with earlier splits goes together with them, and the person is told so first. True when deleted.
Future<bool> deleteIncomeFlow(
  BuildContext context,
  WidgetRef ref,
  Json income,
) async {
  final api = ref.read(apiProvider);
  var hasSplits = false;
  try {
    final splits = await api.verbList('split_list', <String, Object?>{
      'limit': 50,
      'includeReplaced': true,
    });
    hasSplits = splits.any(
      (s) => str(s['incomeScheduleId']) == str(income['id']),
    );
  } catch (_) {
    // Not knowing is safe: the server keeps a payday with splits and switches it off, and the answer says so
  }
  if (!context.mounted) return false;
  final label = str(income['label']);
  final yes = await confirm(
    context,
    title: context.t.paydayDeleteTitle,
    body: hasSplits
        ? context.t.paydayDeleteWithSplitsBody(label)
        : context.t.paydayDeleteBody(label),
    yes: context.t.paydayDeleteYes,
    danger: true,
  );
  if (!yes || !context.mounted) return false;
  try {
    await api.verb('income_delete', <String, Object?>{
      'incomeId': str(income['id']),
      if (hasSplits) 'withSplits': true,
    });
    if (context.mounted) say(context, context.t.paydayDeleted);
    return true;
  } catch (e) {
    if (context.mounted) say(context, errorWords(e, context));
    return false;
  }
}

/// The form for a payday: add one (no [existing]) or change one. A changed payday keeps its weekend rule, and a schedule the picker cannot
/// show is replaced only if the person changes it. True when something was saved or deleted.
Future<bool> incomeSheet(
  BuildContext context,
  WidgetRef ref, {
  Json? existing,
}) async {
  final editing = existing != null;
  final label = TextEditingController(
    text: editing ? str(existing['label']) : context.t.paydayIncomeDefault,
  );
  final amount = TextEditingController(
    text: editing && existing['expectedAmount'] is int
        ? context.plainAmountMain(intOf(existing['expectedAmount']))
        : '',
  );
  final schedule =
      (editing ? ScheduleValue.fromJson(asJson(existing['schedule'])) : null) ??
      ScheduleValue(pattern: SchedulePattern.semiMonthly, day: 15, day2: 30);
  final accounts = await ref.read(balancesProvider.future);
  var accountId = editing
      ? str(existing['accountId'])
      : str(accounts.firstOrNull?['id']);
  if (!context.mounted) return false;
  final weekend = editing ? str(existing['weekendRule'], 'before') : 'before';
  final result = await showFormSheet<String>(
    context,
    title: editing ? context.t.paydayEditTitle : context.t.paydayIncomeTitle,
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
            weekend: weekend,
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
                  editing ? 'income_update' : 'income_create',
                  <String, Object?>{
                    if (editing) 'incomeId': str(existing['id']),
                    'label': label.text.trim(),
                    'accountId': accountId,
                    'expectedAmount': cents,
                    'schedule': schedule.toJson(),
                    'weekendRule': weekend,
                  },
                );
                close('saved');
              } catch (e) {
                if (sheet.mounted) say(sheet, errorWords(e, context));
              }
            },
            child: Text(sheet.t.save),
          ),
          if (editing)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => close('delete'),
                child: Text(
                  sheet.t.paydayDeleteButton,
                  style: TextStyle(color: sheet.colors.danger),
                ),
              ),
            ),
        ],
      ),
    ),
  );
  if (result == 'delete' && editing && context.mounted) {
    return deleteIncomeFlow(context, ref, existing);
  }
  return result == 'saved';
}
