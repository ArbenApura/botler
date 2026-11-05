// THE DATE PICKERS WRITE A DATE IN THE PERSON'S ORDER, THE SAME WAY EVERY SCREEN DOES.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

// -- MODULES -- //
import 'package:botler/core/clock.dart';
import 'package:botler/core/clock_picker_l10n.dart';

// -- FUNCTIONS -- //

Future<MaterialLocalizations> load(String style, [String language = 'en']) =>
    ClockMaterialDelegate(ClockPrefs(dateStyle: style, language: language))
        .load(Locale(language));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('fil');
  });

  final day = DateTime(2026, 11, 5);

  test('the picker writes the date in the chosen order', () async {
    final dmy = await load('dmy');
    expect(dmy.formatMediumDate(day), 'Thu, 5 Nov');
    expect(dmy.formatShortDate(day), '5 Nov 2026');
    expect(dmy.formatCompactDate(day), '05/11/2026');
    expect(dmy.dateHelpText, 'dd/mm/yyyy');
    final mdy = await load('mdy');
    expect(mdy.formatMediumDate(day), 'Thu, Nov 5');
    expect(mdy.formatCompactDate(day), '11/05/2026');
    expect(mdy.dateHelpText, 'mm/dd/yyyy');
    final ymd = await load('ymd');
    expect(ymd.formatCompactDate(day), '2026/11/05');
    expect(ymd.dateHelpText, 'yyyy/mm/dd');
  });

  test('auto is day, month, year, and the words stay the language', () async {
    final auto = await load('auto');
    expect(auto.formatCompactDate(day), '05/11/2026');
    expect(auto.okButtonLabel, 'OK');
    final fil = await load('dmy', 'fil');
    expect(fil.formatMonthYear(day), 'Nobyembre 2026');
  });

  test('a change of order reloads the delegate', () {
    const a = ClockMaterialDelegate(ClockPrefs(dateStyle: 'dmy'));
    const b = ClockMaterialDelegate(ClockPrefs(dateStyle: 'mdy'));
    expect(b.shouldReload(a), isTrue);
    expect(a.shouldReload(a), isFalse);
  });
}
