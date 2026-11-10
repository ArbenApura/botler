// ONE NUTRIENT LINE: A NAME AND ITS AMOUNT. UNKNOWN IS A WORD, NEVER A ZERO. SHARED BY THE MEAL DETAIL, THE MEAL REVIEW AND THE BARCODE RESULT
// (BTL-20261110-1532: it lived inside the meal detail before, and the review and the barcode result showed no sugar, fibre or saturated fat).

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';

// -- MODULES -- //
import '../../core/health_units.dart';
import '../../l10n/l10n.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';

// -- FUNCTIONS -- //

/// Grams with one decimal under ten, so 2.4 g of sugar is not shown as 2.
String smallGramsText(int mg) {
  if (mg >= 10000) return gramsFromMgText(mg);
  final tenths = (mg / 100).round();
  return tenths % 10 == 0
      ? '${tenths ~/ 10}'
      : '${tenths ~/ 10}.${tenths % 10}';
}

/// A value of a server answer as milligrams, or null when the server did not know it. Never zero for unknown.
int? mgOrNull(Object? value) => value is num ? value.round() : null;

// -- WIDGETS -- //

/// One nutrient line. [mg] null means the food does not know it. [note] is a short word under the name, such as "known for 2 of 3 foods".
class NutrientLine extends StatelessWidget {
  const NutrientLine({
    super.key,
    required this.name,
    required this.mg,
    this.inMg = false,
    this.note,
  });

  final String name;
  final int? mg;

  /// Sodium is shown in milligrams, everything else in grams.
  final bool inMg;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final amount = mg;
    final value = amount == null
        ? t.healthUnknown
        : inMg
        ? t.healthMilligrams(kcalText(amount))
        : t.healthGrams(smallGramsText(amount));
    final hint = note;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(
            child: hint == null
                ? Text(name)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(name),
                      Text(
                        hint,
                        style: TextStyle(color: c.muted, fontSize: 12),
                      ),
                    ],
                  ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontFeatures: tabular,
              color: amount == null ? c.muted : null,
            ),
          ),
        ],
      ),
    );
  }
}
