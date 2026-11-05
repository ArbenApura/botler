// DAYS AS yyyy-MM-dd TEXT. "A DAY" IN THIS APP IS A DATE IN THE PERSON'S ZONE (ASIA/MANILA UNTIL THEY CHOOSE ANOTHER), WHATEVER ZONE THE PHONE IS SET TO.
// Dates are kept as text and compared as text (they sort the same way), so no time zone can move one by a day. The names keep "Manila" from when
// the zone was fixed; the zone itself now lives in clock.dart.

// -- MODULES -- //
import 'clock.dart' as clock;

export 'clock.dart' show addDaysTo, dayOf, isoOf;

// -- FUNCTIONS -- //

/// Today in the person's zone. [now] is for tests.
String manilaToday([DateTime? now]) => clock.zoneToday(now);
