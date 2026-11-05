// THE TILES OF THE HEALTH HOME SCREEN: A SMALL PICTURE, A VALUE AND A LINE FOR EACH PART. A PART WITH NO DATA YET STILL SHOWS, WITH A QUIET LINE SAYING WHAT TO DO.

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
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'health_charts.dart';
import 'health_parts.dart';
import 'train_screen.dart';
import 'weight_screen.dart';

// -- TYPES -- //

class HomeTiles extends StatelessWidget {
  const HomeTiles({required this.home, super.key});

  final Json home;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final food = asJson(home['food']);
    final weight = asJson(home['weight']);
    final train = asJson(home['train']);
    final sleep = asJson(home['sleep']);
    final free = home['free'];
    final proposals = asJsonList(home['proposals']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final p in proposals)
          if (str(p['kind']) == 'target')
            _Banner(
              title: t.healthCheckInReady,
              line: t.healthCheckInLine,
              onTap: () => context.push('/health/weight'),
            )
          else if (str(p['kind']) == 'week')
            _Banner(
              title: t.healthWeekReady,
              line: t.healthWeekReadyLine,
              onTap: () => context.push('/health/train/week'),
            )
          else
            _ReviewCard(proposal: p),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _FoodTile(food: food)),
              const SizedBox(width: 12),
              Expanded(child: _WeightTile(weight: weight)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _TrainTile(train: train)),
              const SizedBox(width: 12),
              Expanded(child: _SleepTile(sleep: sleep)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PaperCard(
          onTap: () => context.push('/health/week'),
          child: StatRow(
            icon: Icons.schedule,
            title: t.healthTileWeek,
            line: free is Map
                ? t.healthTileFreeToday(
                    clockText(context, str(asJson(free)['from'])),
                    clockText(context, str(asJson(free)['to'])),
                  )
                : t.healthTileNoFree,
            trailing: Icon(Icons.chevron_right, color: context.colors.muted),
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.title, required this.line, required this.onTap});

  final String title;
  final String line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(
        onTap: onTap,
        child: Row(
          children: <Widget>[
            Icon(Icons.auto_awesome_outlined, color: c.accentText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: c.accentText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    line,
                    style: TextStyle(color: c.accentText, fontSize: 13),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: c.accentText),
          ],
        ),
      ),
    );
  }
}

/// The week in a few lines and one thing to try. It makes no model call: asking about it is the person's choice.
class _ReviewCard extends ConsumerStatefulWidget {
  const _ReviewCard({required this.proposal});

  final Json proposal;

  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  late final Once _once = Once(() => setState(() {}));

