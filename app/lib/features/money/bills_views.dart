// THE SWITCH ABOVE "COMING UP" ON THE BILLS SCREEN: THE SAME LIST, SECTIONED BY WEEK OR BY MONTH. IT IS NOT A CALENDAR (THE CALENDAR SCREEN HAS THOSE).
// It looks like the Calendar's tab bar: plain words in a row, the chosen one underlined in the accent, a quiet rule under both.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';

// -- CONSTANTS -- //

/// How the coming-up list is sectioned.
enum BillsGroup { week, month }

// -- TYPES -- //

/// Week or Month as two tabs, remembered by the screen.
class BillsGroupSwitch extends StatelessWidget {
  const BillsGroupSwitch({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final BillsGroup value;
  final ValueChanged<BillsGroup> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: <Widget>[
          for (final (g, label) in <(BillsGroup, String)>[
            (BillsGroup.week, t.billsViewWeek),
            (BillsGroup.month, t.billsViewMonth),
          ])
            Expanded(
              child: Semantics(
                button: true,
                selected: g == value,
                label: label,
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => onChanged(g),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: g == value
                                ? c.accent
                                : c.line.withValues(alpha: 0),
                            width: 2.5,
                          ),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: g == value ? c.ink : c.muted,
                                fontWeight: g == value
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
