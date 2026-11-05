// WEIGHT: THE TREND LINE COUNTS MORE THAN ONE MORNING. THE WEEKLY CHECK-IN IS ANSWERED HERE, WITH THE VALUE THAT WAS SHOWN, AND THE SERVER CHECKS IT AGAIN.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/health_units.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/health.dart';
import '../../state/health_more.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'food_sheets.dart';
import 'health_charts.dart';
import 'health_parts.dart';

// -- TYPES -- //

class WeightScreen extends ConsumerWidget {
  const WeightScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref
      ..invalidate(weightTrendProvider)
      ..invalidate(proposalsProvider)
      ..invalidate(healthHomeProvider)
      ..invalidate(foodDayProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final trend = ref.watch(weightTrendProvider);
    final open = ref.watch(proposalsProvider).value ?? const <Json>[];
    final target = open.where((p) => str(p['kind']) == 'target').firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(t.healthWeightTitle)),
      body: AsyncBody<Json>(
        value: trend,
        onRetry: () => _refresh(ref),
        skeleton: const SkeletonPage(
          child: SkeletonRows(count: 3, kind: SkeletonKind.tile),
        ),
        data: (d) => RefreshIndicator(
          onRefresh: () async => _refresh(ref),
          child: ListView(
            padding: pagePadding(context),
            children: <Widget>[
              _TrendCard(data: d),
              if (boolOf(d['lowIntake'])) ...<Widget>[
                const SizedBox(height: 12),
                SoftCard(
                  child: Text(
                    t.healthLowIntake,
                    style: TextStyle(color: context.colors.accentText),
                  ),
                ),
              ],
              if (target != null) ...<Widget>[
                const SizedBox(height: 12),
                _CheckInCard(proposal: target, onDone: () => _refresh(ref)),
              ],
              if (asJsonList(d['entries']).isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                _EntriesCard(
                  entries: asJsonList(d['entries']),
                  onChanged: () => _refresh(ref),
                ),
              ],
              if (asJson(d['forecast']).isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                _ForecastCard(
                  forecast: asJson(d['forecast']),
                  goalG: intOf(d['goalWeightG']),
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomDock(
        showAsk: true,
        primary: FilledButton.icon(
          onPressed: () => unawaited(_addWeight(context, ref)),
          icon: const Icon(Icons.add),
          label: Text(t.healthAddWeight),
        ),
      ),
    );
  }

  Future<void> _addWeight(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddWeightSheet(onSaved: () => _refresh(ref)),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.data});

  final Json data;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final points = asJsonList(data['points']);
    final trendG = data['trendG'] is num ? intOf(data['trendG']) : null;
    final changeG = data['changeG'] is num ? intOf(data['changeG']) : null;
    final scaleG = data['scaleG'] is num ? intOf(data['scaleG']) : null;
    final trend = <int>[for (final p in points) intOf(p['trendG'])];
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    t.healthYourTrend,
                    style: TextStyle(color: c.muted, fontSize: 14),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      BigNumber(
                        trendG == null ? '-' : kgText(trendG),
                        size: 52,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'kg',
                        style: TextStyle(color: c.muted, fontSize: 18),
                      ),
                    ],
                  ),
                ],
              ),
              if (changeG != null && points.length > 1)
                Flexible(child: _Tag(text: changeWords(context, changeG))),
            ],
          ),
          const SizedBox(height: 12),
          if (trend.length < 2)
            Text(t.healthChartEmpty, style: TextStyle(color: c.muted))
          else ...<Widget>[
            WeightChart(
              trend: trend,
              scale: <int>[for (final p in points) intOf(p['grams'])],
              label: t.healthChartLabel(
                kgText(trend.first),
                kgText(trend.last),
              ),
            ),
            if (scaleG != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                t.healthScaleToday(kgText(scaleG)),
                style: TextStyle(color: c.muted, fontSize: 13),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// "Down 1 kg" or "Steady" from a change in grams.
String changeWords(BuildContext context, int grams) {
  final t = context.t;
  if (grams.abs() < 100) return t.healthSteady;
  final kg = kgText(grams.abs());
  return grams < 0 ? t.healthDown(kg) : t.healthUp(kg);
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: c.accentText,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _CheckInCard extends ConsumerStatefulWidget {
  const _CheckInCard({required this.proposal, required this.onDone});

  final Json proposal;
  final VoidCallback onDone;

  @override
  ConsumerState<_CheckInCard> createState() => _CheckInCardState();
}

class _CheckInCardState extends ConsumerState<_CheckInCard> {
  // -- STATES -- //

  late final Once _once = Once(() => setState(() {}));
  String? _error;

  // -- FUNCTIONS -- //

  Future<void> _answer(bool accept) async {
    final payload = asJson(widget.proposal['payload']);
    try {
      await _once.run((key) async {
        await ref.read(apiProvider).verb('proposal_answer', <String, Object?>{
          'proposalId': str(widget.proposal['id']),
          'accept': accept,
          if (accept) 'value': intOf(payload['toKcal']),
        }, key);
      });
      widget.onDone();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final payload = asJson(widget.proposal['payload']);
    final to = kcalText(intOf(payload['toKcal']));
    final from = kcalText(intOf(payload['fromKcal']));
    final style = TextStyle(color: c.accentText);
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.auto_awesome_outlined, size: 18, color: c.accentText),
              const SizedBox(width: 6),
              Text(
                t.healthCheckInTitle,
                style: style.copyWith(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          BigNumber(t.healthTryKcal(to), size: 28, color: c.accentText),
          const SizedBox(height: 6),
          Text(
            t.healthCheckInWhy(kcalText(intOf(payload['burnKcal']))),
            style: style,
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(_error ?? '', style: TextStyle(color: c.danger)),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _once.running()
                      ? null
                      : () => unawaited(_answer(true)),
                  child: Text(t.healthUseKcal(to)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton(
                  onPressed: _once.running()
                      ? null
                      : () => unawaited(_answer(false)),
                  child: Text(t.healthKeepKcal(from)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The latest weigh-ins. One the assistant made is marked, and any can be removed.
class _EntriesCard extends ConsumerWidget {
  const _EntriesCard({required this.entries, required this.onChanged});

  final List<Json> entries;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t.healthRecentWeights,
            style: TextStyle(
              color: c.muted,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          for (final e in entries)
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${kgText(intOf(e['grams']))} kg',
                        style: TextStyle(fontFeatures: tabular),
                      ),
                      Text(
                        DateFormat.MMMd(
                          Localizations.localeOf(context).toString(),
                        ).format(DateTime.parse(str(e['day']))),
                        style: TextStyle(color: c.muted, fontSize: 13),
                      ),
                      if (boolOf(e['byAgent'])) const ByBotlerMark(),
                    ],
                  ),
                ),
                if (boolOf(e['byAgent']))
                  TextButton(
                    onPressed: () => unawaited(_remove(context, ref, e)),
                    child: Text(t.healthUndo),
                  )
                else
                  IconButton(
                    tooltip: t.healthRemoveWeight,
                    icon: Icon(Icons.close, color: c.muted),
                    onPressed: () => unawaited(_remove(context, ref, e)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, Json e) async {
    final t = context.t;
    // An entry the person typed leaves the trend for good, so it asks first; an assistant entry has its Undo
    if (!boolOf(e['byAgent'])) {
      final yes = await confirm(
        context,
        title: t.healthRemoveWeight,
        body: t.healthRemoveWeightBody,
        yes: t.healthRemove,
        danger: true,
      );
      if (!yes || !context.mounted) return;
    }
    try {
      await ref.read(apiProvider).verb('weight_delete', <String, Object?>{
        'day': str(e['day']),
      }, newRequestId());
      onChanged();
    } catch (err) {
      if (context.mounted) say(context, errorWords(err, context));
    }
  }
}

class _ForecastCard extends StatelessWidget {
  const _ForecastCard({required this.forecast, required this.goalG});

  final Json forecast;
  final int goalG;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final reason = str(forecast['reason']);
    if (reason == 'no_goal') return const SizedBox.shrink();
    final reachOn = str(forecast['reachOn']);
    final title = switch (reason) {
      'flat' => t.healthForecastFlat,
      'wrong_way' => t.healthForecastAway,
      'too_far' => t.healthForecastFar,
      'reached' => t.healthForecastReached,
      _ => t.healthForecastAround(
        kgText(goalG),
        DateFormat.yMMMM(Localizations.localeOf(context).toString())
            .format(DateTime.parse(reachOn)),
      ),
    };
    final line = reachOn.isEmpty && reason != 'reached'
        ? t.healthForecastNoDate
        : reason == 'reached'
        ? ''
        : t.healthForecastLine;
    return PaperCard(
      child: StatRow(icon: Icons.show_chart, title: title, line: line),
    );
  }
}

class _AddWeightSheet extends ConsumerStatefulWidget {
  const _AddWeightSheet({required this.onSaved});

  final VoidCallback onSaved;

  @override
  ConsumerState<_AddWeightSheet> createState() => _AddWeightSheetState();
}

class _AddWeightSheetState extends ConsumerState<_AddWeightSheet> {
  // -- STATES -- //

  final TextEditingController _kg = TextEditingController();
  late final Once _once = Once(() => setState(() {}));
  String? _error;

  // -- LIFECYCLES -- //

  @override
  void dispose() {
    _kg.dispose();
    super.dispose();
  }

  // -- FUNCTIONS -- //

  Future<void> _save() async {
    final t = context.t;
    final grams = gramsFromKgText(_kg.text);
    if (grams == null || grams < 20000 || grams > 400000) {
      setState(() => _error = t.healthWeightBad);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await _once.run((key) async {
        final queued = await writeOrQueue(ref, 'weight_log', <String, Object?>{
          'grams': grams,
        }, key);
        if (queued) {
          messenger.showSnackBar(SnackBar(content: Text(t.healthWeightQueued)));
        }
      });
      widget.onSaved();
      navigator.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t.healthWeightToday,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _kg,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: t.healthWeightKg,
              suffixText: 'kg',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _once.running() ? null : () => unawaited(_save()),
              child: Text(t.healthAddWeight),
            ),
          ),
        ],
      ),
    );
  }
}
