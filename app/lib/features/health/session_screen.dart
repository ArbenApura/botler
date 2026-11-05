// ONE WORKOUT AS IT HAPPENS. THE SERVER BUILDS THE SESSION FROM THE PROGRAM AND REFUSES ANY SET IT DID NOT PLACE, SO THIS SCREEN ONLY FILLS IN WHAT WAS DONE.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'health_parts.dart';
import 'train_screen.dart';

// -- CONSTANTS -- //

const int _restSeconds = 60;

// -- TYPES -- //

class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({this.plannedId, this.templateKey, super.key});

  final String? plannedId;
  final String? templateKey;

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  // -- STATES -- //

  late final Once _once = Once(() => setState(() {}));
  Json? _session;
  String? _error;
  Timer? _clock;
  int _rest = 0;

  // -- LIFECYCLES -- //

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  // -- FUNCTIONS -- //

  Future<void> _call(String verb, Json args, {String intent = ''}) async {
    try {
      await _once.run((key) async {
        final answer = await ref.read(apiProvider).verbJson(verb, args, key);
        if (mounted) setState(() => _session = answer);
      }, intent: intent);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _start() => _call('workout_start', <String, Object?>{
    if (widget.plannedId != null) 'plannedId': widget.plannedId,
    if (widget.templateKey != null) 'templateKey': widget.templateKey,
  }, intent: 'start');

  /// The first exercise with a set still open, or the last one.
  int _current(List<Json> exercises) {
    for (var i = 0; i < exercises.length; i++) {
      if (asJsonList(exercises[i]['sets']).any((s) => !boolOf(s['done']))) {
        return i;
      }
    }
    return exercises.length - 1;
  }

  void _startRest() {
    _clock?.cancel();
    setState(() => _rest = _restSeconds);
    _clock = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _rest -= 1);
      if (_rest <= 0) timer.cancel();
    });
  }

  Future<void> _logSet(Json exercise, Json set) async {
    final isHold = str(exercise['measure']) == 'seconds';
    final value = await _askValue(
      isHold ? context.t.healthSecondsAsk : context.t.healthRepsAsk,
      intOf(set['reps'], intOf(set['seconds'], intOf(exercise['aim']))),
    );
    if (value == null || !mounted) return;
    await _call('workout_set_log', <String, Object?>{
      'sessionId': str(_session?['id']),
      'exerciseKey': str(exercise['exerciseKey']),
      'position': intOf(set['position']),
      if (isHold) 'seconds': value else 'reps': value,
    }, intent: 'set-${exercise['exerciseKey']}-${set['position']}-$value');
    _startRest();
  }

  Future<int?> _askValue(String title, int start) => showDialog<int>(
    context: context,
    builder: (_) => _ValueDialog(title: title, start: start),
  );

  Future<void> _swap(Json exercise) async {
    final t = context.t;
    final level = intOf(exercise['level']);
    final ladder = asList(exercise['ladder']);
    final direction = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (level > 0)
              ListTile(
                leading: const Icon(Icons.south),
                title: Text(t.healthEasier),
                subtitle: Text(str(ladder[level - 1])),
                onTap: () => Navigator.pop(ctx, 'easier'),
              ),
            if (level < ladder.length - 1)
              ListTile(
                leading: const Icon(Icons.north),
                title: Text(t.healthHarder),
                subtitle: Text(str(ladder[level + 1])),
                onTap: () => Navigator.pop(ctx, 'harder'),
              ),
          ],
        ),
      ),
    );
    if (direction == null) return;
    await _call('workout_swap', <String, Object?>{
      'sessionId': str(_session?['id']),
      'exerciseKey': str(exercise['exerciseKey']),
      'direction': direction,
    }, intent: 'swap-${exercise['exerciseKey']}-$direction');
  }

  Future<void> _finish() async {
    final t = context.t;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await _once.run((key) async {
        final done = await ref.read(apiProvider).verbJson(
          'workout_finish',
          <String, Object?>{'sessionId': str(_session?['id'])},
          key,
        );
        final up = asList(done['levelledUp']).map(str).toList();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              up.isEmpty
                  ? t.healthWorkoutSaved
                  : t.healthLevelUp(up.join(', ')),
            ),
          ),
        );
      }, intent: 'finish');
      refreshTrain(ref);
      if (router.canPop()) router.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  // -- WIDGETS -- //

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final s = _session;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error == null
            ? const SkeletonPage(
                child: SkeletonRows(count: 3, kind: SkeletonKind.tile),
              )
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error ?? '', style: TextStyle(color: c.danger)),
              ),
      );
    }
    final exercises = asJsonList(s['exercises']);
    final run = s['run'];
    final index = exercises.isEmpty ? 0 : _current(exercises);
    final current = exercises.isEmpty ? null : exercises[index];
    final allSets = exercises.expand((e) => asJsonList(e['sets']));
    final doneSets = allSets.where((x) => boolOf(x['done'])).length;
    final percent = allSets.isEmpty ? 0 : doneSets * 100 ~/ allSets.length;
    final openSet = current == null
        ? null
        : asJsonList(current['sets'])
              .where((x) => !boolOf(x['done']))
              .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(str(s['title']))),
      body: ListView(
        padding: pagePadding(context),
        children: <Widget>[
          if (current != null) ...<Widget>[
            Text(
              t.healthExerciseOf('${index + 1}', '${exercises.length}'),
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
            const SizedBox(height: 6),
            ThinBar(percent),
            const SizedBox(height: 12),
            _ExerciseCard(
              exercise: current,
              rest: _rest,
              onSkipRest: () {
                _clock?.cancel();
                setState(() => _rest = 0);
              },
              onSet: (set) => unawaited(_logSet(current, set)),
            ),
            const SizedBox(height: 12),
            PaperCard(
              child: Column(
                children: <Widget>[
                  for (final e in exercises)
                    if (e != current) _NextMove(exercise: e),
                ],
              ),
            ),
          ],
          if (run is Map) _RunCard(run: asJson(run)),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_error ?? '', style: TextStyle(color: c.danger)),
          ],
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              t.healthPainNote,
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomDock(
        primary: openSet != null && current != null
            ? FilledButton(
                onPressed: _once.running()
                    ? null
                    : () => unawaited(_logSet(current, openSet)),
                child: Text(t.healthFinishSet),
              )
            : FilledButton(
                onPressed: _once.running() ? null : () => unawaited(_finish()),
                child: Text(t.healthFinishWorkout),
              ),
        below: Row(
          children: <Widget>[
            if (openSet != null)
              TextButton(
                onPressed: _once.running() ? null : () => unawaited(_finish()),
                child: Text(t.healthFinishWorkout),
              ),
            const Spacer(),
            if (current != null)
              TextButton(
                onPressed: _once.running()
                    ? null
                    : () => unawaited(_swap(current)),
                child: Text(t.healthSwap),
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks for one whole number. It owns its text field, so the field lives until the dialog has finished closing.
class _ValueDialog extends StatefulWidget {
  const _ValueDialog({required this.title, required this.start});

  final String title;
  final int start;

  @override
  State<_ValueDialog> createState() => _ValueDialogState();
}

class _ValueDialogState extends State<_ValueDialog> {
  late final TextEditingController _field = TextEditingController(
    text: '${widget.start}',
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _field,
      autofocus: true,
      keyboardType: TextInputType.number,
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () =>
            Navigator.pop(context, int.tryParse(_field.text.trim())),
        child: Text(context.t.healthSave),
      ),
    ],
  );
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.exercise,
    required this.rest,
    required this.onSkipRest,
    required this.onSet,
  });

  final Json exercise;
  final int rest;
  final VoidCallback onSkipRest;
  final ValueChanged<Json> onSet;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final sets = asJsonList(exercise['sets']);
    final isHold = str(exercise['measure']) == 'seconds';
    final low = '${intOf(exercise['low'])}';
    final high = '${intOf(exercise['high'])}';
    final level = intOf(exercise['level']);
    final ladder = asList(exercise['ladder']).map(str).toList();
    final firstOpen = sets.indexWhere((s) => !boolOf(s['done']));
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          BigNumber(str(exercise['name']), size: 30),
          const SizedBox(height: 4),
          Text(
            '${isHold ? t.healthSetsOfHolds('${sets.length}', low, high) : t.healthSetsOfReps('${sets.length}', low, high)} ${str(exercise['how'])}',
            style: TextStyle(color: c.muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              for (var i = 0; i < sets.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _SetButton(
                    set: sets[i],
                    index: i,
                    now: i == firstOpen,
                    aim: intOf(exercise['aim']),
                    isHold: isHold,
                    onTap: () => onSet(sets[i]),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Text(
            t.healthYourPath,
            style: TextStyle(
              color: c.muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              for (var i = 0; i < ladder.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      ThinBar(i <= level ? 100 : 0, height: 4),
                      const SizedBox(height: 5),
                      Text(
                        ladder[i],
                        style: TextStyle(
                          fontSize: 12,
                          color: i == level ? c.ink : c.muted,
                          fontWeight: i == level
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            level < ladder.length - 1
                ? t.healthPathNext(high, ladder[level + 1])
                : t.healthPathTop,
            style: TextStyle(color: c.accentText, fontSize: 13),
          ),
          if (rest > 0) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Icon(Icons.schedule, size: 20, color: c.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.healthRestLeft(
                      '${rest ~/ 60}:${(rest % 60).toString().padLeft(2, '0')}',
                    ),
                    style: TextStyle(fontFeatures: tabular),
                  ),
                ),
                TextButton(onPressed: onSkipRest, child: Text(t.healthSkip)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SetButton extends StatelessWidget {
  const _SetButton({
    required this.set,
    required this.index,
    required this.now,
    required this.aim,
    required this.isHold,
    required this.onTap,
  });

  final Json set;
  final int index;
  final bool now;
  final int aim;
  final bool isHold;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final done = boolOf(set['done']);
    final value = done ? intOf(set['reps'], intOf(set['seconds'])) : aim;
    final text = isHold ? t.healthSecondsShort('$value') : '$value';
    return Semantics(
      button: true,
      label: done
          ? t.healthSetDoneLabel('${index + 1}', text)
          : t.healthSetOpenLabel('${index + 1}', text),
      child: ExcludeSemantics(
        child: Material(
          color: done ? c.accentSoft : c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: now ? c.accent : (done ? c.accentSoft : c.line),
              width: now ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Center(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 20,
                    color: done ? c.accentText : (now ? c.ink : c.muted),
                    fontFeatures: tabular,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NextMove extends StatelessWidget {
  const _NextMove({required this.exercise});

  final Json exercise;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final sets = asJsonList(exercise['sets']);
    final done = sets.every((s) => boolOf(s['done']));
    final low = '${intOf(exercise['low'])}';
    final high = '${intOf(exercise['high'])}';
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minTap),
      child: Row(
        children: <Widget>[
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 22,
            color: done ? c.accent : c.line,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  str(exercise['name']),
                  style: TextStyle(
                    color: done ? c.muted : c.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  str(exercise['measure']) == 'seconds'
                      ? t.healthSetsOfHolds('${sets.length}', low, high)
                      : t.healthSetsOfReps('${sets.length}', low, high),
                  style: TextStyle(color: c.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({required this.run});

  final Json run;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    String span(int seconds) => seconds >= 60 && seconds % 60 == 0
        ? t.healthWorkoutMinutes('${seconds ~/ 60}')
        : t.healthSecondsShort('$seconds');
    final walk = intOf(run['walk']);
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          BigNumber(
            walk == 0
                ? span(intOf(run['run']))
                : t.healthRunSteps(
                    span(intOf(run['run'])),
                    span(walk),
                    '${intOf(run['repeat'])}',
                  ),
            size: 26,
          ),
          const SizedBox(height: 6),
          Text(str(run['note']), style: TextStyle(color: c.muted)),
          const SizedBox(height: 6),
          Text(t.healthRunWarm, style: TextStyle(color: c.muted)),
          const SizedBox(height: 6),
          Text(
            t.healthRunTotal('${intOf(run['minutes'])}'),
            style: TextStyle(color: c.accentText),
          ),
        ],
      ),
    );
  }
}
