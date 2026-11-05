// A SCHEDULE AS A SENTENCE IN THE PERSON'S LANGUAGE ("Every 1st Wednesday of the month"), BUILT ON THE PHONE FROM THE SCHEDULE'S OWN FIELDS.
// It mirrors the server's describeSchedule (server/src/lib/finance/schedule.ts), so a bill reads the same everywhere and offline. A kind this
// version of the app does not know gives null, and the screen shows the server's own sentence or a plain notice instead of failing.

// -- DEP-MODULES -- //
import 'package:intl/intl.dart';

// -- MODULES -- //
import '../l10n/l10n.dart';
import 'json.dart';
import 'clock.dart';

// -- CONSTANTS -- //

/// The kinds of schedule this version of the app can show and edit.
const Set<String> knownScheduleKinds = <String>{
  'monthly',
  'semi_monthly',
  'every_n_days',
  'weekly',
  'nth_weekday',
  'week_of_month',
  'day_range',
  'yearly',
  'once',
};

// -- FUNCTIONS -- //

/// 1st, 2nd, 3rd ... in English; ika-1, ika-2 ... in Filipino; the word for "last" for -1.
String ordinalWord(AppLocalizations t, String locale, int n) {
  if (n == -1) return t.schedLast;
  if (locale.startsWith('fil')) return 'ika-$n';
  final rest = n % 100;
  if (rest >= 11 && rest <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

List<String> weekdayNames(String locale) =>
    DateFormat('EEEE', locale).dateSymbols.WEEKDAYS;

List<String> monthNames(String locale) =>
    DateFormat('MMMM', locale).dateSymbols.MONTHS;

String _every(AppLocalizations t, Json s) {
  final n = intOf(s['everyMonths'], 1);
  return n > 1 ? t.schedSayEveryMonths(n) : '';
}

/// The sentence for a schedule, or null for a kind this version does not know. A first date, a last date and the dates left out follow in
/// brackets, as the server's describeSchedule writes them ("... (from 2026-01-01, until 2026-12-31, not on 2026-03-05)").
String? describeSchedule(AppLocalizations t, String locale, Json s) {
  final base = _describeRule(t, locale, s);
  if (base == null) return null;
  final extra = <String>[];
  final start = str(s['startsOn']);
  final end = str(s['endsOn']);
  final skips = <String>[
    for (final d in asList(s['skipDates']))
      if (d is String && d.isNotEmpty) d,
  ]..sort();
  if (start.isNotEmpty) extra.add(t.schedFromDate(start));
  if (end.isNotEmpty) extra.add(t.schedUntilDate(end));
  if (skips.isNotEmpty) extra.add(t.schedNotOnDates(skips.join(', ')));
  return extra.isEmpty ? base : '$base (${extra.join(', ')})';
}

String? _describeRule(AppLocalizations t, String locale, Json s) {
  final kind = str(s['kind']);
  final names = weekdayNames(locale);
  String ord(int n) => ordinalWord(t, locale, n);
  switch (kind) {
    case 'monthly':
      final day = intOf(s['day']);
      return day == -1
          ? t.schedSayMonthlyLast(_every(t, s))
          : t.schedSayMonthlyDay(ord(day), _every(t, s));
    case 'semi_monthly':
      final days = asList(s['days']);
      return t.schedSaySemi(
        ord(days.isNotEmpty ? intOf(days[0]) : 1),
        ord(days.length > 1 ? intOf(days[1]) : 15),
      );
    case 'every_n_days':
      final n = intOf(s['n'], 1);
      final date = str(s['anchor']);
      return n == 1 ? t.schedSayEveryDay(date) : t.schedSayEveryN(n, date);
    case 'weekly':
      final days = asList(s['days'])
          .map((d) => names[intOf(d).clamp(0, 6)])
          .join(', ');
      final every = intOf(s['everyWeeks'], 1);
      return every > 1
          ? t.schedSayWeeklyEvery(every, days)
          : t.schedSayWeekly(days);
    case 'nth_weekday':
      return t.schedSayNth(
        ord(intOf(s['n'], 1)),
        names[intOf(s['weekday']).clamp(0, 6)],
        _every(t, s),
      );
    case 'week_of_month':
      final n = intOf(s['n'], 1);
      final span = str(s['basis']) == 'calendar'
          ? t.schedSpanCalendar
          : (n == -1
                ? t.schedSpanLast
                : t.schedSpanDays((n - 1) * 7 + 1, n * 7));
      return str(s['pick']) == 'weekday'
          ? t.schedSayWeekWeekday(
              names[intOf(s['weekday']).clamp(0, 6)],
              ord(n),
              span,
              _every(t, s),
            )
          : t.schedSayWeekWindow(ord(n), span, _every(t, s));
    case 'day_range':
      final from = ord(intOf(s['from'], 1));
      return intOf(s['to']) == -1
          ? t.schedSayRangeToLast(from, _every(t, s))
          : t.schedSayRange(from, ord(intOf(s['to'], 1)), _every(t, s));
    case 'yearly':
      final months = monthNames(locale);
      return t.schedSayYearly(
        months[(intOf(s['month'], 1) - 1).clamp(0, 11)],
        intOf(s['day'], 1),
      );
    case 'once':
      final date = DateTime.tryParse(str(s['date']));
      return date == null ? null : t.schedSayOnce(fmtDate(date));
  }
  return null;
}

/// A schedule whose occurrences are a window (several days), so a bill with it can be paid any day inside.
bool isWindowSchedule(Json s) =>
    str(s['kind']) == 'day_range' ||
    (str(s['kind']) == 'week_of_month' && str(s['pick']) != 'weekday');
