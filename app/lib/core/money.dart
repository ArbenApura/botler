// MONEY IN THE APP: INTEGER CENTAVOS EVERYWHERE, SHOWN AS PESOS. A FLOAT NEVER HOLDS AN AMOUNT.

// -- FUNCTIONS -- //

/// ₱1,234.50, with a minus sign for a negative amount. Built from integers, so it is exact.
String formatPhp(int centavos) {
  final abs = centavos.abs();
  final whole = (abs ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final cents = (abs % 100).toString().padLeft(2, '0');
  return '${centavos < 0 ? '-' : ''}₱$whole.$cents';
}

/// What a person typed ("180", "1,250.50", "₱ 90") as centavos, or null when it is not an amount.
int? parsePesos(String text) {
  final cleaned = text.replaceAll(
    RegExp(r'[₱,\s]|php', caseSensitive: false),
    '',
  );
  final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(cleaned);
  if (m == null) return null;
  final whole = int.tryParse(m.group(1) ?? '');
  if (whole == null) return null;
  final frac = (m.group(2) ?? '').padRight(2, '0');
  final cents = int.tryParse(frac.isEmpty ? '0' : frac) ?? 0;
  final total = whole * 100 + cents;
  // The server holds amounts in a 32 bit integer
  return total > 2147483647 ? null : total;
}

/// The amount typed into a field, without the peso sign, for putting back in the field: 18000 -> "180.00".
String pesosText(int centavos) =>
    '${centavos ~/ 100}.${(centavos.abs() % 100).toString().padLeft(2, '0')}';
