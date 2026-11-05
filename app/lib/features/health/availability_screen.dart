// MY WEEK: WORK HOURS AND FREE TIME PER WEEKDAY, CHANGES FOR ONE DATE, AWAKE HOURS AND TRAVEL TIME. THE PLANNER AND THE REMINDERS READ THIS. ONE PRIMARY ACTION: SAVE MY WEEK.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/manila.dart';
import '../../l10n/l10n.dart';
import '../../state/health.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../ui/ui.dart';
import 'health_parts.dart';

// -- FUNCTIONS -- //

TimeOfDay _time(String hhmm) {
  final p = hhmm.split(':');
  return TimeOfDay(
    hour: p.isNotEmpty ? int.tryParse(p[0]) ?? 0 : 0,
    minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0,
  );
}

String _hhmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

int _minutes(String hhmm) {
  final t = _time(hhmm);
  return t.hour * 60 + t.minute;
}

// -- TYPES -- //

class AvailabilityScreen extends ConsumerStatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  ConsumerState<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends ConsumerState<AvailabilityScreen> {
  // -- STATES -- //

  /// The blocks being edited, per weekday. Null until the server answered.
  Map<int, List<Json>>? _days;
  late final Once _once = Once(() => setState(() {}));

  // -- FUNCTIONS -- //

  void _fill(Json data) {
    if (_days != null) return;
    _days = <int, List<Json>>{
      for (final d in asJsonList(data['days']))
        intOf(d['weekday']): asJsonList(d['blocks']),
    };
  }

  String _dayName(int weekday) {
    // 2023-01-01 was a Sunday, so the weekday numbers line up with the server's
    final locale = Localizations.localeOf(context).languageCode;
    return DateFormat.EEEE(locale).format(DateTime.utc(2023, 1, 1 + weekday));
  }

  String _clock(String hhmm) => _time(hhmm).format(context);

  /// Every block of the day in words: the work times, then the busy ones. Free blocks are the default and need no words.
  String _workLine(List<Json> blocks) {
    final t = context.t;
    String ranges(String kind) =>
        (blocks.where((b) => str(b['kind']) == kind).toList()
              ..sort((a, b) => str(a['start']).compareTo(str(b['start']))))
            .map(
              (b) => t.healthWeekRange(
                _clock(str(b['start'])),
                _clock(str(b['end'])),
              ),
            )
            .join(', ');
    final work = ranges('work');
    final busy = ranges('busy');
    if (work.isEmpty && busy.isEmpty) return t.healthWeekFree;
    return <String>[
      if (work.isNotEmpty) work,
      if (busy.isNotEmpty) t.healthWeekBusyLine(busy),
    ].join(' · ');
  }

