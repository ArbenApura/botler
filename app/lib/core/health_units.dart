// HEALTH UNITS AT THE DISPLAY EDGE: THE SERVER WORKS IN WHOLE GRAMS, MILLIMETRES AND KCAL. THIS FILE ONLY READS WHAT A PERSON TYPED AND WRITES WHAT THEY SEE, WITHOUT A FLOAT.

// -- FUNCTIONS -- //

/// Reads "74" or "74.2" as whole units of a thousandth (74200), or null when it is not a number. At most three decimals are kept.
int? thousandthsFromText(String text) {
  final t = text.trim().replaceAll(',', '.');
  final m = RegExp(r'^(\d{1,4})(?:\.(\d{1,3}))?$').firstMatch(t);
  if (m == null) return null;
  final whole = int.parse(m.group(1) ?? '0');
  final part = (m.group(2) ?? '').padRight(3, '0');
  return whole * 1000 + int.parse(part);
}

/// Grams from kilograms typed by a person.
int? gramsFromKgText(String text) => thousandthsFromText(text);

/// Millimetres from centimetres typed by a person.
int? mmFromCmText(String text) {
  final v = thousandthsFromText(text);
  return v == null ? null : (v / 100).round();
}

/// 74200 grams reads "74.2". A whole kilogram reads "74".
String kgText(int grams) {
  final tenths = (grams / 100).round();
  final whole = tenths ~/ 10;
  final part = tenths % 10;
  return part == 0 ? '$whole' : '$whole.$part';
}

/// Whole kcal with a thousands comma: 1850 reads "1,850".
String kcalText(int kcal) {
  final digits = kcal.abs().toString();
  final out = StringBuffer(kcal < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Whole grams from milligrams, as a person reads them: 118400 reads "118".
String gramsFromMgText(int mg) => '${(mg / 1000).round()}';

/// How long a number of minutes is: 400 reads "6 h 40 min".
String durationText(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}
