// THE CLOCK OF THE APP: THE PERSON'S ZONE DECIDES THE DAY, DAYLIGHT SAVING IS RIGHT, AND 12 OR 24 HOUR AND THE DATE ORDER FOLLOW THE SETTINGS.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

// -- MODULES -- //
import 'package:botler/core/clock.dart';

// -- FUNCTIONS -- //

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('fil');
  });

  setUp(() {
    ensureTimeZones();
    clockPrefs = const ClockPrefs();
  });

  group('zones', () {
    test('Manila is the default and today follows it', () {
      expect(zoneToday(DateTime.utc(2026, 10, 21, 17)), '2026-10-22');
    });

    test('another zone moves the day', () {
      final t = DateTime.utc(2026, 11, 5, 20);
      expect(zoneToday(t, 'Asia/Tokyo'), '2026-11-06');
      expect(zoneToday(t, 'America/New_York'), '2026-11-05');
      expect(zoneToday(t, 'Pacific/Kiritimati'), '2026-11-06');
      clockPrefs = const ClockPrefs(zone: 'America/New_York');
      expect(zoneToday(t), '2026-11-05');
    });

    test('a name the phone does not know falls back to Manila', () {
      clockPrefs = const ClockPrefs(zone: 'Not/AZone');
      expect(activeZone, defaultZone);
      expect(zoneToday(DateTime.utc(2026, 10, 21, 17)), '2026-10-22');
    });

    test('spring forward: the day is 23 hours, the missing time lands after the gap', () {
      const z = 'America/New_York';
      final len = zoneDayStart(
        '2026-03-09',
        z,
      ).difference(zoneDayStart('2026-03-08', z));
      expect(len, const Duration(hours: 23));
      expect(
        zoneInstant(DateTime.utc(2026, 3, 8, 2, 30), z),
        DateTime.utc(2026, 3, 8, 7, 30),
      );
    });

    test(
      'fall back: the day is 25 hours, the repeated time is the first one',
      () {
        const z = 'America/New_York';
        final len = zoneDayStart(
          '2026-11-02',
          z,
        ).difference(zoneDayStart('2026-11-01', z));
        expect(len, const Duration(hours: 25));
        expect(
          zoneInstant(DateTime.utc(2026, 11, 1, 1, 30), z),
          DateTime.utc(2026, 11, 1, 5, 30),
        );
      },
    );

    test('a half hour zone and a wall round trip', () {
      const z = 'Asia/Kolkata';
      final wall = DateTime.utc(2026, 6, 1, 9, 15);
      expect(zoneWall(zoneInstant(wall, z), z), wall);
      expect(
        offsetAt(DateTime.utc(2026, 6, 1), z),
        const Duration(hours: 5, minutes: 30),
      );
    });
  });

  group('formats', () {
    final evening = DateTime.utc(2026, 11, 5, 15, 42);

    test('12 and 24 hour clocks', () {
      clockPrefs = const ClockPrefs(timeFormat: '12');
      expect(fmtTime(evening), '3:42 PM');
      expect(fmtTimeOfDay(const TimeOfDay(hour: 7, minute: 5)), '7:05 AM');
      expect(fmtHm('18:30'), '6:30 PM');
      clockPrefs = const ClockPrefs(timeFormat: '24');
      expect(fmtTime(evening), '15:42');
      expect(fmtTimeOfDay(const TimeOfDay(hour: 7, minute: 5)), '07:05');
      expect(fmtHm('18:30'), '18:30');
    });

    test('date order', () {
      clockPrefs = const ClockPrefs(dateStyle: 'dmy');
      expect(fmtDate(evening), '5 Nov 2026');
      expect(fmtDate(evening, DateKind.monthDay), '5 Nov');
      clockPrefs = const ClockPrefs(dateStyle: 'mdy');
      expect(fmtDate(evening), 'Nov 5, 2026');
      expect(fmtDate(evening, DateKind.monthDayWeekday), 'Thu, Nov 5');
      clockPrefs = const ClockPrefs(dateStyle: 'ymd');
      expect(fmtDate(evening), '2026 Nov 5');
      expect(fmtDate(evening, DateKind.monthYear), '2026 November');
      clockPrefs = const ClockPrefs(dateStyle: 'dmy', timeFormat: '24');
      expect(fmtDateTime(evening), '5 Nov 2026, 15:42');
    });
  });
}
