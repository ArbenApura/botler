// THE AGENDA: TASKS, EVENTS, ROUTINES AND REMINDERS IN FOUR QUIET TABS. EVERYTHING HERE CAN ALSO BE SAID TO BOTLER IN CHAT.
// Events show up in Google Calendar when sync is on, and events that came from Google are marked, because their words may have been written by someone else.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../../core/json.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
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
      final now = DateTime.now();
      final f = DateFormat('yyyy-MM-dd');
      return ref.watch(apiProvider).verbList('event_list', <String, Object?>{
        'from': f.format(now),
        'to': f.format(now.add(const Duration(days: 14))),
      });
    });

const List<String> _dayNames = <String>[
  'Sun',
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
];

// -- TYPES -- //

class AgendaScreen extends ConsumerWidget {
  const AgendaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Agenda'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Tab>[
              Tab(text: 'Tasks'),
              Tab(text: 'Events'),
              Tab(text: 'Routines'),
              Tab(text: 'Reminders'),
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

/// The date and time pickers in one: a moment in the person's own time zone.
Future<DateTime?> pickMoment(BuildContext context, {DateTime? initial}) async {
  final start = initial ?? DateTime.now().add(const Duration(hours: 1));
  final d = await showDatePicker(
    context: context,
    initialDate: start,
    firstDate: DateTime.now().subtract(const Duration(days: 1)),
    lastDate: DateTime(2100),
  );
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(start),
  );
  if (t == null) return null;
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}

String _stamp(DateTime d) =>
    DateFormat('EEE, MMM d · h:mm a').format(d.toLocal());

// -- TASKS -- //

