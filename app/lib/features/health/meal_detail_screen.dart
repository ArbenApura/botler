// ONE MEAL IN FULL: ITS CALORIES, WHERE THEY COME FROM, AND EVERY FOOD WITH ALL OF ITS NUTRIENTS. UNKNOWN IS SHOWN AS UNKNOWN, NEVER AS ZERO. NO RED FOR GOING OVER.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/health_units.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/health.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'food_sheets.dart';
import 'health_parts.dart';
import 'nutrient_line.dart';
import 'reading_screen.dart';

// -- CONSTANTS -- //

/// The labels and units of the nutrients a food can hold besides the main ones, by the server's code. Same words as the day's nutrients page.
const Map<String, (String, String)> _micro = <String, (String, String)>{
  'potassium': ('Potassium', 'mg'),
  'calcium': ('Calcium', 'mg'),
  'iron': ('Iron', 'mg'),
  'magnesium': ('Magnesium', 'mg'),
  'phosphorus': ('Phosphorus', 'mg'),
  'zinc': ('Zinc', 'mg'),
  'copper': ('Copper', 'mg'),
  'selenium': ('Selenium', 'µg'),
  'cholesterol': ('Cholesterol', 'mg'),
  'vitamin_a': ('Vitamin A', 'µg'),
  'vitamin_c': ('Vitamin C', 'mg'),
  'vitamin_d': ('Vitamin D', 'µg'),
  'vitamin_e': ('Vitamin E', 'mg'),
  'vitamin_k': ('Vitamin K', 'µg'),
  'thiamin': ('Thiamin', 'mg'),
  'riboflavin': ('Riboflavin', 'mg'),
  'niacin': ('Niacin', 'mg'),
  'vitamin_b6': ('Vitamin B6', 'mg'),
  'folate': ('Folate', 'µg'),
  'vitamin_b12': ('Vitamin B12', 'µg'),
};

// -- FUNCTIONS -- //

/// Calories a number of milligrams of a macro gives, in whole kcal (4, 4 and 9 per gram).
int _kcalOf(int mg, int perGram) => mg * perGram ~/ 1000;

// -- TYPES -- //

class MealDetailScreen extends ConsumerWidget {
  const MealDetailScreen({required this.meal, super.key});

