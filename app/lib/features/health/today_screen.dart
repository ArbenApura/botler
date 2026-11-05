// TODAY: HOW MUCH IS LEFT, PROTEIN, WHAT WAS EATEN AND WHETHER THE DAY IS COMPLETE. NO RED FOR GOING OVER. ONE PRIMARY ACTION: LOG FOOD.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/api.dart';
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

// -- CONSTANTS -- //

const List<String> _mealOrder = <String>[
  'breakfast',
  'lunch',
  'merienda',
  'dinner',
  'snack',
];

// -- TYPES -- //

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    final day = ref.watch(foodDayProvider);
    final health = ref.watch(healthProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.healthTileToday),
        actions: <Widget>[
          TextButton(
            onPressed: () => context.push('/health/nutrients'),
            child: Text(t.healthDetails),
          ),
        ],
      ),
      body: AsyncBody<Json>(
        value: day,
        onRetry: () => ref.invalidate(foodDayProvider),
        skeleton: const SkeletonPage(
          child: SkeletonRows(count: 4, kind: SkeletonKind.tile),
        ),
        data: (d) {
          final entries = asJsonList(d['entries']);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(foodDayProvider),
            child: ListView(
              padding: pagePadding(context),
              children: <Widget>[
                _Summary(day: d, health: health),
                const SizedBox(height: 12),
                if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    child: Column(
                      children: <Widget>[
                        Text(
                          t.healthTileTodayEmpty,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t.healthTodayEmptyLine,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.muted),
                        ),
                      ],
                    ),
                  )
                else
                  PaperCard(
                    child: Column(
                      children: <Widget>[
                        for (final meal in _mealOrder)
                          if (entries.any((e) => str(e['meal']) == meal))
                            _MealRow(
                              meal: meal,
                              entries: entries
                                  .where((e) => str(e['meal']) == meal)
                                  .toList(),
                            ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                PaperCard(
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              t.healthDayComplete,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              t.healthDayCompleteLine,
                              style: TextStyle(color: c.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: boolOf(d['complete']),
                        onChanged: (on) => _markDay(context, ref, d, on),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: BottomDock(
        showAsk: true,
        primary: FilledButton.icon(
          onPressed: () => context.push('/health/camera'),
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(t.healthLogFood),
        ),
        below: TextButton(
          onPressed: () => showAddFoodSheet(context, ref),
          child: Text(t.healthAddByHand),
        ),
      ),
    );
  }

  Future<void> _markDay(
    BuildContext context,
    WidgetRef ref,
    Json day,
    bool on,
  ) async {
    try {
      await ref.read(apiProvider).verb('food_day_mark', <String, Object?>{
        'day': day['day'],
        'complete': on,
      }, newRequestId());
      ref.invalidate(foodDayProvider);
    } catch (e) {
      if (context.mounted) say(context, errorWords(e, context));
    }
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.day, required this.health});

  final Json day;
  final Json? health;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final totals = asJson(day['totals']);
    final eaten = intOf(totals['kcal']);
    final target = day['targetKcal'] == null ? null : intOf(day['targetKcal']);
    final left = target == null ? null : target - eaten;
    final protein = intOf(asJson(asJson(totals['core'])['proteinMg'])['mg']);
    final proteinTarget = health == null
        ? null
        : asJson(health?['goal'])['proteinTargetMg'];
    return PaperCard(
      child: Column(
        children: <Widget>[
          HealthRing(
            size: 196,
            stroke: 15,
            percent: target == null || target == 0 ? 0 : eaten * 100 ~/ target,
            label: left == null
                ? t.healthEatenKcal(kcalText(eaten))
                : t.healthLeftKcal(kcalText(left.abs())),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (left != null)
                  Text(
                    left >= 0 ? t.healthAbout : t.healthOverBy,
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                BigNumber(kcalText(left?.abs() ?? eaten), size: 48),
                Text(
                  left == null
                      ? t.healthKcalEaten
                      : (left >= 0 ? t.healthKcalLeft : t.healthKcalOver),
                  style: TextStyle(color: c.muted, fontSize: 14),
                ),
              ],
            ),
          ),
          if (target != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              t.healthEatenOf(kcalText(eaten), kcalText(target)),
              style: TextStyle(color: c.muted, fontSize: 14),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  t.healthProtein,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                proteinTarget == null
                    ? t.healthGrams(gramsFromMgText(protein))
                    : t.healthGramsOf(
                        gramsFromMgText(protein),
                        gramsFromMgText(intOf(proteinTarget)),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ThinBar(
            proteinTarget == null || intOf(proteinTarget) == 0
                ? 0
                : protein * 100 ~/ intOf(proteinTarget),
            color: c.info,
          ),
        ],
      ),
    );
  }
}

class _MealRow extends ConsumerWidget {
  const _MealRow({required this.meal, required this.entries});

  final String meal;
  final List<Json> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    int sum(String key) => entries.fold<int>(0, (a, e) => a + intOf(e[key]));
    final kcal = sum('kcal');
    final byBotler = entries.any((e) => boolOf(e['byAgent']));
    return InkWell(
      onTap: () => context.push('/health/meal/$meal'),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            IconTile(_iconOf(meal), size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    mealName(context, meal),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    entries.map((e) => str(e['name'])).join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                  Text(
                    t.healthMacroLine(
                      gramsFromMgText(sum('proteinMg')),
                      gramsFromMgText(sum('carbsMg')),
                      gramsFromMgText(sum('fatMg')),
                    ),
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 12,
                      fontFeatures: tabular,
                    ),
                  ),
                  if (byBotler) const ByBotlerMark(),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(kcalText(kcal), style: TextStyle(fontFeatures: tabular)),
            Icon(Icons.chevron_right, color: c.muted),
          ],
        ),
      ),
    );
  }

  IconData _iconOf(String meal) => switch (meal) {
    'breakfast' => Icons.wb_sunny_outlined,
    'lunch' => Icons.restaurant_outlined,
    'merienda' => Icons.local_cafe_outlined,
    'dinner' => Icons.dinner_dining_outlined,
    _ => Icons.cookie_outlined,
  };
}

