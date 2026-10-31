// "TODAY" IN THE SCREENS IS A MANILA CALENDAR DATE. A SCREEN THAT READS THE PHONE'S OWN CLOCK FOR A DAY SHOWS THE WRONG ONE FOR SOMEONE WHOSE PHONE IS
// SET TO ANOTHER ZONE (OR FOR EVERYONE FOR A FEW HOURS EACH DAY). DateTime.now() IN lib/features IS FOR A MOMENT ONLY (AN ELAPSED TIME, A FALLBACK
// FOR A MISSING TIMESTAMP, AN ANIMATION): EVERY SUCH USE IS LISTED HERE WITH ITS REASON.

// -- DEP-MODULES -- //
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// -- MODULES -- //
import 'package:botler/core/manila.dart';
import 'package:botler/ui/manila_clock.dart';

// -- CONSTANTS -- //

/// File -> how many `DateTime.now()` it may hold, and why.
const Map<String, (int, String)> allowedNow = <String, (int, String)>{
  'features/chat/agent_text.dart': (
    2,
    'the pause between two reads of a streaming answer',
  ),
  'features/agenda/agenda_screen.dart': (
    1,
    'a missing timestamp reads as a moment, shown in Manila',
  ),
  'features/chat/chat_state.dart': (
    2,
    'how long the model thought, in seconds',
  ),
  'features/money/account_detail_screen.dart': (
    2,
    'a missing timestamp reads as a moment, shown in Manila',
  ),
  'features/notebooks/activity_feed.dart': (
    1,
    'minutes and hours ago, an elapsed time',
  ),
  'features/notebooks/deleted_pages.dart': (
    1,
    'days left of 30, an elapsed time',
  ),
  'features/settings/settings_screen.dart': (
    1,
    'a missing timestamp reads as a moment, shown in Manila',
  ),
  'features/simulate/simulate_data.dart': (
    2,
    'the time a what-if was saved, and a missing one',
  ),
  'features/calendar/calendar_parts.dart': (
    1,
    'a missing timestamp reads as a moment, shown in Manila',
  ),
  'features/auth/lock_gate.dart': (
    99,
    'owned by the sign-in work: lock timing',
  ),
  'features/update/update_gate.dart': (99, 'owned by the update work: timing'),
  'features/chat/chat_screen.dart': (
    99,
    'owned by the chat work: ids and animation',
  ),
  'features/settings/reset_screen.dart': (99, 'owned by the reset work'),
};

// -- FUNCTIONS -- //

void main() {
  test('screens read the day from the Manila clock, not the phone', () {
    final over = <String>[];
    for (final f in Directory('lib/features').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/').replaceFirst('lib/', '');
      final n = RegExp(r'DateTime\.now\(\)')
          .allMatches(f.readAsStringSync())
          .length;
      final allowed = allowedNow[path]?.$1 ?? 0;
      if (n > allowed) over.add('$path: $n uses, $allowed allowed');
    }
    expect(
      over,
      isEmpty,
      reason: 'Use manilaToday() / manilaTodayPicker() / manilaNow() (core/manila.dart, ui/manila_clock.dart) for a day. A use of DateTime.now() for a moment needs an entry in allowedNow with a reason.',
    );
  });

  test('toLocal() is not used to show a time', () {
    final bad = <String>[];
    for (final f in Directory('lib/features').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (RegExp(r'\.toLocal\(\)').hasMatch(f.readAsStringSync())) {
        bad.add(f.path);
      }
    }
    // Times shown to the person are Manila wall time (manilaWall); the phone's zone is not theirs
    expect(bad, isEmpty);
  });

  group('the Manila clock', () {
    test('a moment late in the UTC evening is already tomorrow in Manila', () {
      final late = DateTime.utc(2026, 10, 31, 17, 30);
      expect(manilaToday(late), '2026-11-01');
      expect(manilaNow(late).day, 1);
      expect(manilaNow(late).hour, 1);
    });

    test('a picked Manila time round-trips to the same wall reading', () {
      final wall = DateTime(2026, 3, 8, 9, 30);
      final instant = manilaInstant(wall);
      expect(instant.isUtc, isTrue);
      expect(instant, DateTime.utc(2026, 3, 8, 1, 30));
      final back = manilaWall(instant);
      expect(
        <int>[back.year, back.month, back.day, back.hour, back.minute],
        <int>[2026, 3, 8, 9, 30],
      );
    });

    test('an all-day start is the Manila midnight', () {
      expect(manilaInstant(DateTime(2026, 5, 2)), DateTime.utc(2026, 5, 1, 16));
      expect(manilaDayStart('2026-05-02'), DateTime.utc(2026, 5, 1, 16));
    });

    test('calendar days step by date, never by 24 hours', () {
      // The last day of a fall-back (a 25 hour day) and of a spring-forward (23 hours) in the US zones
      for (final d in <DateTime>[DateTime(2026, 11, 1), DateTime(2026, 3, 8)]) {
        final next = addCalendarDays(d, 7);
        expect(next.hour, 0);
        expect(calendarDaysBetween(d, next), 7);
        expect(calendarDaysBetween(next, d), -7);
      }
      expect(addCalendarDays(DateTime(2026, 12, 30), 3), DateTime(2027, 1, 2));
      expect(
        calendarDaysBetween(DateTime(2026, 1, 1), DateTime(2026, 12, 31)),
        364,
      );
    });

    test('the day count of a window ignores the time of day', () {
      expect(
        calendarDaysBetween(
          DateTime(2026, 3, 1, 23, 59),
          DateTime(2026, 3, 2, 0, 1),
        ),
        1,
      );
    });
  });
}
