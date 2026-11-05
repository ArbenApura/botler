// THE ZONE LIST: EVERY NAME THE SERVER ACCEPTS IS A ZONE THIS PHONE KNOWS, SO THE PICKER SHOWS ALL OF THEM AND NO CHOICE FALLS BACK TO MANILA.

// -- DEP-MODULES -- //
import 'package:flutter_test/flutter_test.dart';

// -- MODULES -- //
import 'package:botler/core/clock.dart';
import 'package:botler/core/zone_list.dart';

// -- TESTS -- //

void main() {
  test('every listed zone is one the phone knows', () {
    ensureTimeZones();
    final missing = <String>[
      for (final z in timeZoneNames)
        if (!isKnownZone(z)) z,
    ];
    expect(missing, isEmpty);
    expect(zoneNames(), timeZoneNames);
  });

  test('the list is sorted, with UTC first, and has no repeat', () {
    expect(timeZoneNames.first, 'UTC');
    final rest = timeZoneNames.sublist(1);
    expect(rest, <String>[...rest]..sort());
    expect(timeZoneNames.toSet().length, timeZoneNames.length);
  });
}
