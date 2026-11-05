// THE DATE PICKERS IN THE PERSON'S DATE ORDER. FLUTTER'S OWN PICKERS WRITE A DATE WITH THE LANGUAGE'S FORMATS; THIS DELEGATE REPLACES THOSE FORMATS WITH THE ONES core/clock.dart USES, SO A PICKER AND A SCREEN NEVER DISAGREE.
// Only the date formats and the hint of the typing box change: every word still comes from Flutter's own translation of the language.

// -- DEP-MODULES -- //
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

// -- MODULES -- //
import 'clock.dart';

// -- CONSTANTS -- //

/// The numbers-only pattern of the typing box, and its hint, for each date order.
const Map<String, String> _compact = <String, String>{
  'dmy': 'dd/MM/y',
  'mdy': 'MM/dd/y',
  'ymd': 'y/MM/dd',
};
const Map<String, String> _hint = <String, String>{
  'dmy': 'dd/mm/yyyy',
  'mdy': 'mm/dd/yyyy',
  'ymd': 'yyyy/mm/dd',
};

String _style(ClockPrefs p) => p.dateStyle == 'auto' ? 'dmy' : p.dateStyle;

// -- TYPES -- //

/// The hint of the typing box follows the date order.
mixin _OrderedHint on GlobalMaterialLocalizations {
  String get hintFor;

  @override
  String get dateHelpText => _hint[hintFor] ?? 'dd/mm/yyyy';
}

class _En extends MaterialLocalizationEn with _OrderedHint {
  const _En({
    required this.hintFor,
    required super.fullYearFormat,
    required super.compactDateFormat,
    required super.shortDateFormat,
    required super.mediumDateFormat,
    required super.longDateFormat,
    required super.yearMonthFormat,
    required super.shortMonthDayFormat,
    required super.decimalFormat,
    required super.twoDigitZeroPaddedFormat,
  });

  @override
  final String hintFor;
}

class _Fil extends MaterialLocalizationFil with _OrderedHint {
  const _Fil({
    required this.hintFor,
    required super.fullYearFormat,
    required super.compactDateFormat,
    required super.shortDateFormat,
    required super.mediumDateFormat,
    required super.longDateFormat,
    required super.yearMonthFormat,
    required super.shortMonthDayFormat,
    required super.decimalFormat,
    required super.twoDigitZeroPaddedFormat,
  });

  @override
  final String hintFor;
}

class ClockMaterialDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const ClockMaterialDelegate(this.prefs);

  final ClockPrefs prefs;

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'fil';

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    final loc = locale.languageCode == 'fil' ? 'fil' : 'en';
    final style = _style(prefs);
    // The same patterns every screen uses, with the compact one for the typing box
    String p(DateKind k) => datePattern(k, style);
    final fullYear = DateFormat.y(loc);
    final compact = DateFormat(_compact[style] ?? 'dd/MM/y', loc);
    final short = DateFormat(p(DateKind.date), loc);
    final medium = DateFormat(p(DateKind.monthDayWeekday), loc);
    final long = DateFormat(p(DateKind.dateLongWeekday), loc);
    final yearMonth = DateFormat(p(DateKind.monthYear), loc);
    final monthDay = DateFormat(p(DateKind.monthDay), loc);
    final decimal = NumberFormat.decimalPattern(loc);
    final twoDigit = NumberFormat('00', loc);
    return SynchronousFuture<MaterialLocalizations>(
      loc == 'fil'
          ? _Fil(
              hintFor: style,
              fullYearFormat: fullYear,
              compactDateFormat: compact,
              shortDateFormat: short,
              mediumDateFormat: medium,
              longDateFormat: long,
              yearMonthFormat: yearMonth,
              shortMonthDayFormat: monthDay,
              decimalFormat: decimal,
              twoDigitZeroPaddedFormat: twoDigit,
            )
          : _En(
              hintFor: style,
              fullYearFormat: fullYear,
              compactDateFormat: compact,
              shortDateFormat: short,
              mediumDateFormat: medium,
              longDateFormat: long,
              yearMonthFormat: yearMonth,
              shortMonthDayFormat: monthDay,
              decimalFormat: decimal,
              twoDigitZeroPaddedFormat: twoDigit,
            ),
    );
  }

  @override
  bool shouldReload(ClockMaterialDelegate old) => old.prefs != prefs;
}