class _TasksTab extends ConsumerWidget {
  const _TasksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        AsyncBody<List<Json>>(
          value: ref.watch(_tasks),
          onRetry: () => ref.invalidate(_tasks),
          data: (list) => Column(
            children: <Widget>[
              if (list.isEmpty)
                const Note(
                  'Nothing open. Add something you want to remember to do.',
                ),
              for (final t in list)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: false,
                  title: Text(str(t['title'])),
                  subtitle: t['dueAt'] == null
                      ? null
                      : Text(
                          'Due ${_stamp(dateOf(t['dueAt']) ?? DateTime.now())}',
                          style: TextStyle(color: c.muted),
                        ),
                  onChanged: (_) async {
                    try {
                      await ref.read(apiProvider).verb(
                        'task_update',
                        <String, Object?>{
                          'taskId': str(t['id']),
                          'status': 'done',
                        },
                      );
                      ref
                        ..invalidate(_tasks)
                        ..invalidate(syncProvider);
                    } catch (e) {
                      if (context.mounted) say(context, errorWords(e));
                    }
                  },
                ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _add(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Add a task'),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    DateTime? due;
    final done = await showFormSheet<bool>(
      context,
      title: 'Add a task',
      builder: (sheet, close) => StatefulBuilder(
        builder: (_, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Field(controller: title, label: 'What needs doing?'),
            OutlinedButton(
              onPressed: () async {
                final m = await pickMoment(sheet, initial: due);
                if (m != null) setState(() => due = m);
              },
              child: Text(
                due == null
                    ? 'Set a deadline (optional)'
                    : 'Due ${_stamp(due!)}',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty)
                  return say(sheet, 'Say what the task is.');
                try {
                  await ref.read(apiProvider).verb(
                    'task_create',
                    <String, Object?>{
                      'title': title.text.trim(),
                      if (due != null) 'dueAt': due!.toUtc().toIso8601String(),
                    },
                  );
                  close(true);
                } catch (e) {
                  if (sheet.mounted) say(sheet, errorWords(e));
                }
              },
              child: const Text('Add the task'),
            ),
          ],
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

class _EventsTab extends ConsumerWidget {
  const _EventsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        AsyncBody<List<Json>>(
          value: ref.watch(_events),
          onRetry: () => ref.invalidate(_events),
          data: (list) => Column(
            children: <Widget>[
              if (list.isEmpty) const Note('No events in the next two weeks.'),
              for (final e in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(str(e['title'])),
                  subtitle: Text(
                    '${boolOf(e['allDay']) ? DateFormat('EEE, MMM d').format(dateOf(e['startsAt'])?.toLocal() ?? DateTime.now()) : _stamp(dateOf(e['startsAt']) ?? DateTime.now())}${boolOf(e['untrusted']) ? ' · from Google Calendar' : ''}',
                    style: TextStyle(color: c.muted),
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      try {
                        await ref.read(apiProvider).verb(
                          'event_delete',
                          <String, Object?>{'eventId': str(e['id'])},
                        );
                        ref
                          ..invalidate(_events)
                          ..invalidate(syncProvider);
                      } catch (err) {
                        if (context.mounted) say(context, errorWords(err));
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _add(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Add an event'),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    DateTime? when;
    final done = await showFormSheet<bool>(
      context,
      title: 'Add an event',
      builder: (sheet, close) => StatefulBuilder(
        builder: (_, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Field(controller: title, label: 'What is it?'),
            OutlinedButton(
              onPressed: () async {
                final m = await pickMoment(sheet, initial: when);
                if (m != null) setState(() => when = m);
              },
              child: Text(
                when == null ? 'Pick the day and time' : _stamp(when!),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty || when == null)
                  return say(sheet, 'Give it a name and a time.');
                try {
                  await ref.read(apiProvider).verb(
                    'event_create',
                    <String, Object?>{
                      'title': title.text.trim(),
                      'startsAt': when!.toUtc().toIso8601String(),
                    },
                  );
                  close(true);
                } catch (e) {
                  if (sheet.mounted) say(sheet, errorWords(e));
                }
              },
              child: const Text('Add the event'),
            ),
          ],
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

class _RoutinesTab extends ConsumerWidget {
  const _RoutinesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        AsyncBody<List<Json>>(
          value: ref.watch(_routines),
          onRetry: () => ref.invalidate(_routines),
          data: (list) => Column(
            children: <Widget>[
              if (list.isEmpty)
                const Note(
                  'No routines. Try “gym every Monday, Wednesday and Friday at 6”.',
                ),
              for (final r in list)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(str(r['title'])),
                  subtitle: Text(
                    _describe(asJson(r['recurrence'])),
                    style: TextStyle(color: c.muted),
                  ),
                  value: boolOf(r['active']),
                  onChanged: (on) async {
                    try {
                      await ref.read(apiProvider).verb(
                        'routine_update',
                        <String, Object?>{
                          'routineId': str(r['id']),
                          'active': on,
                        },
                      );
                      ref
                        ..invalidate(_routines)
                        ..invalidate(syncProvider);
                    } catch (e) {
                      if (context.mounted) say(context, errorWords(e));
                    }
                  },
                ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _add(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Add a routine'),
        ),
      ],
    );
  }

  static String _describe(Json r) {
    final time = str(r['time']);
    return switch (str(r['freq'])) {
      'daily' => 'Every day at $time',
      'weekly' =>
        '${asList(r['days']).whereType<num>().map((d) => _dayNames[d.toInt() % 7]).join(', ')} at $time',
      'monthly' => 'Every month on the ${r['day']}th at $time',
      'every_n_days' => 'Every ${r['n']} days at $time',
      _ => time,
    };
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    var freq = 'daily';
    final days = <int>{1, 3, 5};
    var time = const TimeOfDay(hour: 7, minute: 0);
    final done = await showFormSheet<bool>(
      context,
      title: 'Add a routine',
      builder: (sheet, close) => StatefulBuilder(
        builder: (_, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Field(
              controller: title,
              label: 'What is it?',
              hint: 'Take vitamins',
            ),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final (k, label) in <(String, String)>[
                  ('daily', 'Every day'),
                  ('weekly', 'On some days'),
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
                      label: Text(_dayNames[d]),
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
              child: Text('At ${time.format(sheet)}'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty ||
                    (freq == 'weekly' && days.isEmpty))
                  return say(
                    sheet,
                    'Give it a name, and pick at least one day.',
                  );
                final hhmm =
                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                try {
                  await ref.read(apiProvider).verb(
                    'routine_create',
                    <String, Object?>{
                      'title': title.text.trim(),
                      'recurrence': freq == 'daily'
                          ? <String, Object?>{'freq': 'daily', 'time': hhmm}
                          : <String, Object?>{
                              'freq': 'weekly',
                              'days': days.toList()..sort(),
                              'time': hhmm,
                            },
                    },
                  );
                  close(true);
                } catch (e) {
                  if (sheet.mounted) say(sheet, errorWords(e));
                }
              },
              child: const Text('Add the routine'),
            ),
          ],
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

class _RemindersTab extends ConsumerWidget {
  const _RemindersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        AsyncBody<List<Json>>(
          value: ref.watch(_reminders),
          onRetry: () => ref.invalidate(_reminders),
          data: (list) => Column(
            children: <Widget>[
              if (list.isEmpty) const Note('No reminders waiting.'),
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
                    _stamp(dateOf(r['remindAt']) ?? DateTime.now()),
                    style: TextStyle(color: c.muted),
                  ),
                  trailing: IconButton(
                    tooltip: 'Cancel',
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      try {
                        await ref.read(apiProvider).verb(
                          'reminder_cancel',
                          <String, Object?>{'reminderId': str(r['id'])},
                        );
                        ref
                          ..invalidate(_reminders)
                          ..invalidate(syncProvider);
                      } catch (e) {
                        if (context.mounted) say(context, errorWords(e));
                      }
                    },
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
                  _add(context, ref, 'reminder_create', 'Remind me'),
              child: const Text('Remind me'),
            ),
            OutlinedButton(
              onPressed: () => _add(context, ref, 'alarm_create', 'Alarm'),
              child: const Text('Set an alarm'),
            ),
            OutlinedButton(
              onPressed: () => _timer(context, ref),
              child: const Text('Start a timer'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    String verb,
    String heading,
  ) async {
    final title = TextEditingController();
    DateTime? when;
    final done = await showFormSheet<bool>(
      context,
      title: heading,
      builder: (sheet, close) => StatefulBuilder(
        builder: (_, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Field(controller: title, label: 'What for?'),
            OutlinedButton(
              onPressed: () async {
                final m = await pickMoment(sheet, initial: when);
                if (m != null) setState(() => when = m);
              },
              child: Text(
                when == null ? 'Pick the day and time' : _stamp(when!),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty || when == null)
                  return say(sheet, 'Say what for, and when.');
                try {
                  await ref.read(apiProvider).verb(verb, <String, Object?>{
                    'title': title.text.trim(),
                    'at': when!.toUtc().toIso8601String(),
                  });
                  close(true);
                } catch (e) {
                  if (sheet.mounted) say(sheet, errorWords(e));
                }
              },
              child: const Text('Save'),
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

  Future<void> _timer(BuildContext context, WidgetRef ref) async {
    final minutes = TextEditingController(text: '10');
    final done = await showFormSheet<bool>(
      context,
      title: 'Start a timer',
      builder: (sheet, close) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Field(
            controller: minutes,
            label: 'How many minutes?',
            keyboard: TextInputType.number,
          ),
          FilledButton(
            onPressed: () async {
              final m = int.tryParse(minutes.text.trim());
              if (m == null || m < 1 || m > 1440)
                return say(sheet, 'Pick between 1 and 1440 minutes.');
              try {
                await ref.read(apiProvider).verb(
                  'timer_create',
                  <String, Object?>{'minutes': m},
                );
                close(true);
              } catch (e) {
                if (sheet.mounted) say(sheet, errorWords(e));
              }
            },
            child: const Text('Start'),
          ),
        ],
      ),
    );
    if (done == true) {
      ref
        ..invalidate(_reminders)
        ..invalidate(syncProvider);
    }
  }
}
