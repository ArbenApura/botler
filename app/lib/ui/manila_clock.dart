// THE MANILA CLOCK FOR SCREENS. A DAY IS A MANILA CALENDAR DATE AND A TIME THE PERSON SEES IS MANILA WALL TIME, WHATEVER ZONE THE PHONE IS IN.
// A "wall" value here is a DateTime whose year, month, day, hour and minute fields are the Manila clock reading; it is only for showing and picking.

// -- MODULES -- //
import '../core/manila.dart';

// -- CONSTANTS -- //

const Duration _manilaOffset = Duration(hours: 8);

// -- FUNCTIONS -- //

/// Now as a Manila wall reading. [now] is for tests.
DateTime manilaNow([DateTime? now]) =>
    (now ?? DateTime.now()).toUtc().add(_manilaOffset);

/// The Manila wall reading of a real moment (for showing it).
DateTime manilaWall(DateTime instant) => instant.toUtc().add(_manilaOffset);

/// The real moment (UTC) at which the Manila clock reads [wall]'s fields (for sending it).
DateTime manilaInstant(DateTime wall) => DateTime.utc(
  wall.year,
  wall.month,
  wall.day,
  wall.hour,
  wall.minute,
  wall.second,
).subtract(_manilaOffset);

/// The real moment at which Manila's day [iso] begins.
DateTime manilaDayStart(String iso) {
  final d = DateTime.parse('${iso}T00:00:00Z');
  return d.subtract(_manilaOffset);
}

/// Today's Manila date as the plain local-midnight DateTime a date picker wants.
DateTime manilaTodayPicker([DateTime? now]) =>
    dayOf(manilaToday(now)) ?? DateTime(2000);

/// [n] calendar days after [d], at local midnight. Calendar arithmetic, not 24 hour steps, so a daylight saving change cannot skip or repeat a day.
DateTime addCalendarDays(DateTime d, int n) =>
    DateTime(d.year, d.month, d.day + n);

/// Whole calendar days from [a] to [b] (negative when [b] is earlier), counted on the dates alone, so a 23 or 25 hour day cannot change the count.
int calendarDaysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
