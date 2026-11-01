// THE SWITCH ABOVE "COMING UP" ON THE BILLS SCREEN: THE SAME LIST, SECTIONED BY WEEK OR BY MONTH. IT IS NOT A CALENDAR (THE CALENDAR SCREEN HAS THOSE).

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../l10n/l10n.dart';

// -- CONSTANTS -- //

/// How the coming-up list is sectioned.
enum BillsGroup { week, month }

// -- TYPES -- //

/// Week or Month: one segmented control, remembered by the screen.
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
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<BillsGroup>(
        showSelectedIcon: false,
        segments: <ButtonSegment<BillsGroup>>[
          ButtonSegment<BillsGroup>(
            value: BillsGroup.week,
            label: Text(t.billsViewWeek),
          ),
          ButtonSegment<BillsGroup>(
            value: BillsGroup.month,
            label: Text(t.billsViewMonth),
          ),
        ],
        selected: <BillsGroup>{value},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}
