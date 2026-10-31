// THE AGENDA: TASKS, EVENTS, ROUTINES AND REMINDERS IN FOUR QUIET TABS. EVERYTHING HERE CAN ALSO BE SAID TO BOTLER IN CHAT.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../core/manila.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../ui/manila_clock.dart';
import '../../ui/ui.dart';

// -- CONSTANTS -- //

final FutureProvider<List<Json>> _tasks =
    FutureProvider.autoDispose<List<Json>>(
      (ref) => ref.watch(apiProvider).verbList('task_list'),
    );
final FutureProvider<List<Json>> _routines =
    FutureProvider.autoDispose<List<Json>>(
      (ref) => ref.watch(apiProvider).verbList('routine_list'),
    );
final FutureProvider<List<Json>> _reminders =
    FutureProvider.autoDispose<List<Json>>(
      (ref) => ref.watch(apiProvider).verbList('reminder_list'),
    );
final FutureProvider<List<Json>> _events =
    FutureProvider.autoDispose<List<Json>>((ref) {
      // Manila calendar dates, whatever zone the phone is in
      final today = manilaToday();
      return ref.watch(apiProvider).verbList('event_list', <String, Object?>{
        'from': today,
        'to': addDaysTo(today, 14),
      });
    });

/// Short weekday name for 0 = Sunday ... 6 = Saturday, in the app's language (1 January 2023 was a Sunday).
String _dayName(BuildContext context, int d) => DateFormat(
  'EEE',
  Localizations.localeOf(context).toString(),
).format(DateTime(2023, 1, 1 + d));

// -- TYPES -- //

class AgendaScreen extends ConsumerWidget {
  const AgendaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.t.agendaTitle),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Tab>[
              Tab(text: context.t.agendaTabTasks),
              Tab(text: context.t.agendaTabEvents),
              Tab(text: context.t.agendaTabRoutines),
              Tab(text: context.t.agendaTabReminders),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            _TasksTab(),
            _EventsTab(),
            _RoutinesTab(),
            _RemindersTab(),
          ],
        ),
      ),
    );
  }
}

/// The date and time pickers in one: a Manila wall reading (send it with [manilaInstant]).
Future<DateTime?> pickMoment(BuildContext context, {DateTime? initial}) async {
  final start = initial ?? manilaNow().add(const Duration(hours: 1));
  final d = await showDatePicker(
    context: context,
    initialDate: DateTime(start.year, start.month, start.day),
    firstDate: addCalendarDays(manilaTodayPicker(), -1),
    lastDate: DateTime(2100),
  );
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: start.hour, minute: start.minute),
  );
  if (t == null) return null;
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}

/// A Manila wall reading as text, in the app's language.
String _stampWall(BuildContext context, DateTime wall) => DateFormat(
  'EEE, MMM d · h:mm a',
  Localizations.localeOf(context).toString(),
).format(wall);

/// A real moment as Manila wall time.
String _stamp(BuildContext context, DateTime instant) =>
    _stampWall(context, manilaWall(instant));

/// The moment a row's timestamp field holds; a missing one reads as now.
DateTime _moment(Object? raw) => dateOf(raw) ?? DateTime.now().toUtc();

// -- TASKS -- //

class _TasksTab extends ConsumerStatefulWidget {
  const _TasksTab();

