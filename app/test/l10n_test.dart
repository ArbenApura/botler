// THE TWO LANGUAGES STAY IN STEP: THE SAME KEYS, THE SAME PLACEHOLDERS, NO EMPTY TEXT, AND NO ENGLISH LEFT IN A TRANSLATION BY ACCIDENT.

// -- DEP-MODULES -- //
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// -- FUNCTIONS -- //

Map<String, Object?> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

Set<String> _placeholders(String text) =>
    RegExp(r'\{(\w+)').allMatches(text).map((m) => m.group(1)!).toSet();

void main() {
  final en = _arb('lib/l10n/app_en.arb');
  final fil = _arb('lib/l10n/app_fil.arb');
  final keys = en.keys.where((k) => !k.startsWith('@')).toList();

  test('Filipino has every key English has, and no other', () {
    final filKeys = fil.keys.where((k) => !k.startsWith('@')).toSet();
    expect(filKeys.difference(keys.toSet()), isEmpty);
    expect(keys.toSet().difference(filKeys), isEmpty);
  });

  test(
    'every text is filled and uses the same placeholders in both languages',
    () {
      for (final k in keys) {
        final e = en[k]! as String;
        final f = fil[k]! as String;
        expect(e.trim(), isNotEmpty, reason: 'English $k');
        expect(f.trim(), isNotEmpty, reason: 'Filipino $k');
        // A plural or select keeps its own braces; the names that are filled in must match
        Set<String> names(String s) =>
            _placeholders(s)
                .where((n) => n != 'count' || s.contains('plural'))
                .toSet();
        expect(names(f), names(e), reason: 'placeholders of $k');
      }
    },
  );

  test('the template is English and the translation is Filipino', () {
    expect(en['@@locale'], 'en');
    expect(fil['@@locale'], 'fil');
  });
}
