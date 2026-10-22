// "WHEN?" FOR A BILL OR A PAYDAY, IN PLAIN CHOICES: ONCE A MONTH ON A DAY, TWICE A MONTH ON TWO DAYS, OR EVERY SO MANY DAYS FROM A DATE.
// The server checks the schedule again and explains any problem in words.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../theme/tokens.dart';

// -- TYPES -- //

enum ScheduleKind { monthly, semiMonthly, everyN }

class ScheduleValue {
  ScheduleValue({
    this.kind = ScheduleKind.monthly,
    this.day = 1,
    this.day2 = 15,
    this.n = 14,
    DateTime? anchor,
  }) : anchor = anchor ?? DateTime.now();

  ScheduleKind kind;
  int day;
  int day2;
  int n;
  DateTime anchor;

  /// The schedule as the server takes it.
  Json toJson() => switch (kind) {
    ScheduleKind.monthly => <String, Object?>{'kind': 'monthly', 'day': day},
    ScheduleKind.semiMonthly => <String, Object?>{
      'kind': 'semi_monthly',
      'days': <int>[day, day2],
    },
    ScheduleKind.everyN => <String, Object?>{
      'kind': 'every_n_days',
      'anchor': DateFormat('yyyy-MM-dd').format(anchor),
      'n': n,
    },
  };
}

class SchedulePicker extends StatefulWidget {
  const SchedulePicker({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final ScheduleValue value;
  final VoidCallback onChanged;

  @override
  State<SchedulePicker> createState() => _SchedulePickerState();
}

class _SchedulePickerState extends State<SchedulePicker> {
  ScheduleValue get v => widget.value;

  void _set(VoidCallback change) {
    setState(change);
    widget.onChanged();
  }

  Widget _dayDropdown(String label, int value, ValueChanged<int> onPick) =>
      Expanded(
        child: DropdownButtonFormField<int>(
          // ignore: deprecated_member_use
          value: value,
          decoration: InputDecoration(labelText: label),
          items: <DropdownMenuItem<int>>[
            for (var d = 1; d <= 31; d++)
              DropdownMenuItem<int>(value: d, child: Text('$d')),
          ],
          onChanged: (d) => d == null ? null : onPick(d),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('How often?', style: TextStyle(color: c.muted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            ChoiceChip(
              label: const Text('Once a month'),
              selected: v.kind == ScheduleKind.monthly,
              onSelected: (_) => _set(() => v.kind = ScheduleKind.monthly),
            ),
            ChoiceChip(
              label: const Text('Twice a month'),
              selected: v.kind == ScheduleKind.semiMonthly,
              onSelected: (_) => _set(() => v.kind = ScheduleKind.semiMonthly),
            ),
            ChoiceChip(
              label: const Text('Every few days'),
              selected: v.kind == ScheduleKind.everyN,
              onSelected: (_) => _set(() => v.kind = ScheduleKind.everyN),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (v.kind == ScheduleKind.monthly)
          Row(
            children: <Widget>[
              _dayDropdown(
                'On which day?',
                v.day,
                (d) => _set(() => v.day = d),
              ),
            ],
          ),
        if (v.kind == ScheduleKind.semiMonthly)
          Row(
            children: <Widget>[
              _dayDropdown('First day', v.day, (d) => _set(() => v.day = d)),
              const SizedBox(width: 12),
              _dayDropdown('Second day', v.day2, (d) => _set(() => v.day2 = d)),
            ],
          ),
        if (v.kind == ScheduleKind.everyN)
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<int>(
                  // ignore: deprecated_member_use
                  value: v.n,
                  decoration: const InputDecoration(
                    labelText: 'Every how many days?',
                  ),
                  items: <DropdownMenuItem<int>>[
                    for (final n in <int>[7, 10, 14, 15, 28, 30])
                      DropdownMenuItem<int>(value: n, child: Text('$n days')),
                  ],
                  onChanged: (n) => n == null ? null : _set(() => v.n = n),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: v.anchor,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      helpText: 'A day it falls on',
                    );
                    if (d != null) _set(() => v.anchor = d);
                  },
                  child: Text(
                    'From ${DateFormat('MMM d, y').format(v.anchor)}',
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
