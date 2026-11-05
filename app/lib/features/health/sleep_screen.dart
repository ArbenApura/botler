// SLEEP: WHEN AND HOW LONG, WITH NO SCORES. A PATTERN SHOWS ONLY AFTER 14 NIGHTS AND IS WORDED AS SOMETHING TO NOTICE, NEVER A CAUSE.

// -- DEP-MODULES -- //
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -- MODULES -- //
import '../../core/api.dart';
import '../../core/health_units.dart';
import '../../core/json.dart';
import '../../l10n/l10n.dart';
import '../../state/health.dart';
import '../../state/health_more.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'food_sheets.dart';
import 'health_charts.dart';
import 'health_parts.dart';
import 'train_screen.dart';

// -- CONSTANTS -- //

/// The chart's clock starts at 9 pm.
const int _chartStartMinute = 21 * 60;

// -- FUNCTIONS -- //

/// An instant as minutes after 21:00 on the evening before its Manila wake day. Manila has one offset and no clock changes.
int _chartMinute(String iso) {
  final m = DateTime.parse(iso).toUtc().add(const Duration(hours: 8));
  final minute = m.hour * 60 + m.minute;
  return minute >= _chartStartMinute
      ? minute - _chartStartMinute
      : minute + 24 * 60 - _chartStartMinute;
}

String _clockOfIso(BuildContext context, String iso) {
  final m = DateTime.parse(iso).toUtc().add(const Duration(hours: 8));
  return MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay(hour: m.hour, minute: m.minute));
}

// -- TYPES -- //

