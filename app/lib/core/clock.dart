// THE CLOCK OF THE APP: WHAT DAY IT IS AND HOW A DATE OR A TIME READS, FOLLOWING THE ZONE, THE 12 OR 24 HOUR CLOCK AND THE DATE ORDER THE PERSON CHOSE.
// Every screen shows dates and times through this file, and nowhere else. A "wall" value is a DateTime whose year, month, day, hour and minute
// fields are the clock reading in the person's zone (flagged UTC so the phone's own zone can never touch it); it is only for showing and picking.

// -- DEP-MODULES -- //
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// -- MODULES -- //
import 'zone_list.dart';

// -- TYPES -- //

/// What the person chose in Settings about time. [timeFormat] is auto, 12 or 24; [dateStyle] is auto, dmy, mdy or ymd.
class ClockPrefs {
  const ClockPrefs({
    this.zone = defaultZone,
    this.timeFormat = 'auto',
    this.dateStyle = 'auto',
    this.language = 'en',
  });

  final String zone;
  final String timeFormat;
  final String dateStyle;

  /// The language of the app, for month and day names.
  final String language;

  @override
  bool operator ==(Object other) =>
      other is ClockPrefs &&
      other.zone == zone &&
      other.timeFormat == timeFormat &&
      other.dateStyle == dateStyle &&
      other.language == language;

  @override
  int get hashCode => Object.hash(zone, timeFormat, dateStyle, language);
}

/// The kinds of date text the screens use.
enum DateKind {
  /// Nov 5
  monthDay,

  /// November 5
  monthDayLong,

  /// Nov 5, 2026
  date,

  /// Thu, Nov 5
  monthDayWeekday,

  /// November 5, 2026
  dateLong,

  /// Thursday, November 5, 2026
  dateLongWeekday,

  /// November 2026
  monthYear,
}

// -- CONSTANTS -- //

/// The zone of a person who has not chosen one.
const String defaultZone = 'Asia/Manila';

final DateFormat _day = DateFormat('yyyy-MM-dd');

// -- STATES -- //

/// The choices in force. Set by the settings notifier whenever they change (and from the stored copy at start), read by every function here.
ClockPrefs clockPrefs = const ClockPrefs();

bool _zonesReady = false;
final Map<String, tz.Location?> _locations = <String, tz.Location?>{};

// -- FUNCTIONS -- //

/// Loads the zone database once. Called by whatever needs a zone first, so no start-up order can leave it missing.
void ensureTimeZones() {
  if (_zonesReady) return;
  _zonesReady = true;
  try {
    tzdata.initializeTimeZones();
  } on Object {
    // Without the database only the default zone works (it has no daylight saving, so a fixed shift is exact)
  }
}

tz.Location? _locationOf(String zone) {
  ensureTimeZones();
  return _locations.putIfAbsent(zone, () {
    try {
      return tz.getLocation(zone);
    } on Object {
      return null;
    }
  });
}

/// The zones a person can choose: the shared list (the server accepts exactly these), keeping the ones this phone can read. For the zone picker.
List<String> zoneNames() => <String>[
  for (final z in timeZoneNames)
    if (isKnownZone(z)) z,
];

/// "UTC+9" or "UTC+5:30" for a zone right now.
String zoneOffsetLabel(String zone, [DateTime? now]) {
  final off = offsetAt(now ?? DateTime.now(), zone);
  final minutes = off.inMinutes.abs();
  final sign = off.isNegative ? '-' : '+';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return 'UTC$sign$h${m == 0 ? '' : ':${m.toString().padLeft(2, '0')}'}';
}

/// True when the zone name is one this phone knows.
bool isKnownZone(String zone) => _locationOf(zone) != null;

/// The zone in force: the person's, or Manila when the name is not one this phone knows.
String get activeZone =>
    isKnownZone(clockPrefs.zone) ? clockPrefs.zone : defaultZone;

/// How far ahead of UTC the zone's clock is at a real moment.
Duration offsetAt(DateTime instant, [String? zone]) {
  final loc = _locationOf(zone ?? activeZone);
  if (loc == null) return const Duration(hours: 8);
  return tz.TZDateTime.from(instant.toUtc(), loc).timeZoneOffset;
}

/// The clock reading in the person's zone at a real moment, as a wall value.
DateTime zoneWall(DateTime instant, [String? zone]) =>
    instant.toUtc().add(offsetAt(instant, zone));

/// Now as a wall reading. [now] is for tests.
DateTime zoneNow([DateTime? now, String? zone]) =>
    zoneWall(now ?? DateTime.now(), zone);

/// The real moment at which the person's clock reads [wall]'s fields. A time that does not exist (spring forward) lands after the gap; one
/// that happens twice (fall back) is the first.
DateTime zoneInstant(DateTime wall, [String? zone]) {
  final loc = _locationOf(zone ?? activeZone);
  if (loc == null) {
    return DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
      wall.second,
    ).subtract(const Duration(hours: 8));
  }
  return tz.TZDateTime(
    loc,
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
  ).toUtc();
}

/// The real moment at which the day [iso] begins in the person's zone.
DateTime zoneDayStart(String iso, [String? zone]) {
  final d = DateTime.parse('${iso}T00:00:00Z');
  return zoneInstant(d, zone);
}

/// Today in the person's zone, as yyyy-MM-dd. [now] is for tests.
String zoneToday([DateTime? now, String? zone]) =>
    _day.format(zoneNow(now, zone));

/// The date [days] after (or before, when negative) the date [iso]. Calendar arithmetic on the text, so no zone can move it.
String addDaysTo(String iso, int days) =>
    _day.format(DateTime.parse('${iso}T00:00:00Z').add(Duration(days: days)));