/// The nutrients of a day. Unknown is shown as unknown and never counted as zero.
class NutrientsScreen extends ConsumerWidget {
  const NutrientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    final day = ref.watch(foodDayProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.healthDetailTitle)),
      body: AsyncBody<Json>(
        value: day,
        onRetry: () => ref.invalidate(foodDayProvider),
        data: (d) {
          final totals = asJson(d['totals']);
          final foods = intOf(totals['foods']);
          final core = asJson(totals['core']);
          Widget row(String name, String key, {String unit = 'g'}) {
            final v = asJson(core[key]);
            final unknown = intOf(v['unknownFoods']);
            final mg = intOf(v['mg']);
            final known = foods - unknown;
            return _NutrientRow(
              name: name,
              value: known == 0
                  ? t.healthUnknown
                  : (unit == 'g'
                        ? t.healthGrams(gramsFromMgText(mg))
                        : t.healthMilligrams(kcalText(mg))),
              note: unknown == 0 || known == 0
                  ? null
                  : t.healthKnownFor('$known', '$foods'),
            );
          }

          return ListView(
            padding: pagePadding(context),
            children: <Widget>[
              Text(
                t.healthFromFoods('$foods'),
                style: TextStyle(color: c.muted),
              ),
              const SizedBox(height: 12),
              PaperCard(
                child: Column(
                  children: <Widget>[
                    _NutrientRow(
                      name: t.healthCalories,
                      value: t.healthKcal(kcalText(intOf(totals['kcal']))),
                    ),
                    row(t.healthProtein, 'proteinMg'),
                    row(t.healthCarbs, 'carbsMg'),
                    row(t.healthSugar, 'sugarMg'),
                    row(t.healthFibre, 'fibreMg'),
                    row(t.healthFat, 'fatMg'),
                    row(t.healthSatFat, 'satFatMg'),
                    row(t.healthSodium, 'sodiumMg', unit: 'mg'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PaperCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      t.healthVitamins,
                      style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (asJsonList(totals['nutrients']).isEmpty)
                      Text(t.healthUnknown, style: TextStyle(color: c.muted)),
                    for (final n in asJsonList(totals['nutrients']))
                      _NutrientRow(
                        name: str(n['label']),
                        value: microText(intOf(n['ng']), str(n['unit'], 'mg')),
                        note: intOf(n['knownFoods']) == foods
                            ? null
                            : t.healthKnownFor(
                                '${intOf(n['knownFoods'])}',
                                '$foods',
                              ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                t.healthDataCredit,
                style: TextStyle(color: c.muted, fontSize: 13),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NutrientRow extends StatelessWidget {
  const _NutrientRow({required this.name, required this.value, this.note});

  final String name;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(name)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
              if (note != null)
                Text(
                  note ?? '',
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
