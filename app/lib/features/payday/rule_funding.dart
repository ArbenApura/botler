// A PAYDAY RULE THAT SAVES FOR A BILL (BTL-20261029-0119): THE "SAVES FOR" ROW ON A RULE CARD AND THE SHEET THAT PICKS THE BILL.
// Linking tells the split to pay that bill from what the rule saved instead of taking it from the pay a second time. Only a fixed rule into an
// account can save for a bill, and only for a bill paid from that same account in the main currency; the server checks the same and says why.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/marks.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- FUNCTIONS -- //

/// The bills [rule] can save for: switched on, in the main currency [main] and paid from the account the rule fills. Empty for a rule that
/// cannot save for a bill (a percentage, the rest, a goal, a retired rule).
List<Json> billsForRule(Json rule, List<Json> bills, String main) {
  final account = str(rule['targetAccountId']);
  if (str(rule['mode']) != 'fixed' ||
      account.isEmpty ||
      str(rule['status']) == 'retired') {
    return const <Json>[];
  }
  return bills
      .where(
        (b) =>
            b['active'] != false &&
            str(b['accountId']) == account &&
            str(b['currency'], main) == main,
      )
      .toList();
}

/// Opens the sheet that picks the bill [rule] saves for, or none, and saves it. True when something was saved.
Future<bool> pickSavesFor(
  BuildContext context,
  WidgetRef ref,
  Json rule,
  List<Json> bills,
) async {
  var chosen = str(rule['fundsBillId']);
  final done = await showFormSheet<bool>(
    context,
    title: context.t.ruleSavesForTitle,
    builder: (sheet, close) => SheetScope(
      texts: const <String>[],
      builder: (_, s) => StatefulBuilder(
        builder: (_, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              sheet.t.ruleSavesForHelp,
              style: TextStyle(color: sheet.colors.muted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                ChoiceChip(
                  label: Text(sheet.t.ruleSavesForNothing),
                  selected: chosen.isEmpty,
                  onSelected: (_) => setState(() => chosen = ''),
                ),
                // The bill it saves for now, when it is not one it could pick again (switched off, moved, or the list did not load)
                if (str(rule['fundsBillId']).isNotEmpty &&
                    !bills.any((b) => str(b['id']) == str(rule['fundsBillId'])))
                  ChoiceChip(
                    label: Text(str(rule['fundsBillName'])),
                    selected: chosen == str(rule['fundsBillId']),
                    onSelected: (_) =>
                        setState(() => chosen = str(rule['fundsBillId'])),
                  ),
                for (final b in bills)
                  ChoiceChip(
                    avatar: MarkBadge(
                      name: str(b['name']),
                      mark: markOf(b),
                      size: 24,
                    ),
                    label: Text(str(b['name'])),
                    selected: chosen == str(b['id']),
                    onSelected: (_) => setState(() => chosen = str(b['id'])),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: s.once.running()
                  ? null
                  : () async {
                      try {
                        final ran = await s.once.ok((key) async {
                          await ref.read(apiProvider).verb(
                            'rule_update',
                            <String, Object?>{
                              'ruleId': str(rule['id']),
                              'fundsBillId': chosen.isEmpty ? null : chosen,
                            },
                            key,
                          );
                        }, intent: 'saves:$chosen');
                        if (!ran) return;
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
    ),
  );
  if (done == true && context.mounted)
    say(context, context.t.ruleSavesForSaved);
  return done == true;
}

// -- TYPES -- //

/// The row under a rule that says which bill it saves for, or offers to pick one. One tap target of at least 48 dp.
class SavesForRow extends StatelessWidget {
  const SavesForRow({required this.billName, required this.onTap, super.key});

  /// The bill the rule saves for, or empty when none.
  final String billName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final linked = billName.isNotEmpty;
    return Semantics(
      button: true,
      label: context.t.ruleSavesForSemantic,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: <Widget>[
              Icon(
                linked ? Icons.savings_outlined : Icons.add_link,
                size: 18,
                color: linked ? c.accentText : c.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  linked
                      ? context.t.ruleSavesFor(billName)
                      : context.t.ruleSavesForNone,
                  style: TextStyle(color: linked ? c.accentText : c.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
