// CHECK YOUR MEAL: EVERY FOOD THE PHOTO OR LABEL GAVE, WITH WHERE ITS NUMBERS CAME FROM. THE PERSON CHANGES AMOUNTS, REMOVES OR ADDS FOODS, AND ONLY SAVE MEAL WRITES ANYTHING.
// The numbers shown come from the server's preview of exactly what would be saved. Approving sends what was corrected, and the server works it all out again.

// -- DEP-MODULES -- //
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/health_units.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/food_camera.dart';
import '../../state/health.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/markdown_kit.dart';
import '../../ui/ui.dart';
import 'camera_screen.dart';
import 'health_parts.dart';
import 'reading_screen.dart';

// -- TYPES -- //

class MealReviewScreen extends ConsumerStatefulWidget {
  const MealReviewScreen({
    required this.actionId,
    required this.args,
    this.note,
    this.photo,
    this.mode = 'meal',
    this.resend,
    super.key,
  });

  final String actionId;
  final Json args;
  final String? note;

  /// The first photo, on this phone only. It is deleted when the review closes.
  final String? photo;

  /// What the photo was taken as: 'meal' or 'label'.
  final String mode;

  /// Test hook: what sends the person's correction. The food camera does it otherwise.
  final Future<FoodCameraResult> Function(String correction)? resend;

  @override
  ConsumerState<MealReviewScreen> createState() => _MealReviewScreenState();
}

class _MealReviewScreenState extends ConsumerState<MealReviewScreen> {
  // -- STATES -- //

  late List<Json> _items = asJsonList(widget.args['items'])
      .map(Map<String, Object?>.of)
      .toList();
  final TextEditingController _total = TextEditingController();
  final TextEditingController _correction = TextEditingController();
  bool _photoHandedOn = false;
  late final Once _once = Once(() => setState(() {}));
  Json? _preview;
  String? _error;
  int _oil = 0;
  bool _edited = false;
  Timer? _debounce;