  @override
  ConsumerState<_TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends ConsumerState<_TasksTab> {
  // -- STATES -- //
  late final Once _once = Once(() {
    if (mounted) setState(() {});
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: pagePadding(context),
      children: <Widget>[
        AsyncBody<List<Json>>(
          value: ref.watch(_tasks),
          skeleton: const SkeletonRows(),
          onRetry: () => ref.invalidate(_tasks),
          data: (list) => Column(
            children: <Widget>[
              if (list.isEmpty) Note(context.t.agendaTasksEmpty),
              for (final t in list)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: false,
                  title: Text(str(t['title'])),
                  subtitle: t['dueAt'] == null
                      ? null
                      : Text(
                          context.t.agendaDue(
                            _stamp(context, _moment(t['dueAt'])),
                          ),
                          style: TextStyle(color: c.muted),
                        ),
                  onChanged: _once.running('done:${str(t['id'])}')
                      ? null
                      : (_) => _finish(str(t['id'])),
                ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _add(context),
          icon: const Icon(Icons.add),
          label: Text(context.t.agendaAddTask),
        ),
      ],
    );
  }

  Future<void> _finish(String id) async {
    try {
      await _once.run((key) async {
        await ref.read(apiProvider).verb('task_update', <String, Object?>{
          'taskId': id,
          'status': 'done',
        }, key);
        ref
          ..invalidate(_tasks)
          ..invalidate(syncProvider);
      }, intent: 'done:$id');
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
    }
  }

  Future<void> _add(BuildContext context) async {
    DateTime? due;
    final done = await showFormSheet<bool>(
      context,
      title: context.t.agendaAddTask,
      builder: (sheet, close) => SheetScope(
        builder: (_, s) => StatefulBuilder(
          builder: (_, setState) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Field(controller: s.c[0], label: sheet.t.agendaTaskWhat),
              OutlinedButton(
                onPressed: () async {
                  final m = await pickMoment(sheet, initial: due);
                  if (m != null) setState(() => due = m);
                },
                child: Text(
                  due == null
                      ? sheet.t.agendaTaskDeadline
                      : sheet.t.agendaDue(
                          _stampWall(sheet, due ?? DateTime(0)),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: s.once.running()
                    ? null
                    : () async {
                        final title = s.c[0].text.trim();
                        if (title.isEmpty) {
                          return say(sheet, sheet.t.agendaTaskNeedsTitle);
                        }
                        final at = due;
                        try {
                          if (!await s.once.ok((key) async {
                            await ref.read(apiProvider).verb(
                              'task_create',
                              <String, Object?>{
                                'title': title,
                                if (at != null)
                                  'dueAt': manilaInstant(at).toIso8601String(),
                              },
                              key,
                            );
                          }))
                            return;
                          close(true);
                        } catch (e) {
                          if (sheet.mounted) say(sheet, errorWords(e, context));
                        }
                      },
                child: Text(sheet.t.agendaTaskSubmit),
              ),
            ],
          ),
        ),
      ),
    );
    if (done == true) {
      ref
        ..invalidate(_tasks)
        ..invalidate(syncProvider);
    }
  }
}

// -- EVENTS -- //

class _EventsTab extends ConsumerStatefulWidget {
  const _EventsTab();

  @override
  ConsumerState<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends ConsumerState<_EventsTab> {
  // -- STATES -- //
  late final Once _once = Once(() {
    if (mounted) setState(() {});
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: pagePadding(context),
      children: <Widget>[
        AsyncBody<List<Json>>(
          value: ref.watch(_events),
          skeleton: const SkeletonRows(),
          onRetry: () => ref.invalidate(_events),
          data: (list) => Column(
            children: <Widget>[
              if (list.isEmpty) Note(context.t.agendaEventsEmpty),
              for (final e in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(str(e['title'])),
                  subtitle: Text(
                    boolOf(e['allDay'])
                        ? DateFormat(
                            'EEE, MMM d',
                            Localizations.localeOf(context).toString(),
                          ).format(manilaWall(_moment(e['startsAt'])))
                        : _stamp(context, _moment(e['startsAt'])),
                    style: TextStyle(color: c.muted),
                  ),
                  trailing: IconButton(
                    tooltip: context.t.agendaRemove,
                    icon: const Icon(Icons.close),
                    onPressed: _once.running('del:${str(e['id'])}')
                        ? null
                        : () => _remove(str(e['id'])),
                  ),
                ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _add(context),
          icon: const Icon(Icons.add),
          label: Text(context.t.agendaAddEvent),
        ),
      ],
    );
  }

  Future<void> _remove(String id) async {
    try {
      await _once.run((key) async {
        await ref.read(apiProvider).verb('event_delete', <String, Object?>{
          'eventId': id,
        }, key);
        ref
          ..invalidate(_events)
          ..invalidate(syncProvider);
      }, intent: 'del:$id');
    } catch (err) {
      if (mounted) say(context, errorWords(err));
    }
  }

  Future<void> _add(BuildContext context) async {
    DateTime? when;
    final done = await showFormSheet<bool>(
      context,
      title: context.t.agendaAddEvent,
      builder: (sheet, close) => SheetScope(
        builder: (_, s) => StatefulBuilder(
          builder: (_, setState) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Field(controller: s.c[0], label: sheet.t.agendaEventWhat),
              OutlinedButton(
                onPressed: () async {
                  final m = await pickMoment(sheet, initial: when);
                  if (m != null) setState(() => when = m);
                },
                child: Text(
                  when == null
                      ? sheet.t.agendaPickMoment
                      : _stampWall(sheet, when ?? DateTime(0)),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: s.once.running()
                    ? null
                    : () async {
                        final title = s.c[0].text.trim();
                        final at = when;
                        if (title.isEmpty || at == null) {
                          return say(sheet, sheet.t.agendaEventNeeds);
                        }
                        try {
                          if (!await s.once.ok((key) async {
                            await ref.read(apiProvider).verb(
                              'event_create',
                              <String, Object?>{
                                'title': title,
                                'startsAt': manilaInstant(at).toIso8601String(),
                              },
                              key,
                            );
                          }))
                            return;
                          close(true);
                        } catch (e) {
                          if (sheet.mounted) say(sheet, errorWords(e, context));
                        }
                      },
                child: Text(sheet.t.agendaEventSubmit),
              ),
            ],
          ),
        ),
      ),
    );
    if (done == true) {
      ref
        ..invalidate(_events)
        ..invalidate(syncProvider);
    }
  }
}

// -- ROUTINES -- //

class _RoutinesTab extends ConsumerStatefulWidget {
  const _RoutinesTab();

  @override
  ConsumerState<_RoutinesTab> createState() => _RoutinesTabState();
}

class _RoutinesTabState extends ConsumerState<_RoutinesTab> {
  // -- STATES -- //
  late final Once _once = Once(() {
    if (mounted) setState(() {});
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: pagePadding(context),
      children: <Widget>[
        AsyncBody<List<Json>>(
          value: ref.watch(_routines),
          skeleton: const SkeletonRows(),
          onRetry: () => ref.invalidate(_routines),
          data: (list) => Column(
            children: <Widget>[
              if (list.isEmpty) Note(context.t.agendaRoutinesEmpty),
              for (final r in list)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(str(r['title'])),
                  subtitle: Text(
                    _describe(context, asJson(r['recurrence'])),
                    style: TextStyle(color: c.muted),
                  ),
                  value: boolOf(r['active']),
                  onChanged: _once.running('toggle:${str(r['id'])}')
                      ? null
                      : (on) => _toggle(str(r['id']), on),
                ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _add(context),
          icon: const Icon(Icons.add),
          label: Text(context.t.agendaAddRoutine),
        ),
      ],
    );
  }

  Future<void> _toggle(String id, bool on) async {
    try {
      await _once.run((key) async {
        await ref.read(apiProvider).verb('routine_update', <String, Object?>{
          'routineId': id,
          'active': on,
        }, key);
        ref
          ..invalidate(_routines)
          ..invalidate(syncProvider);
      }, intent: 'toggle:$id');
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
    }
  }

  static String _describe(BuildContext context, Json r) {
    final time = str(r['time']);
    return switch (str(r['freq'])) {
      'daily' => context.t.agendaEveryDayAt(time),
      'weekly' => context.t.agendaDaysAt(
        asList(r['days'])
            .whereType<num>()
            .map((d) => _dayName(context, d.toInt() % 7))
            .join(', '),
        time,
      ),
      'monthly' => context.t.agendaMonthlyAt('${r['day']}', time),
      'every_n_days' => context.t.agendaEveryNDaysAt('${r['n']}', time),
      _ => time,
    };
  }

  Future<void> _add(BuildContext context) async {
    var freq = 'daily';
    final days = <int>{1, 3, 5};
    var time = const TimeOfDay(hour: 7, minute: 0);
    final done = await showFormSheet<bool>(
      context,
      title: context.t.agendaAddRoutine,
      builder: (sheet, close) => SheetScope(
        builder: (_, s) => StatefulBuilder(
          builder: (_, setState) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Field(
                controller: s.c[0],
                label: sheet.t.agendaEventWhat,
                hint: sheet.t.agendaRoutineHint,
              ),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final (k, label) in <(String, String)>[
                    ('daily', sheet.t.agendaFreqDaily),
                    ('weekly', sheet.t.agendaFreqWeekly),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: freq == k,
                      onSelected: (_) => setState(() => freq = k),
                    ),
                ],
              ),
              if (freq == 'weekly')
                Wrap(
                  spacing: 6,
                  children: <Widget>[
                    for (var d = 0; d < 7; d++)
                      FilterChip(
                        label: Text(_dayName(sheet, d)),
                        selected: days.contains(d),
                        onSelected: (on) =>
                            setState(() => on ? days.add(d) : days.remove(d)),
                      ),
                  ],
                ),
              OutlinedButton(
                onPressed: () async {
                  final t = await showTimePicker(
                    context: sheet,
                    initialTime: time,
                  );
                  if (t != null) setState(() => time = t);
                },
                child: Text(sheet.t.agendaAtTime(time.format(sheet))),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: s.once.running()
                    ? null
                    : () async {
                        final title = s.c[0].text.trim();
                        if (title.isEmpty ||
                            (freq == 'weekly' && days.isEmpty)) {
                          return say(sheet, sheet.t.agendaRoutineNeeds);
                        }
                        final hhmm =
                            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                        try {
                          if (!await s.once.ok((key) async {
                            await ref.read(apiProvider).verb(
                              'routine_create',
                              <String, Object?>{
                                'title': title,
                                'recurrence': freq == 'daily'
                                    ? <String, Object?>{
                                        'freq': 'daily',
                                        'time': hhmm,
                                      }
                                    : <String, Object?>{
                                        'freq': 'weekly',
                                        'days': days.toList()..sort(),
                                        'time': hhmm,
                                      },
                              },
                              key,
                            );
                          }))
                            return;
                          close(true);
                        } catch (e) {
                          if (sheet.mounted) say(sheet, errorWords(e, context));
                        }
                      },
                child: Text(sheet.t.agendaRoutineSubmit),
              ),
            ],
          ),
        ),
      ),
    );
    if (done == true) {
      ref
        ..invalidate(_routines)
        ..invalidate(syncProvider);
    }
  }
}

// -- REMINDERS -- //

class _RemindersTab extends ConsumerStatefulWidget {
  const _RemindersTab();

  @override
  ConsumerState<_RemindersTab> createState() => _RemindersTabState();
}

class _RemindersTabState extends ConsumerState<_RemindersTab> {
  // -- STATES -- //
  late final Once _once = Once(() {
    if (mounted) setState(() {});
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: pagePadding(context),
      children: <Widget>[
        AsyncBody<List<Json>>(
          value: ref.watch(_reminders),
          skeleton: const SkeletonRows(),
          onRetry: () => ref.invalidate(_reminders),
          data: (list) => Column(
            children: <Widget>[
              if (list.isEmpty) Note(context.t.agendaRemindersEmpty),
              for (final r in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(switch (str(r['kind'])) {
                    'alarm' => Icons.alarm,
                    'timer' => Icons.timer_outlined,
                    _ => Icons.notifications_none,
                  }, color: c.muted),
                  title: Text(str(r['title'])),
                  subtitle: Text(
                    _stamp(context, _moment(r['remindAt'])),
                    style: TextStyle(color: c.muted),
                  ),
                  trailing: IconButton(
                    tooltip: context.t.cancel,
                    icon: const Icon(Icons.close),
                    onPressed: _once.running('cancel:${str(r['id'])}')
                        ? null
                        : () => _cancel(str(r['id'])),
                  ),
                ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          children: <Widget>[
            OutlinedButton(
              onPressed: () =>
                  _add(context, 'reminder_create', context.t.agendaRemindMe),
              child: Text(context.t.agendaRemindMe),
            ),
            OutlinedButton(
              onPressed: () =>
                  _add(context, 'alarm_create', context.t.agendaAlarm),
              child: Text(context.t.agendaSetAlarm),
            ),
            OutlinedButton(
              onPressed: () => _timer(context),
              child: Text(context.t.agendaStartTimer),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _cancel(String id) async {
    try {
      await _once.run((key) async {
        await ref.read(apiProvider).verb('reminder_cancel', <String, Object?>{
          'reminderId': id,
        }, key);
        ref
          ..invalidate(_reminders)
          ..invalidate(syncProvider);
      }, intent: 'cancel:$id');
    } catch (e) {
      if (mounted) say(context, errorWords(e, context));
    }
  }

  Future<void> _add(BuildContext context, String verb, String heading) async {
    DateTime? when;
    final done = await showFormSheet<bool>(
      context,
      title: heading,
      builder: (sheet, close) => SheetScope(
        builder: (_, s) => StatefulBuilder(
          builder: (_, setState) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Field(controller: s.c[0], label: sheet.t.agendaReminderWhat),
              OutlinedButton(
                onPressed: () async {
                  final m = await pickMoment(sheet, initial: when);
                  if (m != null) setState(() => when = m);
                },
                child: Text(
                  when == null
                      ? sheet.t.agendaPickMoment
                      : _stampWall(sheet, when ?? DateTime(0)),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: s.once.running()
                    ? null
                    : () async {
                        final title = s.c[0].text.trim();
                        final at = when;
                        if (title.isEmpty || at == null) {
                          return say(sheet, sheet.t.agendaReminderNeeds);
                        }
                        try {
                          if (!await s.once.ok((key) async {
                            await ref.read(apiProvider).verb(
                              verb,
                              <String, Object?>{
                                'title': title,
                                'at': manilaInstant(at).toIso8601String(),
                              },
                              key,
                            );
                          }))
                            return;
                          close(true);
                        } catch (e) {
                          if (sheet.mounted) say(sheet, errorWords(e, context));
                        }
                      },
                child: Text(sheet.t.save),
              ),
            ],
          ),
        ),
      ),
    );
    if (done == true) {
      ref
        ..invalidate(_reminders)
        ..invalidate(syncProvider);
    }
  }

  Future<void> _timer(BuildContext context) async {
    final done = await showFormSheet<bool>(
      context,
      title: context.t.agendaStartTimer,
      builder: (sheet, close) => SheetScope(
        texts: const <String>['10'],
        builder: (_, s) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Field(
              controller: s.c[0],
              label: sheet.t.agendaTimerMinutes,
              keyboard: TextInputType.number,
            ),
            FilledButton(
              onPressed: s.once.running()
                  ? null
                  : () async {
                      final m = int.tryParse(s.c[0].text.trim());
                      if (m == null || m < 1 || m > 1440) {
                        return say(sheet, sheet.t.agendaTimerRange);
                      }
                      try {
                        if (!await s.once.ok((key) async {
                          await ref.read(apiProvider).verb(
                            'timer_create',
                            <String, Object?>{'minutes': m},
                            key,
                          );
                        }))
                          return;
                        close(true);
                      } catch (e) {
                        if (sheet.mounted) say(sheet, errorWords(e, context));
                      }
                    },
              child: Text(sheet.t.agendaTimerStart),
            ),
          ],
        ),
      ),
    );
    if (done == true) {
      ref
        ..invalidate(_reminders)
        ..invalidate(syncProvider);
    }
  }
}
