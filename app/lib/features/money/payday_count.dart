// HOW MANY PAYDAYS A YEAR A PAYDAY SCHEDULE HAS, FOR "IN A YEAR THAT IS ..." LINES. PURE: NO CLOCK, NO SCREEN.
// The schedule is the JSON the server keeps for an income (kind and its fields). A kind this version does not know gives null: never a guess.

// -- MODULES -- //
import '../../core/json.dart';

// -- FUNCTIONS -- //

/// Paydays in a year for one schedule, or null when it is not known (an unknown kind, or a single date).
int? paydaysPerYear(Json schedule) {
  final every = intOf(schedule['everyMonths'], 1).clamp(1, 12);
  switch (str(schedule['kind'])) {
    case 'monthly' || 'nth_weekday' || 'week_of_month' || 'day_range':
      return 12 ~/ every;
    case 'semi_monthly':
      return 24;
    case 'every_n_days':
      final n = intOf(schedule['n'], 0);
      return n < 1 ? null : 365 ~/ n;
    case 'weekly':
      final days = asList(schedule['days']).length;
      final weeks = intOf(schedule['everyWeeks'], 1).clamp(1, 52);
      return days < 1 ? null : (52 ~/ weeks) * days;
    case 'yearly':
      return 1;
  }
  return null;
}

/// Paydays in a year for the person's incomes: those of the first active one that has a known schedule, else null.
int? paydaysPerYearOf(List<Json> incomes) {
  for (final i in incomes) {
    if (i['active'] == false) continue;
    final n = paydaysPerYear(asJson(i['schedule']));
    if (n != null) return n;
  }
  return null;
}
