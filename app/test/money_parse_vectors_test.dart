// THE PARSE RULE FOR TYPED AMOUNTS, AS SHARED VECTORS. THE SERVER'S TWIN (server/src/lib/finance/currency.ts) IS TESTED AGAINST THE SAME LIST IN
// server/tests/finance/parse-vectors.json; THIS FILE KEEPS THE LIST AND CHECKS THE JSON HAS NOT DRIFTED FROM IT.

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';

import 'package:botler/core/manila.dart';
import 'package:botler/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

// -- CONSTANTS -- //

// Currency code, what was typed, and the minor units it means (null: refused)
const List<(String, String, int?)> vectors = <(String, String, int?)>[
  ('PHP', '180', 18000),
  ('PHP', '1,250.50', 125050),
  ('PHP', '₱ 1,250.50', 125050),
  ('PHP', '₱ 90', 9000),
  ('PHP', 'php 12.5', 1250),
  ('PHP', '12,50', 1250),
  ('PHP', '1,25', 125),
  ('PHP', '1,250', 125000),
  ('PHP', '1,250,000', 125000000),
  ('PHP', '1,250,000.5', 125000050),
  ('PHP', '0,50', 50),
  ('PHP', '12,5', null),
  ('PHP', '1,2500', null),
  ('PHP', '1,25,000', null),
  ('PHP', '1.250,50', null),
  ('PHP', '12,50.5', null),
  ('PHP', '1.239', null),
  ('PHP', '12.345', null),
  ('PHP', '.5', null),
  ('PHP', '12.', null),
  ('PHP', 'abc', null),
  ('PHP', '', null),
  ('PHP', '99999999999999999', null),
  ('JPY', '1250', 1250),
  ('JPY', '1,250', 1250),
  ('JPY', '¥ 500', 500),
  ('JPY', 'jpy 500', 500),
  ('JPY', '12.5', null),
  ('JPY', '12,50', null),
  ('KWD', '5', 5000),
  ('KWD', 'kwd 5', 5000),
  ('KWD', '12.5', 12500),
  ('KWD', '1.250', 1250),
  ('KWD', '1,250.500', 1250500),
  ('KWD', '1,250', null),
  ('KWD', '12,500', null),
  ('KWD', '1,25', null),
  ('KWD', '1.2345', null),
  ('USD', 'usd 5', 500),
  ('USD', 'usd5', 500),
  ('USD', r'$5', 500),
  ('USD', r'$1,234.56', 123456),
  ('USD', '1,234', 123400),
  ('USD', '5,00', 500),
  ('USD', '5,0', null),
];

void main() {
  group('parseMoney vectors', () {
    for (final v in vectors) {
      test('${v.$1} "${v.$2}" is ${v.$3 ?? 'refused'}', () {
        expect(parseMoney(v.$2, v.$1), v.$3);
      });
    }

    test('the server\'s vector file lists the same cases', () {
      final file = File('../server/tests/finance/parse-vectors.json');
      if (!file.existsSync()) return;
      final decoded = jsonDecode(file.readAsStringSync()) as List<Object?>;
      final fromFile = <(String, String, int?)>[
        for (final e in decoded)
          if (e is Map<String, Object?>)
            (e['code']! as String, e['text']! as String, e['minor'] as int?),
      ];
      expect(fromFile, vectors);
    });
  });

  group('unknown currency', () {
    test('is neutral: its own code, two digits, never pesos', () {
      final c = currencyOf('XXX');
      expect(c.code, 'XXX');
      expect(c.digits, 2);
      expect(c.symbol.trim(), 'XXX');
      expect(formatMoney(100, 'XXX'), 'XXX 1.00');
      expect(parseMoney('5', 'XXX'), 500);
    });
  });

  group('dayOf', () {
    test('accepts real dates and rejects impossible ones', () {
      expect(dayOf('2026-02-28'), DateTime(2026, 2, 28));
      expect(dayOf('2028-02-29'), DateTime(2028, 2, 29));
      expect(dayOf('2026-02-30'), isNull);
      expect(dayOf('2026-13-01'), isNull);
      expect(dayOf('2026-04-31'), isNull);
      expect(dayOf('not a date'), isNull);
    });
  });
}
