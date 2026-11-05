// NEXT WEEK: WHAT THE SERVER WORKED OUT AROUND WORK AND THE CALENDAR. NOTHING IS SET UNTIL IT IS ACCEPTED, AND THE SERVER CHECKS THE FREE TIME AGAIN AT THAT MOMENT.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/manila.dart';
import '../../l10n/l10n.dart';
import '../../state/health_more.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'health_parts.dart';
import 'train_screen.dart';

// -- TYPES -- //

class WeekPlanScreen extends ConsumerStatefulWidget {
  const WeekPlanScreen({super.key});

  @override
  ConsumerState<WeekPlanScreen> createState() => _WeekPlanScreenState();
}

class _WeekPlanScreenState extends ConsumerState<WeekPlanScreen> {
  // -- STATES -- //

  late final Once _once = Once(() => setState(() {}));
  Json? _week;
  String? _proposalId;
  String? _error;
  bool _stale = false;

  // -- LIFECYCLES -- //

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  // -- FUNCTIONS -- //

  /// Shows the open proposal, or asks for one. Asking is a write of a proposal only: no session exists yet.
  Future<void> _load({bool again = false}) async {
    final api = ref.read(apiProvider);
    try {
      if (!again) {
        final open = await api.verbList('proposals_list');
        final week = open.where((p) => str(p['kind']) == 'week').firstOrNull;
        // A proposal for a week already over is of no use: a new one is worked out below
        final over =
            week != null &&
            _dayText(
                  DateTime.parse(str(asJson(week['payload'])['monday']))
                      .add(const Duration(days: 6)),
                ).compareTo(manilaToday()) <
                0;
        if (week != null && !over) {
          if (mounted) {
            setState(() {
              _week = asJson(week['payload']);
              _proposalId = str(week['id']);
            });
          }
          return;
        }
      }
      await _once.run((key) async {
        final made = await api.verbJson(
          'week_propose',
          const <String, Object?>{},
          key,
        );
        if (mounted) {
          setState(() {
            _week = made;
            _proposalId = str(made['proposalId']);
            _stale = false;
            _error = null;
          });
        }
      }, intent: 'propose');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _accept() async {
    final t = context.t;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await _once.run((key) async {
        await ref.read(apiProvider).verb('proposal_answer', <String, Object?>{
          'proposalId': _proposalId,
          'accept': true,
        }, key);
      }, intent: 'accept');
      refreshTrain(ref);
      ref.invalidate(proposalsProvider);
      messenger.showSnackBar(SnackBar(content: Text(t.healthWeekAccepted)));
      if (router.canPop()) router.pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _stale = true;
        });
      }
    }
  }

  // -- WIDGETS -- //

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final week = _week;
    if (week == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t.healthNextWeek)),
        body: _error == null
            ? const SkeletonPage(
                child: SkeletonRows(count: 5, kind: SkeletonKind.tile),
              )
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error ?? '', style: TextStyle(color: c.danger)),
              ),
      );
    }
    final placed = asJsonList(week['placed']);
    final unplaced = asJsonList(week['unplaced']);
    final monday = DateTime.parse(str(week['monday']));
    return Scaffold(
      appBar: AppBar(title: Text(t.healthNextWeek)),
      body: ListView(
        padding: pagePadding(context),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(t.healthWeekIntro, style: TextStyle(color: c.muted)),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _Stat(
                  value: '${intOf(week['movingMinutes'])}',
                  line: t.healthMinutesMoving,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Stat(
                  value: '${intOf(week['strengthDays'])}',
                  line: t.healthStrengthDays,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PaperCard(
            child: Column(
              children: <Widget>[
                for (var i = 0; i < 7; i++) ...<Widget>[
                  if (i > 0) Divider(color: c.line, height: 1),
                  _PlanDay(
                    day: monday.add(Duration(days: i)),
                    session: placed
                        .where(
                          (p) =>
                              str(p['day']) ==
                              _dayText(monday.add(Duration(days: i))),
                        )
                        .firstOrNull,
                  ),
                ],
              ],
            ),
          ),
          if (unplaced.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                t.healthNoFit(
                  unplaced.map((u) => str(u['title'])).toSet().join(', '),
                ),
                style: TextStyle(color: c.muted),
              ),
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_error ?? '', style: TextStyle(color: c.danger)),
          ],
        ],
      ),
      bottomNavigationBar: BottomDock(
        showAsk: true,
        primary: _stale
            ? FilledButton(
                onPressed: _once.running()
                    ? null
                    : () => unawaited(_load(again: true)),
                child: Text(t.healthNewWeek),
              )
            : FilledButton(
                onPressed: _once.running() || placed.isEmpty
                    ? null
                    : () => unawaited(_accept()),
                child: Text(t.healthAcceptWeek),
              ),
      ),
    );
  }
}

String _dayText(DateTime d) => isoOf(d);

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.line});

  final String value;
  final String line;

  @override
  Widget build(BuildContext context) => PaperCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        BigNumber(value, size: 30),
        Text(line, style: TextStyle(color: context.colors.muted, fontSize: 13)),
      ],
    ),
  );
}

class _PlanDay extends StatelessWidget {
  const _PlanDay({required this.day, required this.session});

  final DateTime day;
  final Json? session;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final s = session;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 44,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  dayName(context, _dayText(day)),
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w300,
                    fontFeatures: tabular,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: s == null
                ? Text(t.healthPlanRest, style: TextStyle(color: c.muted))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        str(s['title']),
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        t.healthPlanWhen(
                          '${intOf(s['minutes'])}',
                          clockText(context, str(s['time'])),
                        ),
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
