// THE CLOCK FOR SCREENS. A DAY IS A DATE IN THE PERSON'S ZONE AND A TIME THE PERSON SEES IS THAT ZONE'S WALL TIME, WHATEVER ZONE THE PHONE IS IN.
// A "wall" value here is a DateTime whose year, month, day, hour and minute fields are the clock reading in the person's zone; it is only for
// showing and picking. The names keep "Manila" from when the zone was fixed; the work is in core/clock.dart.

// -- MODULES -- //
import '../core/clock.dart' as clock;

export '../core/clock.dart' show addCalendarDays, calendarDaysBetween;

// -- FUNCTIONS -- //

/// Now as a wall reading. [now] is for tests.
DateTime manilaNow([DateTime? now]) => clock.zoneNow(now);

/// The wall reading of a real moment (for showing it).
DateTime manilaWall(DateTime instant) => clock.zoneWall(instant);

/// The real moment (UTC) at which the person's clock reads [wall]'s fields (for sending it).
DateTime manilaInstant(DateTime wall) => clock.zoneInstant(wall);

/// The real moment at which the day [iso] begins.
DateTime manilaDayStart(String iso) => clock.zoneDayStart(iso);

/// Today's date as the plain local-midnight DateTime a date picker wants.
DateTime manilaTodayPicker([DateTime? now]) => clock.zoneTodayPicker(now);