  Future<void> _editDay(int weekday) async {
    final days = _days;
    if (days == null) return;
    final result = await showModalBottomSheet<_DayEdit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DaySheet(
        title: _dayName(weekday),
        blocks: days[weekday] ?? <Json>[],
        showCopy: weekday == 1,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      days[weekday] = result.blocks;
      if (result.copyToWeekdays) {
        for (final w in const <int>[2, 3, 4, 5]) {
          days[w] = <Json>[
            for (final b in result.blocks) <String, Object?>{...b},
          ];
        }
      }
    });
  }

  Future<void> _save() async {
    final days = _days;
    if (days == null) return;
    final args = <String, Object?>{
      'days': <Json>[
        for (final e in days.entries)
          <String, Object?>{
            'weekdays': <int>[e.key],
            'blocks': <Json>[
              for (final b in e.value)
                <String, Object?>{
                  'start': b['start'],
                  'end': b['end'],
                  'kind': b['kind'],
                  if (str(b['label']).isNotEmpty) 'label': b['label'],
                },
            ],
          },
      ],
    };
    final t = context.t;
    await _once.run((key) async {
      final queued = await writeOrQueue(ref, 'availability_set', args, key);
      if (!mounted) return;
      say(context, queued ? t.healthSavedOffline : t.healthWeekSaved);
      ref.invalidate(availabilityProvider);
      if (context.canPop()) context.pop();
    }, intent: 'save:$args');
  }

  Future<void> _addChange() async {
    final today = manilaToday();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(today),
      firstDate: DateTime.parse(today),
      lastDate: DateTime.parse(addDaysTo(today, 365)),
    );
    if (picked == null || !mounted) return;
    final day = DateFormat('yyyy-MM-dd').format(picked);
    final result = await showModalBottomSheet<_DayEdit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DaySheet(
        title: _shortDate(day),
        blocks: <Json>[
          <String, Object?>{'start': '09:00', 'end': '15:00', 'kind': 'work'},
        ],
        showCopy: false,
      ),
    );
    if (result == null || !mounted) return;
    await _change(<String, Object?>{
      'day': day,
      if (result.blocks.isNotEmpty)
        'blocks': <Json>[
          for (final b in result.blocks)
            <String, Object?>{
              'start': b['start'],
              'end': b['end'],
              'kind': b['kind'],
            },
        ]
      else
        'off': true,
    });
  }

  Future<void> _change(Json args) async {
    try {
      await ref.read(apiProvider).verb('availability_override_set', args);
      ref.invalidate(availabilityProvider);
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
    }
  }

  Future<void> _setting(Json args) async {
    try {
      await ref.read(apiProvider).verb('availability_setting_set', args);
      ref.invalidate(availabilityProvider);
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
    }
  }

  Future<void> _pickAwake(String field, String now) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time(now),
    );
    if (picked != null) await _setting(<String, Object?>{field: _hhmm(picked)});
  }

  Future<void> _pickTravel(int now) async {
    final t = context.t;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final m in const <int>[0, 15, 30, 45, 60, 90])
              ListTile(
                title: Text(t.healthWeekMinutes('$m')),
                selected: m == now,
                onTap: () => Navigator.of(ctx).pop(m),
              ),
          ],
        ),
      ),
    );
    if (picked != null)
      await _setting(<String, Object?>{'travelMinutes': picked});
  }

  String _shortDate(String day) =>
      DateFormat.MMMEd(Localizations.localeOf(context).languageCode)
          .format(DateTime.parse(day));

  // -- WIDGETS -- //

  Widget _legend() {
    final c = context.colors;
    final t = context.t;
    Widget one(Color color, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: c.muted, fontSize: 13)),
      ],
    );
    return Wrap(
      spacing: 16,
      children: <Widget>[
        one(c.accent, t.healthWeekLegendFree),
        one(c.muted, t.healthWeekLegendWork),
        one(c.info, t.healthWeekLegendBusy),
      ],
    );
  }

  Widget _dayRow(int weekday, Json data) {
    final blocks = _days?[weekday] ?? <Json>[];
    final c = context.colors;
    final line = _workLine(blocks);
    return Semantics(
      button: true,
      label: '${_dayName(weekday)}, $line',
      child: InkWell(
        onTap: () => _editDay(weekday),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    flex: 2,
                    child: Text(
                      _dayName(weekday),
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  // Several blocks make a long line: it wraps under the day instead of overflowing
                  Flexible(
                    flex: 3,
                    child: Text(
                      line,
                      textAlign: TextAlign.end,
                      style: TextStyle(color: c.muted, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _DayBar(
                blocks: blocks,
                awakeFrom: _minutes(str(data['awakeFrom'], '06:00')),
                awakeTo: _minutes(str(data['awakeTo'], '22:00')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    final week = ref.watch(availabilityProvider);
    // Filled before the dock is built, so its button is ready as soon as the data is
    final loaded = week.value;
    if (loaded != null) _fill(loaded);
    return Scaffold(
      appBar: AppBar(title: Text(t.healthWeekTitle)),
      body: AsyncBody<Json>(
        value: week,
        onRetry: () => ref.invalidate(availabilityProvider),
        skeleton: const SkeletonPage(
          child: SkeletonRows(count: 7, kind: SkeletonKind.tile),
        ),
        data: (data) {
          _fill(data);
          final changes = asJsonList(data['changes']);
          return ListView(
            padding: pagePadding(context),
            children: <Widget>[
              Text(t.healthWeekLine, style: TextStyle(color: c.muted)),
              const SizedBox(height: 12),
              PaperCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _legend(),
                    const SizedBox(height: 8),
                    for (final w in const <int>[1, 2, 3, 4, 5, 6, 0])
                      _dayRow(w, data),
                  ],
                ),
              ),
              SectionTitle(t.healthWeekOnce),
              PaperCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final o in changes)
                      StatRow(
                        icon: Icons.event_outlined,
                        title: _shortDate(str(o['day'])),
                        line: boolOf(o['off'])
                            ? t.healthWeekOff
                            : _workLine(asJsonList(o['blocks'])),
                        trailing: TextButton(
                          onPressed: () => _change(<String, Object?>{
                            'day': o['day'],
                            'clear': true,
                          }),
                          child: Text(t.healthRemove),
                        ),
                      ),
                    OutlinedButton(
                      onPressed: _addChange,
                      child: Text(t.healthWeekAddOnce),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PaperCard(
                child: Column(
                  children: <Widget>[
                    StatRow(
                      icon: Icons.wb_sunny_outlined,
                      title: t.healthWeekAwake,
                      line: t.healthWeekRange(
                        _clock(str(data['awakeFrom'], '06:00')),
                        _clock(str(data['awakeTo'], '22:00')),
                      ),
                      trailing: PopupMenuButton<String>(
                        tooltip: t.healthWeekAwake,
                        onSelected: (f) => _pickAwake(
                          f,
                          str(data[f], f == 'awakeFrom' ? '06:00' : '22:00'),
                        ),
                        itemBuilder: (_) => <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'awakeFrom',
                            child: Text(t.healthWeekAwakeFrom),
                          ),
                          PopupMenuItem<String>(
                            value: 'awakeTo',
                            child: Text(t.healthWeekAwakeTo),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    StatRow(
                      icon: Icons.directions_bus_outlined,
                      title: t.healthWeekTravel,
                      line: t.healthWeekMinutes(
                        '${intOf(data['travelMinutes'], 30)}',
                      ),
                      onTap: () =>
                          _pickTravel(intOf(data['travelMinutes'], 30)),
                      trailing: Icon(Icons.chevron_right, color: c.muted),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomDock(
        primary: FilledButton(
          onPressed: _once.running() || _days == null ? null : _save,
          child: Text(t.healthWeekSave),
        ),
      ),
    );
  }
}

/// One weekday as a bar over the awake hours: work in the muted colour, free time in the accent. The words beside it say the same.
class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.blocks,
    required this.awakeFrom,
    required this.awakeTo,
  });

  final List<Json> blocks;
  final int awakeFrom;
  final int awakeTo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 0 is free time, 1 is work, 2 is busy
    final spans = <(int, int, int)>[];
    var at = awakeFrom;
    final taken = blocks.where((b) => str(b['kind']) != 'free').toList()
      ..sort((a, b) => str(a['start']).compareTo(str(b['start'])));
    for (final b in taken) {
      final s = _minutes(str(b['start'])).clamp(awakeFrom, awakeTo);
      final raw = _minutes(str(b['end']));
      final e = (raw <= _minutes(str(b['start'])) ? awakeTo : raw).clamp(
        awakeFrom,
        awakeTo,
      );
      if (s > at) spans.add((at, s, 0));
      if (e > s) spans.add((s, e, str(b['kind']) == 'busy' ? 2 : 1));
      at = e > at ? e : at;
    }
    if (at < awakeTo) spans.add((at, awakeTo, 0));
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 22,
        child: Row(
          children: <Widget>[
            for (final (s, e, kind) in spans)
              Expanded(
                flex: e - s,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  color: kind == 1
                      ? c.muted
                      : kind == 2
                      ? c.info
                      : c.accent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayEdit {
  const _DayEdit({required this.blocks, required this.copyToWeekdays});

  final List<Json> blocks;
  final bool copyToWeekdays;
}

class _DaySheet extends StatefulWidget {
  const _DaySheet({
    required this.title,
    required this.blocks,
    required this.showCopy,
  });

  final String title;
  final List<Json> blocks;
  final bool showCopy;

  @override
  State<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<_DaySheet> {
  // -- STATES -- //

  /// A copy of the day's blocks of every kind, so a block the sheet does not change is kept exactly as it was.
  late final List<Json> _blocks = <Json>[
    for (final b in widget.blocks) <String, Object?>{...b},
  ];
  bool _copy = false;
  String? _error;

  // -- FUNCTIONS -- //

  Future<void> _pick(Json block, bool isStart) async {
    final key = isStart ? 'start' : 'end';
    final picked = await showTimePicker(
      context: context,
      initialTime: _time(str(block[key])),
    );
    if (picked == null) return;
    setState(() {
      block[key] = _hhmm(picked);
      _error = null;
    });
  }

  /// The rule the server holds: no two blocks of one day run into each other, and a block that ends before it starts runs overnight.
  bool _overlaps() {
    final sorted = [..._blocks]
      ..sort((a, b) => str(a['start']).compareTo(str(b['start'])));
    for (var i = 1; i < sorted.length; i++) {
      final prev = sorted[i - 1];
      final start = _minutes(str(prev['start']));
      final end = _minutes(str(prev['end']));
      final prevEnd = end <= start ? 24 * 60 : end;
      if (prevEnd > _minutes(str(sorted[i]['start']))) return true;
    }
    return false;
  }

  void _add() {
    // The new block starts where the last one ends, so a second work block after a break is two taps
    final last = _blocks.isEmpty ? null : _blocks.last;
    final from = last == null ? '09:00' : str(last['end']);
    final to = _hhmm(
      TimeOfDay(hour: (_time(from).hour + 1) % 24, minute: _time(from).minute),
    );
    setState(() {
      _blocks.add(<String, Object?>{'start': from, 'end': to, 'kind': 'work'});
      _error = null;
    });
  }

  void _done() {
    final t = context.t;
    if (_blocks.any((b) => str(b['start']) == str(b['end']))) {
      setState(() => _error = t.healthWeekSameTime);
      return;
    }
    if (_overlaps()) {
      setState(() => _error = t.healthWeekOverlap);
      return;
    }
    Navigator.of(context).pop(
      _DayEdit(
        blocks: _blocks
          ..sort((a, b) => str(a['start']).compareTo(str(b['start']))),
        copyToWeekdays: _copy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.colors;
    return SafeArea(
      child: SingleChildScrollView(
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
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_blocks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(t.healthWeekFree, style: TextStyle(color: c.muted)),
              ),
            for (final b in _blocks) ...<Widget>[
              ChoiceRow<String>(
                choices: <(String, String)>[
                  ('work', t.healthWeekLegendWork),
                  ('busy', t.healthWeekLegendBusy),
                  ('free', t.healthWeekLegendFree),
                ],
                value: str(b['kind'], 'work'),
                onChanged: (v) => setState(() => b['kind'] = v),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pick(b, true),
                      child: Text(
                        '${t.healthWeekFrom} ${_time(str(b['start'])).format(context)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pick(b, false),
                      child: Text(
                        '${t.healthWeekTo} ${_time(str(b['end'])).format(context)}',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: t.healthRemove,
                    onPressed: () => setState(() {
                      _blocks.remove(b);
                      _error = null;
                    }),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: Text(t.healthWeekAddBlock),
              ),
            ),
            if (widget.showCopy)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.healthWeekCopy),
                value: _copy,
                onChanged: (v) => setState(() => _copy = v ?? false),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error ?? '', style: TextStyle(color: c.danger)),
              ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: minTap),
              child: FilledButton(onPressed: _done, child: Text(t.healthDone)),
            ),
          ],
        ),
      ),
    );
  }
}