  final String meal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final day = ref.watch(foodDayProvider);
    return Scaffold(
      appBar: AppBar(title: Text(mealName(context, meal))),
      body: AsyncBody<Json>(
        value: day,
        onRetry: () => ref.invalidate(foodDayProvider),
        skeleton: const SkeletonPage(
          child: SkeletonRows(count: 4, kind: SkeletonKind.tile),
        ),
        data: (d) {
          final entries = asJsonList(d['entries'])
              .where((e) => str(e['meal']) == meal)
              .toList();
          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  t.healthTileTodayEmpty,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(foodDayProvider),
            child: ListView(
              padding: pagePadding(context),
              children: <Widget>[
                _Header(entries: entries, targetKcal: d['targetKcal']),
                SectionTitle(t.healthMealFoods),
                for (final e in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _FoodCard(entry: e),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.entries, required this.targetKcal});

  final List<Json> entries;
  final Object? targetKcal;

  int _sum(String key) => entries.fold<int>(0, (a, e) => a + intOf(e[key]));

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final kcal = _sum('kcal');
    final protein = _sum('proteinMg');
    final carbs = _sum('carbsMg');
    final fat = _sum('fatMg');
    final pK = _kcalOf(protein, 4);
    final cK = _kcalOf(carbs, 4);
    final fK = _kcalOf(fat, 9);
    final total = pK + cK + fK;
    int share(int part) => total == 0 ? 0 : part * 100 ~/ total;
    final target = targetKcal == null ? null : intOf(targetKcal);
    final rough = entries.any((e) => intOf(e['lowKcal']) != intOf(e['kcal']));
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              BigNumber(kcalText(kcal), size: 44),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  t.healthKcalEaten,
                  style: TextStyle(color: c.muted, fontSize: 14),
                ),
              ),
            ],
          ),
          if (rough)
            Text(
              t.healthCouldBe(
                kcalText(_sum('lowKcal')),
                kcalText(_sum('highKcal')),
              ),
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
          if (target != null && target > 0)
            Text(
              t.healthMealOfDay('${kcal * 100 ~/ target}'),
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              _Macro(
                label: t.healthProtein,
                grams: protein,
                percent: share(pK),
                color: c.info,
              ),
              _Macro(
                label: t.healthCarbs,
                grams: carbs,
                percent: share(cK),
                color: c.accent,
              ),
              _Macro(
                label: t.healthFat,
                grams: fat,
                percent: share(fK),
                color: c.warning,
              ),
            ],
          ),
          if (total > 0) ...<Widget>[
            const SizedBox(height: 12),
            Semantics(
              label:
                  '${t.healthMacroSplit}: ${t.healthProtein} ${share(pK)}%, ${t.healthCarbs} ${share(cK)}%, ${t.healthFat} ${share(fK)}%',
              child: ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 10,
                    child: Row(
                      children: <Widget>[
                        for (final (part, color) in <(int, Color)>[
                          (pK, c.info),
                          (cK, c.accent),
                          (fK, c.warning),
                        ])
                          if (part > 0)
                            Expanded(
                              flex: part,
                              child: Container(
                                margin: const EdgeInsets.only(right: 1),
                                color: color,
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t.healthMacroSplit,
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _Macro extends StatelessWidget {
  const _Macro({
    required this.label,
    required this.grams,
    required this.percent,
    required this.color,
  });

  final String label;
  final int grams;
  final int percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    return Expanded(
      child: Semantics(
        label: '$label ${t.healthGrams(gramsFromMgText(grams))}',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.muted, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                t.healthGrams(gramsFromMgText(grams)),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  fontFeatures: tabular,
                ),
              ),
              Text(
                '$percent%',
                style: TextStyle(
                  color: c.muted,
                  fontSize: 12,
                  fontFeatures: tabular,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoodCard extends ConsumerStatefulWidget {
  const _FoodCard({required this.entry});

  final Json entry;

  @override
  ConsumerState<_FoodCard> createState() => _FoodCardState();
}

class _FoodCardState extends ConsumerState<_FoodCard> {
  // -- STATES -- //

  late final Once _once = Once(() => setState(() {}));

  // -- FUNCTIONS -- //

  Future<void> _call(String verb, Json args, String intent) async {
    try {
      await _once.run((key) async {
        await ref.read(apiProvider).verbJson(verb, args, key);
        ref.invalidate(foodDayProvider);
      }, intent: intent);
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
    }
  }

  Future<void> _grams(int change) async {
    final e = widget.entry;
    final next = intOf(e['grams']) + change;
    if (next < 1) return;
    await _call('food_edit', <String, Object?>{
      'entryId': e['id'],
      'grams': next,
    }, 'edit:${e['id']}:$next');
  }

  /// One nutrient line: unknown is a word, not a zero.
  // The line itself is shared with the review and the barcode result (nutrient_line.dart)
  Widget _line(String name, int? mg, {bool inMg = false}) =>
      NutrientLine(name: name, mg: mg, inMg: inMg);

  int? _mg(String key) =>
      widget.entry[key] == null ? null : intOf(widget.entry[key]);

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final e = widget.entry;
    final grams = e['grams'];
    final extras = asJson(e['nutrients']);
    final known = <(String, String, int)>[
      for (final k in _micro.keys)
        if (extras[k] != null)
          (_micro[k]?.$1 ?? k, _micro[k]?.$2 ?? 'mg', intOf(extras[k])),
    ];
    final rough = intOf(e['lowKcal']) != intOf(e['kcal']);
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      str(e['name']),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      <String>[
                        if (grams != null) t.healthGrams('${intOf(grams)}'),
                        sourceWord(context, str(e['sourceKind'])),
                      ].join(' · '),
                      style: TextStyle(color: c.muted, fontSize: 13),
                    ),
                    if (boolOf(e['byAgent'])) const ByBotlerMark(),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    t.healthKcal(kcalText(intOf(e['kcal']))),
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontFeatures: tabular,
                    ),
                  ),
                  if (rough)
                    Text(
                      t.healthCouldBe(
                        kcalText(intOf(e['lowKcal'])),
                        kcalText(intOf(e['highKcal'])),
                      ),
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
                ],
              ),
            ],
          ),
          const Divider(height: 20),
          _line(t.healthProtein, _mg('proteinMg')),
          _line(t.healthCarbs, _mg('carbsMg')),
          _line(t.healthSugar, _mg('sugarMg')),
          _line(t.healthFibre, _mg('fibreMg')),
          _line(t.healthFat, _mg('fatMg')),
          _line(t.healthSatFat, _mg('satFatMg')),
          _line(t.healthSodium, _mg('sodiumMg'), inMg: true),
          if (known.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: c.paper),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  t.healthVitamins,
                  style: TextStyle(color: c.muted, fontWeight: FontWeight.w500),
                ),
                children: <Widget>[
                  for (final (name, unit, ng) in known)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: <Widget>[
                          Expanded(child: Text(name)),
                          Text(
                            microText(ng, unit),
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontFeatures: tabular,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Row(
            children: <Widget>[
              if (grams != null) ...<Widget>[
                IconButton(
                  tooltip: t.healthLess,
                  onPressed: _once.running() ? null : () => _grams(-10),
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  tooltip: t.healthMore,
                  onPressed: _once.running() ? null : () => _grams(10),
                  icon: const Icon(Icons.add),
                ),
              ],
              const Spacer(),
              TextButton(
                onPressed: _once.running()
                    ? null
                    : () => _call('food_delete', <String, Object?>{
                        'entryId': e['id'],
                      }, 'delete:${e['id']}'),
                child: Text(t.healthRemove),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
