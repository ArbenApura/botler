// WHICH NOTIFICATIONS THE PHONE SCHEDULES, SHOWS AT ONCE OR LEAVES OUT, FROM THE SERVER'S LIST.

// -- DEP-MODULES -- //
import 'package:flutter_test/flutter_test.dart';

// -- MODULES -- //
import 'package:botler/core/reminders.dart';

// -- CONSTANTS -- //

final DateTime _now = DateTime.utc(2026, 10, 23, 0, 30);

Map<String, Object?> _reminder(
  String key,
  DateTime at, {
  String kind = 'custom',
}) => <String, Object?>{
  'key': key,
  'kind': kind,
  'title': 'Call mum',
  'at': at.toIso8601String(),
};

// -- TESTS -- //

void main() {
  group('planNotices', () {
    test('a reminder in the future is scheduled at its time', () {
      final at = _now.add(const Duration(minutes: 3));
      final plan = planNotices(
        <Map<String, Object?>>[_reminder('a', at)],
        0,
        _now,
        <String>{},
      );
      expect(plan, hasLength(1));
      expect(plan.single.showNow, isFalse);
      expect(plan.single.fire, at.toLocal());
    });

    test('a reminder a minute late is shown at once, not dropped', () {
      final at = _now.subtract(const Duration(minutes: 1));
      final plan = planNotices(
        <Map<String, Object?>>[_reminder('a', at)],
        0,
        _now,
        <String>{},
      );
      expect(plan.single.showNow, isTrue);
    });

    test('a lead time longer than the wait shows it at once', () {
      // Due in 3 minutes with a 10 minute lead: its ring time is already past
      final at = _now.add(const Duration(minutes: 3));
      final plan = planNotices(
        <Map<String, Object?>>[_reminder('a', at)],
        10,
        _now,
        <String>{},
      );
      expect(plan.single.showNow, isTrue);
    });

    test('a reminder shown before is not shown again', () {
      final at = _now.subtract(const Duration(minutes: 1));
      final plan = planNotices(
        <Map<String, Object?>>[_reminder('a', at)],
        0,
        _now,
        <String>{shownKeyOf('a', at.toLocal())},
      );
      expect(plan, isEmpty);
    });

    test('one past the grace is left out', () {
      final at = _now.subtract(lateGrace + const Duration(minutes: 1));
      final plan = planNotices(
        <Map<String, Object?>>[_reminder('a', at)],
        0,
        _now,
        <String>{},
      );
      expect(plan, isEmpty);
    });

    test('alarms, timers and unreadable times are not notifications', () {
      final at = _now.add(const Duration(minutes: 3));
      final plan = planNotices(
        <Map<String, Object?>>[
          _reminder('a', at, kind: 'alarm'),
          _reminder('t', at, kind: 'timer'),
          <String, Object?>{'key': 'x', 'kind': 'custom', 'at': 'not a time'},
        ],
        0,
        _now,
        <String>{},
      );
      expect(plan, isEmpty);
    });
  });

  group('planAlarms', () {
    test('an alarm and a timer ring at their own time, with no lead', () {
      final at = _now.add(const Duration(hours: 30));
      final plan = planAlarms(
        <Map<String, Object?>>[
          _reminder('a', at, kind: 'alarm'),
          _reminder('t', at, kind: 'timer'),
        ],
        _now,
        <String>{},
      );
      expect(plan, hasLength(2));
      expect(plan.every((n) => n.alarm && !n.showNow), isTrue);
      expect(plan.first.fire, at.toLocal());
    });

    test('an alarm a minute late rings at once, once', () {
      final at = _now.subtract(const Duration(minutes: 1));
      final first = planAlarms(
        <Map<String, Object?>>[_reminder('a', at, kind: 'alarm')],
        _now,
        <String>{},
      );
      expect(first.single.showNow, isTrue);
      final again = planAlarms(
        <Map<String, Object?>>[_reminder('a', at, kind: 'alarm')],
        _now,
        <String>{shownKeyOf('a', at.toLocal())},
      );
      expect(again, isEmpty);
    });

    test(
      'one past the grace, an ordinary reminder and a bad time are left out',
      () {
        final late = _now.subtract(lateGrace + const Duration(minutes: 1));
        final plan = planAlarms(
          <Map<String, Object?>>[
            _reminder('a', late, kind: 'alarm'),
            _reminder('c', _now.add(const Duration(minutes: 3))),
            <String, Object?>{'key': 'x', 'kind': 'alarm', 'at': 'not a time'},
          ],
          _now,
          <String>{},
        );
        expect(plan, isEmpty);
      },
    );
  });

  group('changesReminders', () {
    test('a reply that made a reminder asks the phone to sync', () {
      expect(changesReminders(<Object?>['reminder_create']), isTrue);
      expect(
        changesReminders(<Object?>['balance_get', 'timer_create']),
        isTrue,
      );
    });

    test('a reply that only read things does not', () {
      expect(changesReminders(<Object?>['balance_get']), isFalse);
      expect(changesReminders(null), isFalse);
    });
  });
}
