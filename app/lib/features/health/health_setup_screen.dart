// HEALTH SETUP IN TWO SHORT STEPS. IT CAN STOP AT ANY POINT: WHAT WAS SAVED STAYS, AND THE HOME SCREEN OFFERS TO FINISH IT. THE TARGET AND ITS DATE COME FROM THE SERVER'S PREVIEW.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/health_units.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/health.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'health_parts.dart';

// -- TYPES -- //

class HealthSetupScreen extends ConsumerStatefulWidget {
  const HealthSetupScreen({super.key});

  @override
  ConsumerState<HealthSetupScreen> createState() => _HealthSetupScreenState();
}

class _HealthSetupScreenState extends ConsumerState<HealthSetupScreen> {
  // -- STATES -- //

  final TextEditingController _height = TextEditingController();
  final TextEditingController _weight = TextEditingController();
  final TextEditingController _year = TextEditingController();
  final TextEditingController _goalWeight = TextEditingController();
  late final Once _once = Once(() => setState(() {}));
  int _step = 1;
  String _sex = 'skip';
  String _activity = 'sitting';
  String _goal = 'lose';
  int _pace = 50;
  bool _filled = false;
  Json? _preview;
  String? _error;
  Timer? _debounce;

  // -- LIFECYCLES -- //

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    _year.dispose();
    _goalWeight.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // -- FUNCTIONS -- //

  void _fillFrom(Json health) {
    if (_filled) return;
    _filled = true;
    final p = asJson(health['profile']);
    final g = asJson(health['goal']);
    if (p['heightMm'] != null) {
      _height.text = '${(intOf(p['heightMm']) / 10).round()}';
    }
    if (health['latestWeightG'] != null) {
      _weight.text = kgText(intOf(health['latestWeightG']));
    }
    if (p['birthYear'] != null) _year.text = '${intOf(p['birthYear'])}';
    _sex = str(p['sex'], 'skip');
    _activity = str(p['activity'], 'sitting');
    final kind = str(g['kind'], 'track');
    if (kind != 'track') _goal = kind;
    _pace = intOf(g['paceBp'], 50);
    if (g['goalWeightG'] != null) {
      _goalWeight.text = kgText(intOf(g['goalWeightG']));
    }
  }

  Future<void> _next() async {
    setState(() => _error = null);
    final height = mmFromCmText(_height.text);
    final weight = gramsFromKgText(_weight.text);
    final year = int.tryParse(_year.text.trim());
    try {
      await _once.run((key) async {
        await ref.read(apiProvider).verb(
          'health_profile_save',
          <String, Object?>{
            'heightMm': ?height,
            'weightG': ?weight,
            'birthYear': ?year,
            'sex': _sex,
            'activity': _activity,
          },
          key,
        );
      }, intent: 'facts:$height:$weight:$year:$_sex:$_activity');
      if (!mounted) return;
      setState(() => _step = 2);
      _askPreview();
    } catch (e) {
      if (mounted) setState(() => _error = errorWords(e, context));
    }
  }

  Json get _goalArgs => <String, Object?>{
    'kind': _goal,
    if (_goal == 'lose' || _goal == 'gain') ...<String, Object?>{
      'goalWeightG': gramsFromKgText(_goalWeight.text),
      'paceBp': _pace,
    },
  };

