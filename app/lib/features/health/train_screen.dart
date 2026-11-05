// TRAIN: TODAY'S SESSION, THE SEVEN DAYS, MINUTES AGAINST 150 AND STRENGTH DAYS AGAINST 2. WHATEVER NO LONGER FITS THE WEEK ASKS FOR A MOVE, WITH NO GUILT ABOUT ANYTHING MISSED.

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
import '../../state/health_more.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'food_sheets.dart';
import 'health_parts.dart';
import '../../core/clock.dart';

// -- FUNCTIONS -- //

/// "19:15" as the person's own clock.
String clockText(BuildContext context, String time) {
  final parts = time.split(':');
  final h = int.tryParse(parts.first) ?? 0;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return fmtTimeOfDay(TimeOfDay(hour: h, minute: m));
}

/// The short name of a day: "Sat".
String dayName(BuildContext context, String day) =>
    fmtWeekday(DateTime.parse(day));

/// Runs a verb that changes the week, then shows the answer on the screens that read it.
void refreshTrain(WidgetRef ref) {
  ref
    ..invalidate(trainProvider)
    ..invalidate(healthHomeProvider);
}

// -- TYPES -- //

class TrainScreen extends ConsumerWidget {
  const TrainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final train = ref.watch(trainProvider);
    final today = train.value?['todayPlanned'];
    final runningId = str(train.value?['runningId']);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.healthTrainTitle),
        actions: <Widget>[
          TextButton(
            onPressed: () => context.push('/health/train/week'),
            child: Text(t.healthNextWeek),
          ),
        ],
      ),
      body: AsyncBody<Json>(
        value: train,
        onRetry: () => refreshTrain(ref),
        skeleton: const SkeletonPage(
          child: SkeletonRows(count: 4, kind: SkeletonKind.tile),
        ),
        data: (d) => RefreshIndicator(
          onRefresh: () async => refreshTrain(ref),
          child: ListView(
            padding: pagePadding(context),
            children: <Widget>[
              _TodayCard(data: d),
              const SizedBox(height: 12),
              _WeekCard(data: d),
              for (final m in asJsonList(d['needsMove'])) ...<Widget>[
                const SizedBox(height: 12),
                _NeedsMoveCard(item: m),
              ],
              const SizedBox(height: 16),
              _ProgramsSection(active: asJsonList(d['programs'])),
              if (asJsonList(d['recent']).isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                _RecentSection(rows: asJsonList(d['recent'])),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomDock(
        showAsk: true,
        primary: runningId.isNotEmpty
            ? FilledButton(
                onPressed: () => context.push('/health/train/session'),
                child: Text(t.healthResume),
              )
            : today is Map && str(today['kind']) != 'walk'
            ? FilledButton(
                onPressed: () => context.push(
                  '/health/train/session',
                  extra: <String, Object?>{'plannedId': str(today['id'])},
                ),
                child: Text(t.healthStartSession(str(today['title']))),
              )
            : FilledButton(
                onPressed: () => unawaited(showLogWalkSheet(context, ref)),
                child: Text(t.healthStartWalk),
              ),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.data});

  final Json data;

  /// The card answers from what the server says today is. An older server sends no state, and then the planned session decides, as before.
  String _state() {
    final given = str(data['todayState']);
    if (given.isNotEmpty) return given;
    return data['todayPlanned'] is Map ? 'planned' : 'rest';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final style = TextStyle(color: c.accentText);
    final title = Theme.of(context).textTheme.titleLarge
        ?.copyWith(color: c.accentText);
    Widget card(String heading, String? line, {List<Widget>? more}) => SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(heading, style: title),
          if (line != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(line, style: style),
          ],
          ...?more,
        ],
      ),
    );
    switch (_state()) {
      case 'running':
        return card(t.healthTodayRunning, t.healthTodayRunningLine);
      case 'planned':
        final j = asJson(data['todayPlanned']);
        return card(
          t.healthSessionMinutes(str(j['title']), '${intOf(j['minutes'])}'),
          t.healthTodayAt(clockText(context, str(j['time']))),
        );
      case 'done':
        return card(
          t.healthTodayDone,
          null,
          more: <Widget>[
            const SizedBox(height: 6),
            for (final d in asJsonList(data['todayDone']))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.check, size: 18, color: c.accentText),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        t.healthSessionMinutes(
                          str(d['title']),
                          '${intOf(d['minutes'])}',
                        ),
                        style: style,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      case 'routine':
        return card(
          t.healthTodayRoutine,
          t.healthTodayRoutineLine,
          more: <Widget>[
            const SizedBox(height: 6),
            for (final r in asJsonList(data['todayRoutines']))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  t.healthTodayRoutineItem(
                    clockText(context, str(r['time'])),
                    str(r['title']),
                  ),
                  style: style.copyWith(fontFeatures: tabular),
                ),
              ),
          ],
        );
      case 'program':
        final due = asJsonList(data['programsDue'])
            .where((p) => intOf(p['toPlace']) > 0)
            .map((p) => str(p['name']))
            .join(', ');
        return card(
          t.healthTodayProgram(due),
          t.healthTodayProgramLine,
          more: <Widget>[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.push('/health/train/week'),
              child: Text(t.healthPlanNextWeek),
            ),
          ],
        );
      default:
        return card(t.healthRestDay, t.healthRestLine);
    }
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.data});

  final Json data;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final minutes = intOf(data['minutes']);
    final goal = intOf(data['minutesGoal'], 150);
    final strength = intOf(data['strengthDays']);
    final strengthGoal = intOf(data['strengthGoal'], 2);
    return PaperCard(
      child: Column(
        children: <Widget>[
          WeekDots(days: asJsonList(data['days'])),
          Divider(color: c.line, height: 24),
          Row(
            children: <Widget>[
              Expanded(
                child: _GoalRing(
                  percent: goal == 0 ? 0 : minutes * 100 ~/ goal,
                  title: t.healthMinutesOf('$minutes', '$goal'),
                  line: t.healthMinutesMoving,
                  label: t.healthMinutesLabel('$minutes', '$goal'),
                  color: c.accent,
                ),
              ),
              Expanded(
                child: _GoalRing(
                  percent: strengthGoal == 0
                      ? 0
                      : strength * 100 ~/ strengthGoal,
                  title: t.healthMinutesOf('$strength', '$strengthGoal'),
                  line: t.healthStrengthDays,
                  label: t.healthStrengthLabel('$strength', '$strengthGoal'),
                  color: c.info,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoalRing extends StatelessWidget {
  const _GoalRing({
    required this.percent,
    required this.title,
    required this.line,
    required this.label,
    required this.color,
  });

  final int percent;
  final String title;
  final String line;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: <Widget>[
        HealthRing(
          size: 54,
          stroke: 7,
          percent: percent,
          label: label,
          color: color,
          child: percent >= 100
              ? Icon(Icons.check, size: 18, color: color)
              : Text(
                  '${percent.clamp(0, 100)}%',
                  style: TextStyle(fontSize: 12, fontFeatures: tabular),
                ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  fontFeatures: tabular,
                ),
              ),
              Text(line, style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The seven days of the week as small marks: done, today, planned or a quiet rest.
class WeekDots extends StatelessWidget {
  const WeekDots({required this.days, this.compact = false, super.key});

  final List<Json> days;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final size = compact ? 14.0 : 34.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        for (final d in days)
          Builder(
            builder: (context) {
              final state = str(d['state']);
              final name = dayName(context, str(d['day']));
              final stateWord = switch (state) {
                'done' => t.healthDayDone,
                'today' => t.healthDayToday,
                'planned' => t.healthDayPlanned,
                _ => t.healthDayRest,
              };
              return Semantics(
                label: t.healthDayState(name, stateWord),
                child: Column(
                  children: <Widget>[
                    if (!compact) ...<Widget>[
                      ExcludeSemantics(
                        child: Text(
                          name.substring(0, 1),
                          style: TextStyle(
                            fontSize: 12,
                            color: state == 'today' ? c.ink : c.muted,
                            fontWeight: state == 'today'
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: state == 'done'
                            ? c.accent
                            : state == 'planned'
                            ? c.accentSoft
                            : null,
                        border: Border.all(
                          color: state == 'today'
                              ? c.accent
                              : state == 'rest'
                              // A day with an exercise routine reads as a soft ring, not as a bare rest day
                              ? (boolOf(d['routineDay'])
                                    ? c.accent.withValues(alpha: 0.5)
                                    : c.line)
                              : c.accent.withValues(alpha: 0),
                          width: state == 'today' ? 2 : 1,
                        ),
                      ),
                      child: state == 'done' && !compact
                          ? Icon(Icons.check, size: 18, color: c.onAccent)
                          : null,
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class _NeedsMoveCard extends ConsumerStatefulWidget {
  const _NeedsMoveCard({required this.item});

  final Json item;

  @override
  ConsumerState<_NeedsMoveCard> createState() => _NeedsMoveCardState();
}

class _NeedsMoveCardState extends ConsumerState<_NeedsMoveCard> {
  late final Once _once = Once(() => setState(() {}));
  String? _error;

  Future<void> _do(String verb, Json args) async {
    try {
      await _once.run((key) async {
        await ref.read(apiProvider).verb(verb, args, key);
      });
      refreshTrain(ref);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final m = widget.item;
    final id = str(m['id']);
    final suggestion = str(m['suggestion']);
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          StatRow(
            icon: Icons.warning_amber_rounded,
            title: t.healthNeedsMove(
              str(m['title']),
              dayName(context, str(m['day'])),
            ),
            line: suggestion.isEmpty ? t.healthNoRoom : t.healthNeedsMoveLine,
          ),
          if (_error != null)
            Text(_error ?? '', style: TextStyle(color: c.danger)),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              if (suggestion.isNotEmpty)
                Expanded(
                  child: OutlinedButton(
                    onPressed: _once.running()
                        ? null
                        : () => unawaited(
                            _do('workout_move', <String, Object?>{
                              'plannedId': id,
                              'time': suggestion,
                            }),
                          ),
                    child: Text(t.healthMoveTo(clockText(context, suggestion))),
                  ),
                ),
              TextButton(
                onPressed: _once.running()
                    ? null
                    : () => unawaited(
                        _do('workout_skip', <String, Object?>{'plannedId': id}),
                      ),
                child: Text(t.healthSkip),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgramsSection extends ConsumerWidget {
  const _ProgramsSection({required this.active});

  final List<Json> active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    final all = ref.watch(programsProvider).value;
    final activeKeys = active.map((p) => str(p['templateKey'])).toSet();
    final others = all == null
        ? const <Json>[]
        : asJsonList(all['templates'])
              .where((p) => !activeKeys.contains(str(p['key'])))
              .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            t.healthYourPrograms,
            style: TextStyle(
              color: c.muted,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        for (final p in active)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PaperCard(
              onTap: () => unawaited(_askStop(context, ref, p)),
              child: Column(
                children: <Widget>[
                  StatRow(
                    icon: Icons.directions_run,
                    title: str(p['name']),
                    line: t.healthProgramWeek(
                      '${intOf(p['week'])}',
                      '${intOf(p['weeks'])}',
                    ),
                  ),
                  const SizedBox(height: 10),
                  ThinBar(intOf(p['percent'])),
                ],
              ),
            ),
          ),
        if (active.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              t.healthProgramsNone,
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
          ),
        for (final p in others)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PaperCard(
              onTap: all == null
                  ? null
                  : () => unawaited(_askStart(context, ref, p, all)),
              child: StatRow(
                icon: Icons.add_circle_outline,
                title: t.healthStartProgram(str(p['name'])),
                line: str(p['line']),
                trailing: Icon(Icons.chevron_right, color: c.muted),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _askStart(
    BuildContext context,
    WidgetRef ref,
    Json p,
    Json all,
  ) async {
    final t = context.t;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.healthReadyTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(t.healthReadyLine),
              if (active.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  t.healthProgramWarning,
                  style: TextStyle(color: context.colors.warning),
                ),
              ],
              const SizedBox(height: 10),
              for (final q in asList(all['readiness']))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(str(q)),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.healthReadyNo),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.healthReadyYes),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await ref.read(apiProvider).verb('program_start', <String, Object?>{
        'templateKey': str(p['key']),
      }, newRequestId());
      ref.invalidate(programsProvider);
      refreshTrain(ref);
    } catch (e) {
      if (context.mounted) say(context, errorWords(e, context));
    }
  }

  Future<void> _askStop(BuildContext context, WidgetRef ref, Json p) async {
    final t = context.t;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(str(p['name'])),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.healthReadyNo),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.healthStopProgram),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await ref.read(apiProvider).verb('program_stop', <String, Object?>{
        'templateKey': str(p['templateKey']),
      }, newRequestId());
      ref.invalidate(programsProvider);
      refreshTrain(ref);
    } catch (e) {
      if (context.mounted) say(context, errorWords(e, context));
    }
  }
}

class _RecentSection extends ConsumerWidget {
  const _RecentSection({required this.rows});

  final List<Json> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            t.healthRecent,
            style: TextStyle(
              color: c.muted,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PaperCard(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(str(r['title'])),
                        Text(
                          <String>[
                            dayName(context, str(r['day'])),
                            t.healthWorkoutMinutes('${intOf(r['minutes'])}'),
                          ].join(' · '),
                          style: TextStyle(color: c.muted, fontSize: 13),
                        ),
                        if (boolOf(r['byAgent'])) const ByBotlerMark(),
                      ],
                    ),
                  ),
                  if (boolOf(r['byAgent']))
                    TextButton(
                      onPressed: () async {
                        try {
                          await ref.read(apiProvider).verb(
                            'workout_delete',
                            <String, Object?>{'id': str(r['id'])},
                            newRequestId(),
                          );
                          refreshTrain(ref);
                        } catch (e) {
                          if (context.mounted) {
                            say(context, errorWords(e, context));
                          }
                        }
                      },
                      child: Text(t.healthUndo),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Logs a walk or a run that already happened.
Future<void> showLogWalkSheet(BuildContext context, WidgetRef ref) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LogWalkSheet(onSaved: () => refreshTrain(ref)),
    );

class _LogWalkSheet extends ConsumerStatefulWidget {
  const _LogWalkSheet({required this.onSaved});

  final VoidCallback onSaved;

  @override
  ConsumerState<_LogWalkSheet> createState() => _LogWalkSheetState();
}

class _LogWalkSheetState extends ConsumerState<_LogWalkSheet> {
  // -- STATES -- //

  final TextEditingController _minutes = TextEditingController();
  final TextEditingController _km = TextEditingController();
  late final Once _once = Once(() => setState(() {}));
  String _kind = 'walk';
  String? _error;

  // -- LIFECYCLES -- //

  @override
  void dispose() {
    _minutes.dispose();
    _km.dispose();
    super.dispose();
  }

  // -- FUNCTIONS -- //

  Future<void> _save() async {
    final t = context.t;
    final minutes = int.tryParse(_minutes.text.trim());
    if (minutes == null || minutes < 1 || minutes > 600) {
      setState(() => _error = t.healthMinutesBad);
      return;
    }
    final distance = _km.text.trim().isEmpty
        ? null
        : thousandthsFromText(_km.text);
    final navigator = Navigator.of(context);
    try {
      await _once.run((key) async {
        await writeOrQueue(ref, 'workout_log', <String, Object?>{
          'kind': _kind,
          'minutes': minutes,
          'distanceM': ?distance,
        }, key);
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
            t.healthLogWalkTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          ChoiceRow<String>(
            choices: <(String, String)>[
              ('walk', t.healthKindWalk),
              ('run', t.healthKindRun),
            ],
            value: _kind,
            onChanged: (v) => setState(() => _kind = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _minutes,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: t.healthMinutesField,
              errorText: _error,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _km,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: t.healthDistanceField),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _once.running() ? null : () => unawaited(_save()),
              child: Text(t.healthWalkSave),
            ),
          ),
        ],
      ),
    );
  }
}