  Future<void> _close() async {
    try {
      await _once.run((key) async {
        await ref.read(apiProvider).verb('proposal_answer', <String, Object?>{
          'proposalId': str(widget.proposal['id']),
          'accept': true,
        }, key);
      });
      ref.invalidate(healthHomeProvider);
    } on ApiException catch (_) {
      // A review that closed elsewhere leaves the screen on the next read
      ref.invalidate(healthHomeProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final p = asJson(widget.proposal['payload']);
    final style = TextStyle(color: c.accentText);
    final averageKcal = p['averageKcal'];
    final changeG = p['changeG'];
    final sleep = p['averageSleepMinutes'];
    final suggestion = switch (str(p['suggestion'])) {
      'sleep_earlier' => t.healthSuggestSleep,
      'log_food' => t.healthSuggestFood,
      'weigh_more' => t.healthSuggestWeigh,
      'move_more' => t.healthSuggestMove,
      _ => t.healthSuggestKeep,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              t.healthReviewTitle,
              style: style.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            Text(
              averageKcal is num
                  ? t.healthReviewFood(
                      '${intOf(p['completeDays'])}',
                      kcalText(averageKcal.round()),
                    )
                  : t.healthReviewNoFood,
              style: style,
            ),
            if (changeG is num)
              Text(changeWords(context, changeG.round()), style: style),
            Text(
              t.healthReviewMoved(
                '${intOf(p['minutes'])}',
                '${intOf(p['strengthDays'])}',
              ),
              style: style,
            ),
            if (sleep is num)
              Text(
                t.healthReviewSleep(durationText(sleep.round())),
                style: style,
              ),
            const SizedBox(height: 8),
            Text(
              suggestion,
              style: style.copyWith(fontWeight: FontWeight.w500),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                children: <Widget>[
                  TextButton(
                    onPressed: () => context.go('/'),
                    child: Text(t.healthReviewAsk),
                  ),
                  TextButton(
                    onPressed: _once.running()
                        ? null
                        : () => unawaited(_close()),
                    child: Text(t.healthReviewDone),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One square of the home screen.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.title,
    required this.picture,
    required this.value,
    required this.line,
    required this.onTap,
  });

  final String title;
  final Widget picture;
  final String value;
  final String line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PaperCard(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 144),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              title,
              style: TextStyle(
                color: c.muted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 66,
              child: Align(alignment: Alignment.centerLeft, child: picture),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                letterSpacing: -0.2,
                fontFeatures: tabular,
              ),
            ),
            Text(line, style: TextStyle(color: c.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _FoodTile extends StatelessWidget {
  const _FoodTile({required this.food});

  final Json food;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final eaten = intOf(food['eatenKcal']);
    final target = food['targetKcal'] is num ? intOf(food['targetKcal']) : null;
    final left = food['leftKcal'] is num ? intOf(food['leftKcal']) : null;
    final percent = target == null || target == 0 ? 0 : eaten * 100 ~/ target;
    return _Tile(
      title: t.healthTileToday,
      onTap: () => context.push('/health/today'),
      picture: HealthRing(
        size: 62,
        stroke: 8,
        percent: percent,
        label: t.healthRingLabel('$percent'),
        child: Text(
          '${percent.clamp(0, 999)}%',
          style: TextStyle(fontSize: 13, fontFeatures: tabular),
        ),
      ),
      value: left == null
          ? t.healthTileEaten(kcalText(eaten))
          : left >= 0
          ? t.healthTileLeft(kcalText(left))
          : t.healthTileOver(kcalText(-left)),
      line: target == null
          ? t.healthTileTodayEmpty
          : t.healthTileOfTarget(kcalText(eaten), kcalText(target)),
    );
  }
}

class _WeightTile extends StatelessWidget {
  const _WeightTile({required this.weight});

  final Json weight;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final points = <int>[for (final p in asList(weight['points'])) intOf(p)];
    final trend = weight['trendG'] is num ? intOf(weight['trendG']) : null;
    final change = weight['changeG'] is num ? intOf(weight['changeG']) : null;
    return _Tile(
      title: t.healthTileWeight,
      onTap: () => context.push('/health/weight'),
      picture: points.length < 2
          ? Icon(Icons.monitor_weight_outlined, size: 32, color: c.accentText)
          : WeightChart(
              trend: points,
              scale: const <int>[],
              height: 62,
              label: t.healthWeightSpark,
            ),
      value: trend == null ? '-' : '${kgText(trend)} kg',
      line: trend == null
          ? t.healthTileWeightEmpty
          : change == null || points.length < 2
          ? ''
          : changeWords(context, change),
    );
  }
}

class _TrainTile extends StatelessWidget {
  const _TrainTile({required this.train});

  final Json train;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final next = train['next'];
    final days = asJsonList(train['days']);
    final minutes = intOf(train['minutes']);
    final goal = intOf(train['minutesGoal'], 150);
    return _Tile(
      title: t.healthTileTrain,
      onTap: () => context.push('/health/train'),
      picture: WeekDots(days: days, compact: true),
      value: next is Map ? str(asJson(next)['title']) : t.healthTileNoPlan,
      line: next is Map
          ? t.healthNextAt(
              dayName(context, str(asJson(next)['day'])),
              clockText(context, str(asJson(next)['time'])),
            )
          : minutes > 0
          ? t.healthMinutesLabel('$minutes', '$goal')
          : t.healthTileTrainEmpty,
    );
  }
}

class _SleepTile extends StatelessWidget {
  const _SleepTile({required this.sleep});

  final Json sleep;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final last = sleep['last'];
    final nights = <int>[for (final n in asList(sleep['nights'])) intOf(n)];
    return _Tile(
      title: t.healthTileSleep,
      onTap: () => context.push('/health/sleep'),
      picture: nights.isEmpty
          ? Icon(Icons.bedtime_outlined, size: 32, color: c.accentText)
          : MiniBars(values: nights, label: t.healthSleepBars),
      value: last is Map ? durationText(intOf(asJson(last)['minutes'])) : '-',
      line: last is Map ? t.healthTileLastNight : t.healthTileSleepEmpty,
    );
  }
}
