// A SCANNED BARCODE: IS THIS IT, HOW MUCH DID YOU HAVE, ADD IT. A PRODUCT THE FOOD DATA DOES NOT KNOW GOES TO THE LABEL, AND BOTLER REMEMBERS IT NEXT TIME.

// -- DEP-MODULES -- //
import 'dart:async';

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
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'health_parts.dart';

// -- TYPES -- //

class BarcodeResultScreen extends ConsumerStatefulWidget {
  const BarcodeResultScreen({required this.code, super.key});

  final String code;

  @override
  ConsumerState<BarcodeResultScreen> createState() =>
      _BarcodeResultScreenState();
}

class _BarcodeResultScreenState extends ConsumerState<BarcodeResultScreen> {
  // -- STATES -- //

  Json? _answer;
  String? _error;
  double _servings = 1;
  late final Once _once = Once(() => setState(() {}));

  // -- LIFECYCLES -- //

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  // -- FUNCTIONS -- //

  Future<void> _load() async {
    try {
      final r = await ref.read(apiProvider).verbJson(
        'barcode_lookup',
        <String, Object?>{'barcode': widget.code},
      );
      if (mounted) setState(() => _answer = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  int _baseGrams(Json a) {
    final serving = a['servingG'];
    if (serving != null && intOf(serving) > 0) return intOf(serving);
    final pack = a['packG'];
    return pack != null && intOf(pack) > 0 ? intOf(pack) : 100;
  }

  Future<void> _add(Json a) async {
    final grams = (_baseGrams(a) * _servings).round();
    final args = <String, Object?>{
      'items': <Json>[
        <String, Object?>{'foodId': a['id'], 'grams': grams},
      ],
    };
    try {
      await _once.run((key) async {
        await ref.read(apiProvider).verb('meal_log', args, key);
        ref
          ..invalidate(foodDayProvider)
          ..invalidate(healthHomeProvider);
        if (mounted && context.canPop()) context.pop();
      }, intent: args.toString());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toLabel() {
    context.pushReplacement('/health/camera?mode=label&barcode=${widget.code}');
  }

  // -- WIDGETS -- //

  Widget _notFound() {
    final t = context.t;
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const IconTile(Icons.qr_code_2, size: 72),
              const SizedBox(height: 16),
              Text(
                t.healthNotFoundTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                t.healthNotFoundLine,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomDock(
        primary: FilledButton(
          onPressed: _toLabel,
          child: Text(t.healthReadLabel),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final a = _answer;
    if (a == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t.healthIsThisIt)),
        body: _error == null
            ? const SkeletonPage(
                child: SkeletonRows(count: 2, kind: SkeletonKind.tile),
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Note(_error ?? ''),
              ),
      );
    }
    if (a['found'] != true) return _notFound();
    final facts = asJson(a['facts']);
    final grams = (_baseGrams(a) * _servings).round();
    int part(String key) => (intOf(facts[key]) * grams / 100).round();
    final isOff = str(a['source']) == 'off';
    return Scaffold(
      appBar: AppBar(title: Text(t.healthIsThisIt)),
      body: ListView(
        padding: pagePadding(context),
        children: <Widget>[
          PaperCard(
            child: StatRow(
              icon: Icons.qr_code_2,
              title: str(a['name']),
              line: t.healthGrams('${_baseGrams(a)}'),
            ),
          ),
          SectionTitle(t.healthHowMuch),
          ChoiceRow<double>(
            value: _servings,
            onChanged: (v) => setState(() => _servings = v),
            choices: <(double, String)>[
              (0.5, t.healthHalf),
              (1, t.healthOneServing),
              (2, t.healthTwoServings),
            ],
          ),
          const SizedBox(height: 12),
          PaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                BigNumber(t.healthKcal(kcalText(part('kcal'))), size: 34),
                const SizedBox(height: 8),
                if (facts['proteinMg'] != null)
                  Text(
                    '${t.healthProtein}: ${t.healthGrams(gramsFromMgText(part('proteinMg')))}',
                  ),
                if (facts['carbsMg'] != null)
                  Text(
                    '${t.healthCarbs}: ${t.healthGrams(gramsFromMgText(part('carbsMg')))}',
                  ),
                if (facts['fatMg'] != null)
                  Text(
                    '${t.healthFat}: ${t.healthGrams(gramsFromMgText(part('fatMg')))}',
                  ),
                if (facts['sodiumMg'] != null)
                  Text(
                    '${t.healthSodium}: ${t.healthMilligrams(kcalText(part('sodiumMg')))}',
                  ),
              ],
            ),
          ),
          if (isOff) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              t.healthOffCredit,
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Note(_error ?? ''),
          ],
        ],
      ),
      bottomNavigationBar: BottomDock(
        primary: FilledButton(
          onPressed: _once.running() ? null : () => _add(a),
          child: Text(t.healthAddToToday),
        ),
        below: TextButton(
          onPressed: _toLabel,
          child: Text(t.healthNotThisProduct),
        ),
      ),
    );
  }
}
