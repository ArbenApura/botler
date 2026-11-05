// EVERY DATE AND TIME THE PERSON SEES GOES THROUGH core/clock.dart: THIS FAILS WHEN A SCREEN FORMATS ONE ITSELF (BTL-20261105-0529)

// -- DEP-MODULES -- //
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// -- CONSTANTS -- //

/// Files that may format a date themselves, and why.
const Map<String, String> allowed = <String, String>{
  'core/clock.dart': 'the one place that formats a date or a time',
  'core/schedule_text.dart':
      'reads month and weekday NAMES from the symbol tables, formats nothing',
  'calendar/calendar_screen.dart':
      'reads weekday NAMES from the symbol table, formats nothing',
  'money/schedule_picker.dart':
      'reads weekday NAMES from the symbol table, formats nothing',
  'calendar/calendar_data.dart':
      'yyyy-MM-dd is the key a day is stored under, never shown',
  'main.dart': 'loads the date symbols',
  'core/clock_picker_l10n.dart':
      'gives the date pickers the same patterns clock.dart uses',
};

/// What a screen may not write: a display skeleton, a time of day formatted by the framework, a hand-made clock, the Manila offset.
final List<RegExp> banned = <RegExp>[
  RegExp(r'DateFormat\.\w+\('),
  RegExp(r"DateFormat\('(?!yyyy-MM-dd')"),
  RegExp(r'\.add_(jm|Hm|Hms|jms)\('),
  RegExp(r'\.formatTimeOfDay\('),
  RegExp(r'\.format\(context\)'),
  RegExp(r'hour\.toString\(\)\.padLeft'),
  RegExp(r'Duration\(hours: 8\)'),
];

// -- TESTS -- //

void main() {
  test('no screen formats a date or time itself', () {
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/').replaceFirst('lib/', '');
      if (allowed.keys.any(path.endsWith)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].replaceFirst(RegExp(r'//.*$'), '');
        if (banned.any((r) => r.hasMatch(code))) {
          found.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(found, isEmpty, reason: found.join('\n'));
  });
}