/// A date as a plain DateTime at local midnight, for a date picker. Null when [iso] is not a date, or is a day that does not exist
/// (2026-02-30 would otherwise slide to March 2).
DateTime? dayOf(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return null;
  // The parser rolls an impossible day over to the next month, so the year, month and day written are checked against what came out
  final written = RegExp(r'^\s*(\d{4})-(\d{2})-(\d{2})').firstMatch(iso);
  if (written != null &&
      (int.parse(written.group(1) ?? '0') != d.year ||
          int.parse(written.group(2) ?? '0') != d.month ||
          int.parse(written.group(3) ?? '0') != d.day)) {
    return null;
  }
  return DateTime(d.year, d.month, d.day);
}

/// A date picker's answer as the date text the server takes.
String isoOf(DateTime d) => _day.format(DateTime(d.year, d.month, d.day));

/// Today's date as the plain local-midnight DateTime a date picker wants.
DateTime zoneTodayPicker([DateTime? now]) =>
    dayOf(zoneToday(now)) ?? DateTime(2000);

/// [n] calendar days after [d], at local midnight. Calendar arithmetic, not 24 hour steps, so a daylight saving change cannot skip or repeat a day.
DateTime addCalendarDays(DateTime d, int n) =>
    DateTime(d.year, d.month, d.day + n);

/// Whole calendar days from [a] to [b] (negative when [b] is earlier), counted on the dates alone, so a 23 or 25 hour day cannot change the count.
int calendarDaysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

// -- FORMATS -- //

String get _locale => clockPrefs.language == 'fil' ? 'fil' : 'en';

/// True when clock times read as 24 hour: the person's choice, or the phone's when they left it on auto.
bool get uses24Hour => switch (clockPrefs.timeFormat) {
  '24' => true,
  '12' => false,
  _ => PlatformDispatcher.instance.alwaysUse24HourFormat,
};

/// 3:42 PM or 15:42 for a clock reading (only its hour and minute are used).
String fmtTime(DateTime wall) => uses24Hour
    ? DateFormat('HH:mm', _locale).format(wall)
    : DateFormat('h:mm a', _locale).format(wall);

/// A time of day picked on a clock.
String fmtTimeOfDay(TimeOfDay t) =>
    fmtTime(DateTime.utc(2000, 1, 1, t.hour, t.minute));

/// A time of day as "HH:mm", the form the server takes (always 24 hour, whatever the person reads).
String hhmmOf(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// "HH:mm" from the server as a time of day for a picker. A bad text reads as midnight.
TimeOfDay timeOfHm(String hhmm) {
  final p = hhmm.split(':');
  return TimeOfDay(
    hour: p.isNotEmpty ? int.tryParse(p[0]) ?? 0 : 0,
    minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0,
  );
}

/// The clock reading "HH:mm" (how the server and the weekly plan write it) as the person's clock text.
String fmtHm(String hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hhmm);
  if (m == null) return hhmm;
  return fmtTime(
    DateTime.utc(2000, 1, 1, int.parse(m.group(1)!), int.parse(m.group(2)!)),
  );
}

/// The pattern a date of this kind is written with, in the person's order (Auto is day, month, year). [style] is for the date pickers and tests.
String datePattern(DateKind kind, [String? style]) {
  switch (style ?? clockPrefs.dateStyle) {
    case 'mdy':
      return switch (kind) {
        DateKind.monthDay => 'MMM d',
        DateKind.monthDayLong => 'MMMM d',
        DateKind.date => 'MMM d, y',
        DateKind.monthDayWeekday => 'EEE, MMM d',
        DateKind.dateLong => 'MMMM d, y',
        DateKind.dateLongWeekday => 'EEEE, MMMM d, y',
        DateKind.monthYear => 'MMMM y',
      };
    case 'ymd':
      return switch (kind) {
        DateKind.monthDay => 'MMM d',
        DateKind.monthDayLong => 'MMMM d',
        DateKind.date => 'y MMM d',
        DateKind.monthDayWeekday => 'EEE, MMM d',
        DateKind.dateLong => 'y MMMM d',
        DateKind.dateLongWeekday => 'EEEE, y MMMM d',
        DateKind.monthYear => 'y MMMM',
      };
    default:
      // Day, month, year: the person's own choice, and what Auto means
      return switch (kind) {
        DateKind.monthDay => 'd MMM',
        DateKind.monthDayLong => 'd MMMM',
        DateKind.date => 'd MMM y',
        DateKind.monthDayWeekday => 'EEE, d MMM',
        DateKind.dateLong => 'd MMMM y',
        DateKind.dateLongWeekday => 'EEEE, d MMMM y',
        DateKind.monthYear => 'MMMM y',
      };
  }
}

/// A date as text in the person's order. The weekday and month names follow the app's language.
String fmtDate(DateTime d, [DateKind kind = DateKind.date]) =>
    DateFormat(datePattern(kind), _locale).format(d);

/// A date and the time after it: "Nov 5, 2026, 3:42 PM".
String fmtDateTime(DateTime wall, [DateKind kind = DateKind.date]) =>
    '${fmtDate(wall, kind)}, ${fmtTime(wall)}';

/// Mon / Monday for a date.
String fmtWeekday(DateTime d, {bool long = false}) =>
    (long ? DateFormat.EEEE(_locale) : DateFormat.E(_locale)).format(d);

/// Nov / November for a date.
String fmtMonth(DateTime d, {bool long = false}) =>
    (long ? DateFormat.MMMM(_locale) : DateFormat.MMM(_locale)).format(d);

/// Hour of the day on an axis or a chart: 3 PM or 15.
String fmtHour(int hour) => fmtTime(DateTime.utc(2000, 1, 1, hour));