class SleepScreen extends ConsumerWidget {
  const SleepScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref
      ..invalidate(sleepProvider)
      ..invalidate(healthHomeProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final c = context.colors;
    final sleep = ref.watch(sleepProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.healthSleepTitle)),
      body: AsyncBody<Json>(
        value: sleep,
        onRetry: () => _refresh(ref),
        skeleton: const SkeletonPage(
          child: SkeletonRows(count: 3, kind: SkeletonKind.tile),
        ),
        data: (d) {
          final last = d['last'];
          final nights = asJsonList(d['nights']);
          final average = d['averageMinutes'] is num
              ? intOf(d['averageMinutes'])
              : null;
          final spread = d['bedtimeSpreadMinutes'] is num
              ? intOf(d['bedtimeSpreadMinutes'])
              : null;
          final pattern = d['pattern'];
          return RefreshIndicator(
            onRefresh: () async => _refresh(ref),
            child: ListView(
              padding: pagePadding(context),
              children: <Widget>[
                if (last is Map)
                  _LastNight(
                    entry: asJson(last),
                    onChanged: () => _refresh(ref),
                  )
                else
                  PaperCard(
                    child: Text(
                      t.healthSleepEmpty,
                      style: TextStyle(color: c.muted),
                    ),
                  ),
                if (nights.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  PaperCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                t.healthSevenNights,
                                style: TextStyle(
                                  color: c.muted,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (average != null)
                              Flexible(
                                child: Text(
                                  t.healthAboutTime(durationText(average)),
                                  textAlign: TextAlign.end,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SleepNightsChart(
                          nights: <SleepNight>[
                            for (final n in nights)
                              SleepNight(
                                day: str(n['day']),
                                startMinute: _chartMinute(str(n['startsAt'])),
                                endMinute: _chartMinute(str(n['endsAt'])),
                              ),
                          ],
                          dayLabels: <String>[
                            for (final n in nights)
                              dayName(context, str(n['day'])),
                          ],
                          hourLabels: <String>[
                            for (final h in <int>[21, 0, 3, 6, 9])
                              MaterialLocalizations.of(
                                context,
                              ).formatTimeOfDay(TimeOfDay(hour: h, minute: 0)),
                          ],
                          label: t.healthSleepChart,
                        ),
                        if (spread != null) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            t.healthBedtimeSteady(durationText(spread)),
                            style: TextStyle(color: c.muted, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _WindDownCard(data: d, onChanged: () => _refresh(ref)),
                if (pattern is Map) ...<Widget>[
                  const SizedBox(height: 12),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          t.healthPatternTitle,
                          style: TextStyle(
                            color: c.accentText,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.healthPatternLine(
                            kcalText(
                              intOf(asJson(pattern)['shortNightExtraKcal']),
                            ),
                          ),
                          style: TextStyle(color: c.accentText),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: BottomDock(
        showAsk: true,
        primary: FilledButton.icon(
          onPressed: () => unawaited(
            showModalBottomSheet<void>(
              context: context,
              builder: (_) => _AddSleepSheet(onSaved: () => _refresh(ref)),
            ),
          ),
          icon: const Icon(Icons.add),
          label: Text(t.healthAddSleep),
        ),
      ),
    );
  }
}

class _LastNight extends ConsumerWidget {
  const _LastNight({required this.entry, required this.onChanged});

  final Json entry;
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
            t.healthLastNightTitle,
            style: TextStyle(color: c.muted, fontSize: 14),
          ),
          const SizedBox(height: 4),
          BigNumber(durationText(intOf(entry['minutes']))),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Icon(Icons.bedtime_outlined, size: 16, color: c.muted),
              const SizedBox(width: 4),
              Text(
                _clockOfIso(context, str(entry['startsAt'])),
                style: TextStyle(color: c.muted, fontSize: 14),
              ),
              Icon(Icons.chevron_right, size: 14, color: c.muted),
              Icon(Icons.wb_sunny_outlined, size: 16, color: c.muted),
              const SizedBox(width: 4),
              Text(
                _clockOfIso(context, str(entry['endsAt'])),
                style: TextStyle(color: c.muted, fontSize: 14),
              ),
            ],
          ),
          if (boolOf(entry['byAgent']))
            Row(
              children: <Widget>[
                const ByBotlerMark(),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    try {
                      await ref.read(apiProvider).verb(
                        'sleep_delete',
                        <String, Object?>{'id': str(entry['id'])},
                        newRequestId(),
                      );
                      onChanged();
                    } catch (e) {
                      if (context.mounted) say(context, errorWords(e, context));
                    }
                  },
                  child: Text(t.healthUndo),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _WindDownCard extends ConsumerStatefulWidget {
  const _WindDownCard({required this.data, required this.onChanged});

  final Json data;
  final VoidCallback onChanged;

  @override
  ConsumerState<_WindDownCard> createState() => _WindDownCardState();
}

class _WindDownCardState extends ConsumerState<_WindDownCard> {
  late final Once _once = Once(() => setState(() {}));

  Future<void> _set(bool on) async {
    await _once.run((key) async {
      await ref.read(apiProvider).verb(
        'availability_setting_set',
        <String, Object?>{'windDown': on},
        key,
      );
    }, intent: 'wind-$on');
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final on = boolOf(widget.data['windDownOn']);
    final tonight = widget.data['windDownTonight'];
    final hasTime = tonight is Map;
    final j = hasTime ? asJson(tonight) : const <String, Object?>{};
    return PaperCard(
      child: StatRow(
        icon: Icons.bedtime_outlined,
        title: hasTime
            ? t.healthWindDownBy(clockText(context, str(j['time'])))
            : t.healthWindDownNone,
        line: hasTime
            ? t.healthWindDownWhy(clockText(context, str(j['firstAt'])))
            : t.healthWindDownNoEarly,
        trailing: Semantics(
          label: t.healthWindDownSwitch,
          child: Switch(
            value: on,
            onChanged: _once.running() ? null : (v) => unawaited(_set(v)),
          ),
        ),
      ),
    );
  }
}

class _AddSleepSheet extends ConsumerStatefulWidget {
  const _AddSleepSheet({required this.onSaved});

  final VoidCallback onSaved;

  @override
  ConsumerState<_AddSleepSheet> createState() => _AddSleepSheetState();
}

class _AddSleepSheetState extends ConsumerState<_AddSleepSheet> {
  // -- STATES -- //

  late final Once _once = Once(() => setState(() {}));
  TimeOfDay _from = const TimeOfDay(hour: 23, minute: 0);
  TimeOfDay _to = const TimeOfDay(hour: 6, minute: 0);
  String? _error;

  // -- FUNCTIONS -- //

  String _text(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pick(bool from) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: from ? _from : _to,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    try {
      await _once.run((key) async {
        await writeOrQueue(ref, 'sleep_log', <String, Object?>{
          'from': _text(_from),
          'to': _text(_to),
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
    final c = context.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              t.healthWokeToday,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bedtime_outlined),
              title: Text(t.healthSleepFrom),
              trailing: Text(_from.format(context)),
              onTap: () => unawaited(_pick(true)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.wb_sunny_outlined),
              title: Text(t.healthSleepTo),
              trailing: Text(_to.format(context)),
              onTap: () => unawaited(_pick(false)),
            ),
            if (_error != null)
              Text(_error ?? '', style: TextStyle(color: c.danger)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _once.running() ? null : () => unawaited(_save()),
                child: Text(t.healthSaveSleep),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
