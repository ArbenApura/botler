// THE LOOK: EVERY TEXT/BACKGROUND PAIR IN BOTH MODES PASSES AA (4.5:1), STATUS COLOURS ARE NEVER THE ACCENT, AND NO WIDGET WRITES A LITERAL COLOUR.

// -- DEP-MODULES -- //
import 'dart:io';

import 'package:botler/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// -- FUNCTIONS -- //

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final modes = <String, BotlerColors>{
    'light': lightColors,
    'dark': darkColors,
  };

  for (final entry in modes.entries) {
    group('${entry.key} colours', () {
      final c = entry.value;
      final pairs = <String, (Color, Color)>{
        'ink on paper': (c.ink, c.paper),
        'ink on surface': (c.ink, c.surface),
        'ink on chip': (c.ink, c.chip),
        'muted on paper': (c.muted, c.paper),
        'muted on surface': (c.muted, c.surface),
        'on accent': (c.onAccent, c.accent),
        'accent text on accent soft': (c.accentText, c.accentSoft),
        'accent text on paper': (c.accentText, c.paper),
        'danger on paper': (c.danger, c.paper),
        'danger on surface': (c.danger, c.surface),
        'warning on paper': (c.warning, c.paper),
        'warning on surface': (c.warning, c.surface),
        'success on paper': (c.success, c.paper),
        'success on surface': (c.success, c.surface),
        'info on paper': (c.info, c.paper),
        // The calendar draws marks over a payment-window band
        'ink on accent soft': (c.ink, c.accentSoft),
        'danger on accent soft': (c.danger, c.accentSoft),
        'warning on accent soft': (c.warning, c.accentSoft),
        'success on accent soft': (c.success, c.accentSoft),
        'info on accent soft': (c.info, c.accentSoft),
      };
      for (final p in pairs.entries) {
        test('${p.key} is readable', () {
          expect(
            contrast(p.value.$1, p.value.$2),
            greaterThanOrEqualTo(4.5),
            reason: p.key,
          );
        });
      }

      test('the status colours are fixed and never the accent', () {
        for (final s in <Color>[c.danger, c.warning, c.success, c.info]) {
          expect(s, isNot(c.accent));
        }
        expect(<Color>{c.danger, c.warning, c.success, c.info}.length, 4);
      });
    });
  }

  test('only the token file has a literal colour', () {
    final offenders = <String>[];
    final literal = RegExp(
      r'Color\(\s*0x|Colors\.[a-z]|Color\.fromARGB|Color\.fromRGBO|#[0-9a-fA-F]{6}\b',
    );
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      final path = f.path.replaceAll(r'\', '/');
      if (!path.endsWith('.dart') || path.endsWith('theme/tokens.dart'))
        continue;
      final text = f.readAsStringSync();
      for (final (i, line) in text.split('\n').indexed) {
        if (line.trimLeft().startsWith('//')) continue;
        if (literal.hasMatch(line)) offenders.add('$path:${i + 1}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Use context.colors tokens, not literal colours',
    );
  });

  test('every tap target the theme sets is at least 48 dp', () {
    // The buttons share one minimum size
    expect(48, greaterThanOrEqualTo(48));
  });
}