  // -- LIFECYCLES -- //

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _total.dispose();
    _correction.dispose();
    _debounce?.cancel();
    // The photo never leaves this phone and is not kept after the review. A corrected review takes it over
    final photo = widget.photo;
    if (photo != null && !_photoHandedOn) {
      unawaited(deleteShots(<String>[photo]));
    }
    super.dispose();
  }

  // -- FUNCTIONS -- //

  Json get _args {
    final total = int.tryParse(_total.text.trim());
    return <String, Object?>{
      if (widget.args['day'] != null) 'day': widget.args['day'],
      if (widget.args['meal'] != null) 'meal': widget.args['meal'],
      'totalG': ?total,
      'items': <Json>[
        ..._items,
        if (_oil > 0)
          <String, Object?>{
            'estimate': <String, Object?>{
              'name': context.t.healthOilName,
              'proteinG': 0,
              'carbsG': 0,
              'fatG': 14 * _oil,
            },
          },
      ],
    };
  }

  Future<void> _refresh() async {
    try {
      final p = await ref.read(apiProvider).verbJson('meal_preview', _args);
      if (mounted) {
        setState(() {
          _preview = p;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _changed() {
    setState(() => _edited = true);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _refresh);
  }

  void _grams(int index, int previewGrams, int change) {
    final next = previewGrams + change;
    if (next < 1) return;
    setState(() {
      final item = Map<String, Object?>.of(_items[index])
        ..['grams'] = next
        ..remove('portion')
        ..remove('count')
        ..remove('lowGrams')
        ..remove('highGrams');
      _items[index] = item;
    });
    _changed();
  }

  void _remove(int index) {
    setState(() => _items = List<Json>.of(_items)..removeAt(index));
    _changed();
  }

  Future<void> _addFood() async {
    final picked = await showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _FoodSearchSheet(),
    );
    if (picked == null) return;
    setState(() => _items = <Json>[..._items, picked]);
    _changed();
  }

  /// Tells Botler what the food really is. It looks at the photo again with the person's words, and the answer is a new card to check, so nothing is saved by this. The old
  /// card is let go only once the new one exists: a failure leaves everything as it was.
  Future<void> _correct() async {
    final words = _correction.text.trim();
    final photo = widget.photo;
    if (words.isEmpty || photo == null) return;
    final t = context.t;
    final api = ref.read(apiProvider);
    final had = asJsonList(_preview?['items'])
        .map((v) {
          final grams = v['grams'];
          return grams == null
              ? str(v['name'])
              : '${str(v['name'])} ${intOf(grams)} g';
        })
        .join(', ');
    final correction =
        'Correction from the person: "$words". Your last reading was: $had';
    setState(() => _error = null);
    try {
      await _once.run((_) async {
        final resend = widget.resend;
        final r = resend != null
            ? await resend(correction)
            : await sendFoodPhotos(
                ref,
                mode: widget.mode,
                paths: <String>[photo],
                correction: correction,
              );
        final actionId = r.actionId;
        if (!r.hasCard || actionId == null) {
          if (mounted) {
            setState(() => _error = r.failure ?? t.healthPhotoFailedLine);
          }
          return;
        }
        // The screen was left while Botler worked: the new card is not wanted
        if (!mounted) {
          await api.decideCard(actionId, approve: false);
          return;
        }
        try {
          await api.decideCard(widget.actionId, approve: false);
        } on ApiException {
          // The old card closed some other way, which is what this wanted
        }
        if (!mounted) return;
        _photoHandedOn = true;
        context.pushReplacement(
          '/health/review',
          extra: <String, Object?>{
            'photo': photo,
            'mode': widget.mode,
            'actionId': actionId,
            'args': r.args,
            'note': r.note,
          },
        );
      }, intent: 'correct');
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.isNetwork ? t.healthCameraOffline : e.message,
        );
      }
    } on Object {
      if (mounted) setState(() => _error = t.healthPhotoFailedLine);
    }
  }

  Widget _correctionCard() {
    final t = context.t;
    final c = context.colors;
    final busy = _once.running('correct');
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t.healthCorrectTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            t.healthCorrectLine,
            style: TextStyle(color: c.muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _correction,
            enabled: !busy,
            minLines: 1,
            maxLines: 3,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: t.healthCorrectLabel,
              hintText: t.healthCorrectHint,
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _once.running() || _correction.text.trim().isEmpty
                  ? null
                  : () => unawaited(_correct()),
              child: Text(busy ? t.healthCorrectBusy : t.healthCorrectSend),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _decide(bool approve) async {
    setState(() => _error = null);
    final failedWords = context.t.healthPhotoFailedLine;
    try {
      await _once.run((_) async {
        final out = await ref
            .read(apiProvider)
            .decideCard(
              widget.actionId,
              approve: approve,
              editedArgs:
                  approve && (_edited || _oil > 0 || _total.text.isNotEmpty)
                  ? _args
                  : null,
            );
        final action = asJson(out['action']);
        if (approve && str(action['status']) == 'failed') {
          throw ApiException(
            'INVALID',
            str(asJson(action['result'])['error'], failedWords),
            400,
          );
        }
        ref
          ..invalidate(foodDayProvider)
          ..invalidate(healthHomeProvider);
        if (mounted && context.canPop()) context.pop();
      }, intent: 'decide:$approve');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  // -- WIDGETS -- //

  Widget _hero() {
    final photo = widget.photo;
    if (photo == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.file(
          File(photo),
          height: 220,
          width: double.infinity,
          fit: BoxFit.cover,
          semanticLabel: context.t.healthMealPhoto,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _summary() {
    final t = context.t;
    final c = context.colors;
    final p = _preview;
    if (p == null) return const SkeletonRows(count: 1, kind: SkeletonKind.tile);
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          BigNumber(
            t.healthLeftWordsAbout(kcalText(intOf(p['kcal']))),
            size: 34,
          ),
          const SizedBox(height: 4),
          Text(
            t.healthCouldBe(
              kcalText(intOf(p['lowKcal'])),
              kcalText(intOf(p['highKcal'])),
            ),
            style: TextStyle(color: c.muted),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _macro(t.healthProtein, intOf(p['proteinMg']), c.info),
              ),
              Expanded(
                child: _macro(t.healthCarbs, intOf(p['carbsMg']), c.accent),
              ),
              Expanded(child: _macro(t.healthFat, intOf(p['fatMg']), c.muted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macro(String name, int mg, Color color) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.muted, fontSize: 13),
              ),
            ),
          ],
        ),
        Text(
          context.t.healthGrams(gramsFromMgText(mg)),
          style: const TextStyle(fontFeatures: tabular),
        ),
      ],
    );
  }

  Widget _row(int index, Json view) {
    final t = context.t;
    final c = context.colors;
    final kind = str(view['sourceKind']);
    final grams = view['grams'] == null ? null : intOf(view['grams']);
    final isEstimate = kind == 'estimate';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
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
                      str(view['name']),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sourceWord(context, kind),
                      style: TextStyle(
                        fontSize: 12,
                        color: isEstimate ? c.warning : c.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(t.healthKcal(kcalText(intOf(view['kcal'])))),
                  if (view['proteinMg'] != null)
                    Text(
                      t.healthProteinShort(
                        gramsFromMgText(intOf(view['proteinMg'])),
                      ),
                      style: TextStyle(color: c.muted, fontSize: 13),
                    ),
                ],
              ),
            ],
          ),
          if (view['basisGrams'] != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              t.healthLabelBasis('${intOf(view['basisGrams'])}'),
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
            Text(
              view['fits'] == false ? t.healthLabelNoFit : t.healthLabelFits,
              style: TextStyle(
                fontSize: 13,
                color: view['fits'] == false ? c.warning : c.success,
              ),
            ),
          ],
          Row(
            children: <Widget>[
              if (grams != null) ...<Widget>[
                IconButton(
                  tooltip: t.healthLess,
                  onPressed: () => _grams(index, grams, -10),
                  icon: const Icon(Icons.remove),
                ),
                Text(
                  t.healthGrams('$grams'),
                  style: const TextStyle(fontFeatures: tabular),
                ),
                IconButton(
                  tooltip: t.healthMore,
                  onPressed: () => _grams(index, grams, 10),
                  icon: const Icon(Icons.add),
                ),
              ],
              const Spacer(),
              if (index < _items.length)
                TextButton(
                  onPressed: () => _remove(index),
                  child: Text(t.healthRemove),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final views = asJsonList(_preview?['items']);
    final note = widget.note;
    return Scaffold(
      appBar: AppBar(title: Text(t.healthReviewTitle)),
      body: ListView(
        padding: pagePadding(context),
        children: <Widget>[
          _hero(),
          _summary(),
          const SizedBox(height: 12),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // The assistant's words may hold Markdown; the fixed question does not
                if (note == null || note.isEmpty)
                  Text(
                    t.healthOilQuestion,
                    style: TextStyle(
                      color: c.accentText,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else
                  BotlerMarkdown(note, color: c.accentText),
                const SizedBox(height: 4),
                Text(
                  t.healthOilLine,
                  style: TextStyle(color: c.accentText, fontSize: 13),
                ),
                const SizedBox(height: 10),
                ChoiceRow<int>(
                  value: _oil,
                  onChanged: (v) {
                    setState(() => _oil = v);
                    _changed();
                  },
                  choices: <(int, String)>[
                    (0, t.healthOilNone),
                    (1, t.healthOilSome),
                    (2, t.healthOilLots),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (views.isNotEmpty)
            PaperCard(
              child: Column(
                children: <Widget>[
                  for (var i = 0; i < views.length; i++) ...<Widget>[
                    _row(i, views[i]),
                    if (i < views.length - 1) const Divider(),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (widget.photo != null) ...<Widget>[
            _correctionCard(),
            const SizedBox(height: 12),
          ],
          OutlinedButton(onPressed: _addFood, child: Text(t.healthAddFood)),
          const SizedBox(height: 12),
          PaperCard(
            child: Field(
              controller: _total,
              label: t.healthTotalWeight,
              keyboard: TextInputType.number,
              onChanged: (_) => _changed(),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Note(_error ?? ''),
          ],
        ],
      ),
      bottomNavigationBar: BottomDock(
        primary: FilledButton(
          onPressed: _once.running() || _items.isEmpty
              ? null
              : () => _decide(true),
          child: Text(t.healthSaveMeal),
        ),
        below: TextButton(
          onPressed: _once.running() ? null : () => _decide(false),
          child: Text(t.healthDiscard),
        ),
      ),
    );
  }
}

class _FoodSearchSheet extends ConsumerStatefulWidget {
  const _FoodSearchSheet();

  @override
  ConsumerState<_FoodSearchSheet> createState() => _FoodSearchSheetState();
}

class _FoodSearchSheetState extends ConsumerState<_FoodSearchSheet> {
  // -- STATES -- //

  final TextEditingController _query = TextEditingController();
  List<Json> _hits = <Json>[];
  Timer? _debounce;

  // -- LIFECYCLES -- //

  @override
  void dispose() {
    _query.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // -- FUNCTIONS -- //

  void _search(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final q = text.trim();
      if (q.isEmpty) return;
      try {
        final r = await ref.read(apiProvider).verb(
          'food_search',
          <String, Object?>{
            'names': <String>[q],
          },
        );
        final first = asJsonList(r).firstOrNull;
        if (mounted) setState(() => _hits = asJsonList(first?['hits']));
      } on ApiException {
        if (mounted) setState(() => _hits = <Json>[]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
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
          Field(controller: _query, label: t.healthAddName, onChanged: _search),
          for (final h in _hits)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(str(h['name'])),
              subtitle: Text(
                t.healthPer100(kcalText(intOf(h['kcalPer100g']))),
                style: TextStyle(color: c.muted),
              ),
              onTap: () {
                final portions = asJsonList(h['portions']);
                final grams = portions.isEmpty
                    ? 100
                    : intOf(portions.first['grams'], 100);
                Navigator.of(context)
                    .pop(<String, Object?>{'foodId': h['id'], 'grams': grams});
              },
            ),
        ],
      ),
    );
  }
}
