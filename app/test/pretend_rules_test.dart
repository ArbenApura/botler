// THE PURE RULES OF THE WHAT-IF SHEET AND OF "IN A YEAR": A PERCENT CHANGE ROUNDED HALF UP IN WHOLE MINOR UNITS, THE LIMITS OF A PRETEND ENTRY, AND THE
// PAYDAYS A YEAR OF A SCHEDULE.

// -- DEP-MODULES -- //
import 'package:flutter_test/flutter_test.dart';

// -- MODULES -- //
import 'package:botler/features/money/payday_count.dart';
import 'package:botler/features/simulate/pretend_rules.dart';

// -- FUNCTIONS -- //

void main() {
  group('scaleByPercent', () {
    test('rounds a half up, in integers', () {
      expect(scaleByPercent(1050, -10), 945);
      expect(scaleByPercent(5, 10), 6);
      expect(scaleByPercent(4, 10), 4);
      expect(scaleByPercent(15, -10), 14);
      expect(scaleByPercent(1, -10), 1);
      expect(scaleByPercent(0, 10), 0);
      expect(scaleByPercent(2500000, 10), 2750000);
    });

    test('is exact for a large amount', () {
      expect(scaleByPercent(1000000000000, 10), 1100000000000);
      expect(scaleByPercent(999999999999, -10), 899999999999);
    });

    test('plus and minus ten percent of 100 cents', () {
      expect(scaleByPercent(100, 10), 110);
      expect(scaleByPercent(100, -10), 90);
    });
  });

  group('pretend entries', () {
    test('the amount must be at least 1 and at most 1e12 minor units', () {
      expect(pretendAmountOk(0), isFalse);
      expect(pretendAmountOk(-5), isFalse);
      expect(pretendAmountOk(1), isTrue);
      expect(pretendAmountOk(1000000000000), isTrue);
      expect(pretendAmountOk(1000000000001), isFalse);
    });

    test('there are at most fifty', () {
      expect(maxPretendEntries, 50);
    });
  });

  group('paydaysPerYear', () {
    test('counts by the kind of schedule', () {
      expect(paydaysPerYear(<String, Object?>{'kind': 'semi_monthly'}), 24);
      expect(
        paydaysPerYear(<String, Object?>{'kind': 'monthly', 'day': 15}),
        12,
      );
      expect(
        paydaysPerYear(<String, Object?>{'kind': 'monthly', 'everyMonths': 3}),
        4,
      );
      expect(
        paydaysPerYear(<String, Object?>{'kind': 'every_n_days', 'n': 14}),
        26,
      );
      expect(
        paydaysPerYear(<String, Object?>{
          'kind': 'weekly',
          'days': <int>[1, 5],
        }),
        104,
      );
      expect(
        paydaysPerYear(<String, Object?>{
          'kind': 'weekly',
          'days': <int>[5],
          'everyWeeks': 2,
        }),
        26,
      );
      expect(paydaysPerYear(<String, Object?>{'kind': 'yearly'}), 1);
    });

    test('an unknown kind or a single date is not guessed', () {
      expect(paydaysPerYear(<String, Object?>{'kind': 'once'}), isNull);
      expect(paydaysPerYear(<String, Object?>{'kind': 'lunar'}), isNull);
      expect(paydaysPerYear(const <String, Object?>{}), isNull);
      expect(
        paydaysPerYear(<String, Object?>{'kind': 'every_n_days', 'n': 0}),
        isNull,
      );
    });

    test('the first active payday with a known schedule decides', () {
      expect(
        paydaysPerYearOf(<Map<String, Object?>>[
          <String, Object?>{
            'active': false,
            'schedule': <String, Object?>{'kind': 'semi_monthly'},
          },
          <String, Object?>{
            'active': true,
            'schedule': <String, Object?>{'kind': 'monthly'},
          },
        ]),
        12,
      );
      expect(paydaysPerYearOf(const <Map<String, Object?>>[]), isNull);
    });
  });
}
