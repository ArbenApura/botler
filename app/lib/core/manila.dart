// MANILA CALENDAR DATES AS yyyy-MM-dd TEXT. "A DAY" IN THIS APP IS A MANILA DATE, WHATEVER TIME ZONE THE PHONE IS SET TO.
// Dates are kept as text and compared as text (they sort the same way), so no time zone can move one by a day.

// -- DEP-MODULES -- //
import 'package:intl/intl.dart';

// -- CONSTANTS -- //

final DateFormat _day = DateFormat('yyyy-MM-dd');

// -- FUNCTIONS -- //

/// Today in Manila. [now] is for tests.
String manilaToday([DateTime? now]) =>
    _day.format((now ?? DateTime.now()).toUtc().add(const Duration(hours: 8)));

/// The date [days] after (or before, when negative) the Manila date [iso].
String addDaysTo(String iso, int days) =>
    _day.format(DateTime.parse('${iso}T00:00:00Z').add(Duration(days: days)));

/// A Manila date as a plain DateTime at local midnight, for a date picker. Null when [iso] is not a date.
DateTime? dayOf(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// A date picker's answer as the date text the server takes.
String isoOf(DateTime d) => _day.format(DateTime(d.year, d.month, d.day));