  void _askPreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await ref
            .read(apiProvider)
            .verbJson('health_goal_preview', _goalArgs);
        if (mounted) setState(() => _preview = r);
      } catch (_) {
        // The preview only helps: saving still checks everything and says what is wrong
        if (mounted) setState(() => _preview = null);
      }
    });
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      await _once.run((key) async {
        await ref.read(apiProvider).verb('health_goal_set', _goalArgs, key);
        await ref.read(apiProvider).verb(
          'health_profile_save',
          <String, Object?>{'setupDone': true},
        );
      }, intent: 'goal:${_goalArgs.toString()}');
      ref
        ..invalidate(healthProvider)
        ..invalidate(healthHomeProvider);
      if (mounted && context.canPop()) context.pop();
    } catch (e) {
      if (mounted) setState(() => _error = errorWords(e, context));
    }
  }

  // -- WIDGETS -- //

  Widget _stepHeader(String text) {
    final c = context.colors;
    return Row(
      children: <Widget>[
        for (final i in const <int>[1, 2]) ...<Widget>[
          Expanded(child: ThinBar(i <= _step ? 100 : 0, height: 4)),
          const SizedBox(width: 6),
        ],
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: c.muted, fontSize: 13)),
      ],
    );
  }

  Widget _about() {
    final t = context.t;
    final c = context.colors;
    return ListView(
      padding: pagePadding(context),
      children: <Widget>[
        _stepHeader(t.healthStepOf('1')),
        const SizedBox(height: 16),
        BigNumber(t.healthSetupAboutTitle, size: 30),
        const SizedBox(height: 6),
        Text(t.healthSetupAboutLine, style: TextStyle(color: c.muted)),
        const SizedBox(height: 16),
        PaperCard(
          child: Column(
            children: <Widget>[
              Field(
                controller: _height,
                label: t.healthFieldHeight,
                hint: t.healthFieldHeightHint,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              Field(
                controller: _weight,
                label: t.healthFieldWeight,
                hint: t.healthFieldWeightHint,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              Field(
                controller: _year,
                label: t.healthFieldYear,
                hint: t.healthFieldYearHint,
                keyboard: TextInputType.number,
              ),
            ],
          ),
        ),
        SectionTitle(t.healthFieldSex),
        ChoiceRow<String>(
          value: _sex,
          onChanged: (v) => setState(() => _sex = v),
          choices: <(String, String)>[
            ('female', t.healthSexFemale),
            ('male', t.healthSexMale),
            ('skip', t.healthSexSkip),
          ],
        ),
        SectionTitle(t.healthFieldActivity),
        ChoiceRow<String>(
          value: _activity,
          onChanged: (v) => setState(() => _activity = v),
          choices: <(String, String)>[
            ('sitting', t.healthActivitySitting),
            ('some_walking', t.healthActivityWalking),
            ('on_feet', t.healthActivityFeet),
            ('very_active', t.healthActivityVery),
          ],
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          Note(_error ?? ''),
        ],
      ],
    );
  }

  Widget _goalStep() {
    final t = context.t;
    final c = context.colors;
    final preview = _preview;
    final problem = preview == null ? '' : str(preview['problem']);
    final target = preview?['targetKcal'];
    final reachOn = preview == null ? '' : str(preview['reachOn']);
    final grams = intOf(preview?['gramsPerWeek']);
    final weighs = _goal == 'lose' || _goal == 'gain';
    return ListView(
      padding: pagePadding(context),
      children: <Widget>[
        _stepHeader(t.healthStepOf('2')),
        const SizedBox(height: 16),
        BigNumber(t.healthSetupGoalTitle, size: 30),
        const SizedBox(height: 16),
        ChoiceRow<String>(
          value: _goal,
          onChanged: (v) {
            setState(() => _goal = v);
            _askPreview();
          },
          choices: <(String, String)>[
            ('lose', t.healthGoalLose),
            ('maintain', t.healthGoalMaintain),
            ('gain', t.healthGoalGain),
            ('track', t.healthGoalTrack),
          ],
        ),
        if (weighs) ...<Widget>[
          const SizedBox(height: 16),
          PaperCard(
            child: Field(
              controller: _goalWeight,
              label: t.healthFieldGoalWeight,
              hint: t.healthFieldWeightHint,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _askPreview(),
            ),
          ),
          SectionTitle(t.healthPaceTitle),
          ChoiceRow<int>(
            value: _pace,
            onChanged: (v) {
              setState(() => _pace = v);
              _askPreview();
            },
            choices: <(int, String)>[
              (25, t.healthPaceGentle),
              (50, t.healthPaceSteady),
              if (_goal == 'lose') (100, t.healthPaceFastest),
            ],
          ),
        ],
        const SizedBox(height: 16),
        if (problem.isNotEmpty)
          Note(problem)
        else if (target != null)
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  t.healthPreviewTitle,
                  style: TextStyle(
                    color: c.accentText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                BigNumber(
                  t.healthPreviewKcal(kcalText(intOf(target))),
                  size: 28,
                  color: c.accentText,
                ),
                if (reachOn.isNotEmpty && weighs) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    t.healthPreviewReach(kgText(grams), reachOn),
                    style: TextStyle(color: c.accentText),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 12),
        Text(
          t.healthNotMedical,
          style: TextStyle(color: c.muted, fontSize: 13),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          Note(_error ?? ''),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final health = ref.watch(healthProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.healthSetupTitle)),
      body: AsyncBody<Json>(
        value: health,
        onRetry: () => ref.invalidate(healthProvider),
        data: (h) {
          _fillFrom(h);
          return _step == 1 ? _about() : _goalStep();
        },
      ),
      bottomNavigationBar: BottomDock(
        primary: FilledButton(
          onPressed: _once.running() ? null : (_step == 1 ? _next : _start),
          child: Text(_step == 1 ? t.healthNext : t.healthStart),
        ),
        below: _step == 1
            ? TextButton(
                onPressed: () => context.pop(),
                child: Text(t.healthFinishLater),
              )
            : TextButton(
                onPressed: () => setState(() => _step = 1),
                child: Text(t.healthBack),
              ),
      ),
    );
  }
}
