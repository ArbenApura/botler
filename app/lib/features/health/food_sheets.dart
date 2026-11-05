// THE SHEETS OF THE FOOD SCREENS: ADD A FOOD BY HAND (IT WAITS ON THE PHONE WHEN OFFLINE), AND FIX OR REMOVE THE FOODS OF A MEAL. THE SERVER WORKS OUT EVERY NUMBER.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/health_units.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/health.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';

// -- FUNCTIONS -- //

/// The name of a meal in the app's language.
String mealName(BuildContext context, String meal) {
  final t = context.t;
  return switch (meal) {
    'breakfast' => t.healthMealBreakfast,
    'lunch' => t.healthMealLunch,
    'merienda' => t.healthMealMerienda,
    'dinner' => t.healthMealDinner,
    _ => t.healthMealSnack,
  };
}

/// A nutrient amount in nanograms, in the unit people read it in. 0.04 µg stays 0.04, it is not rounded away.
String microText(int ng, String unit) {
  final isMicro = unit == 'µg';
  final per = isMicro ? 1000 : 1000000;
  final hundredths = (ng * 100 / per).round();
  final whole = hundredths ~/ 100;
  final part = hundredths % 100;
  final digits = part == 0
      ? '$whole'
      : part % 10 == 0
      ? '$whole.${part ~/ 10}'
      : '$whole.${part.toString().padLeft(2, '0')}';
  return '$digits $unit';
}

Future<void> showAddFoodSheet(BuildContext context, WidgetRef ref) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AddFoodSheet(),
    );

Future<void> showMealSheet(
  BuildContext context,
  WidgetRef ref,
  String title,
  List<Json> entries,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _MealSheet(title: title, entries: entries),
);

// -- TYPES -- //

/// A quiet line that says the assistant made an entry.
class ByBotlerMark extends StatelessWidget {
  const ByBotlerMark({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.auto_awesome_outlined, size: 13, color: c.accentText),
          const SizedBox(width: 4),
          Text(
            context.t.healthByBotler,
            style: TextStyle(color: c.accentText, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AddFoodSheet extends ConsumerStatefulWidget {
  const _AddFoodSheet();

  @override
  ConsumerState<_AddFoodSheet> createState() => _AddFoodSheetState();
}

class _AddFoodSheetState extends ConsumerState<_AddFoodSheet> {
  // -- STATES -- //

  final TextEditingController _name = TextEditingController();
  final TextEditingController _kcal = TextEditingController();
  final TextEditingController _protein = TextEditingController();
  late final Once _once = Once(() => setState(() {}));
  String? _error;

  // -- LIFECYCLES -- //

  @override
  void dispose() {
    _name.dispose();
    _kcal.dispose();
    _protein.dispose();
    super.dispose();
  }

  // -- FUNCTIONS -- //

  Future<void> _save() async {
    final t = context.t;
    final kcal = int.tryParse(_kcal.text.trim());
    final name = _name.text.trim();
    if (name.isEmpty || kcal == null) {
      setState(() => _error = t.healthAddNeeds);
      return;
    }
    final protein = thousandthsFromText(_protein.text);
    final args = <String, Object?>{
      'items': <Json>[
        <String, Object?>{
          'manual': <String, Object?>{
            'name': name,
            'kcal': kcal,
            'proteinMg': ?protein,
          },
        },
      ],
    };
    try {
      await _once.run((key) async {
        final queued = await writeOrQueue(ref, 'meal_log', args, key);
        ref.invalidate(foodDayProvider);
        if (!mounted) return;
        if (queued) say(context, t.healthSavedOffline);
        Navigator.of(context).pop();
      }, intent: args.toString());
    } catch (e) {
      if (mounted) setState(() => _error = errorWords(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            t.healthAddByHand,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Field(controller: _name, label: t.healthAddName, maxLength: 120),
          Field(
            controller: _kcal,
            label: t.healthAddKcal,
            keyboard: TextInputType.number,
          ),
          Field(
            controller: _protein,
            label: t.healthAddProtein,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          if (_error != null) Note(_error ?? ''),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _once.running() ? null : _save,
            child: Text(t.healthSave),
          ),
        ],
      ),
    );
  }
}

class _MealSheet extends ConsumerStatefulWidget {
  const _MealSheet({required this.title, required this.entries});

  final String title;
  final List<Json> entries;

  @override
  ConsumerState<_MealSheet> createState() => _MealSheetState();
}

class _MealSheetState extends ConsumerState<_MealSheet> {
  // -- STATES -- //

  late List<Json> _entries = widget.entries;
  late final Once _once = Once(() => setState(() {}));

  // -- FUNCTIONS -- //

  Future<void> _grams(Json e, int change) async {
    final now = intOf(e['grams']);
    final next = now + change;
    if (next < 1) return;
    await _call('food_edit', <String, Object?>{
      'entryId': e['id'],
      'grams': next,
    }, 'edit:${e['id']}:$next');
  }

  Future<void> _remove(Json e) => _call('food_delete', <String, Object?>{
    'entryId': e['id'],
  }, 'delete:${e['id']}');

  Future<void> _call(String verb, Json args, String intent) async {
    try {
      await _once.run((key) async {
        final r = await ref.read(apiProvider).verbJson(verb, args, key);
        ref.invalidate(foodDayProvider);
        final today = asJson(r['today']);
        final meal = str(_entries.first['meal']);
        if (mounted) {
          setState(() {
            _entries = asJsonList(today['entries'])
                .where((x) => str(x['meal']) == meal)
                .toList();
          });
          if (_entries.isEmpty) Navigator.of(context).pop();
        }
      }, intent: intent);
    } on ApiException catch (e) {
      if (mounted) say(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: <Widget>[
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final e in _entries) ...<Widget>[
              Row(
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
                          t.healthCouldBe(
                            kcalText(intOf(e['lowKcal'])),
                            kcalText(intOf(e['highKcal'])),
                          ),
                          style: TextStyle(color: c.muted, fontSize: 13),
                        ),
                        if (boolOf(e['byAgent'])) const ByBotlerMark(),
                      ],
                    ),
                  ),
                  Text(t.healthKcal(kcalText(intOf(e['kcal'])))),
                ],
              ),
              Row(
                children: <Widget>[
                  if (e['grams'] != null) ...<Widget>[
                    IconButton(
                      tooltip: t.healthLess,
                      onPressed: _once.running() ? null : () => _grams(e, -10),
                      icon: const Icon(Icons.remove),
                    ),
                    Text(t.healthGrams('${intOf(e['grams'])}')),
                    IconButton(
                      tooltip: t.healthMore,
                      onPressed: _once.running() ? null : () => _grams(e, 10),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                  const Spacer(),
                  TextButton(
                    onPressed: _once.running() ? null : () => _remove(e),
                    child: Text(t.healthRemove),
                  ),
                ],
              ),
              const Divider(),
            ],
          ],
        ),
      ),
    );
  }
}
