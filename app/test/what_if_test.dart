// THE WHAT-IF: READY-MADE ONES BUILD THE SAME SHAPE AS HAND-MADE ONES, A SWITCH CHANGES THE REQUEST, AND RESET BRINGS THE PLAN BACK.

// -- DEP-MODULES -- //
import 'package:botler/core/json.dart';
import 'package:botler/features/simulate/simulate_data.dart';
import 'package:botler/features/simulate/what_if_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// -- CONSTANTS -- //

final Json plan = <String, Object?>{
  'incomes': <Object?>[
    <String, Object?>{
      'id': 'i1',
      'label': 'Salary',
      'expectedAmount': 2500000,
      'active': true,
    },
    <String, Object?>{
      'id': 'i2',
      'label': 'Freelance',
      'expectedAmount': null,
      'active': true,
    },
  ],
  'rules': <Object?>[
    <String, Object?>{'id': 'r1'},
    <String, Object?>{'id': 'r2'},
  ],
  'upcoming': <Object?>[
    <String, Object?>{
      'incomeId': 'i1',
      'label': 'Salary',
      'payday': '2026-11-13',
    },
    <String, Object?>{
      'incomeId': 'i1',
      'label': 'Salary',
      'payday': '2026-11-30',
    },
  ],
};

// -- TESTS -- //

void main() {
  test('ready-made what-ifs fill the same shape', () {
    const w = WhatIf();
    expect(presetSkipNext(w, plan).skipDates, <String>{'2026-11-13'});
    expect(presetLate(w).lateDays, 7);
    expect(presetNoRules(w, plan).off, <String>{'r1', 'r2'});
    // A pay with no amount is left alone; 10% is rounded down to the minor unit
    expect(presetPay(w, plan, 10).amounts, <String, int>{'i1': 2750000});
    expect(presetPay(w, plan, -10).amounts, <String, int>{'i1': 2250000});
    expect(presetDefer(w).defer, isTrue);
    // Presets add up and can be edited after
    final both = presetLate(presetNoRules(w, plan));
    expect(both.changes, 3);
    expect(both.copyWith(lateDays: 0).changes, 2);
    expect(presetSkipNext(w, const <String, Object?>{}).isEmpty, isTrue);
  });

  test('a switch, an amount and a pretend entry change the request; Reset clears it', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final edit = container.read(whatIfProvider.notifier)
      ..toggleOff('b1')
      ..setAmount('i1', 3000000)
      ..toggleSkip('2026-11-13')
      ..addEntry(
        const PretendEntry(
          date: '2026-12-01',
          income: false,
          accountId: 'a1',
          amount: 70000,
          label: 'Phone',
        ),
      );
    final w = container.read(whatIfProvider);
    expect(w.changes, 4);
    expect(w.toJson(), <String, Object?>{
      'off': <String>['b1'],
      'amounts': <Json>[
        <String, Object?>{'id': 'i1', 'amount': 3000000},
      ],
      'skipDates': <String>['2026-11-13'],
      'extra': <Json>[
        <String, Object?>{
          'date': '2026-12-01',
          'kind': 'out',
          'accountId': 'a1',
          'amount': 70000,
          'label': 'Phone',
        },
      ],
    });
    // The same switch again turns it back on; an empty amount takes the change away
    edit
      ..toggleOff('b1')
      ..setAmount('i1', null)
      ..removeEntry(0);
    expect(container.read(whatIfProvider).changes, 1);
    edit.reset();
    expect(container.read(whatIfProvider).isEmpty, isTrue);
  });
}
