// MONEY IN THE APP: INTEGERS IN THE MINOR UNIT OF THE PERSON'S CURRENCY EVERYWHERE (CENTAVOS, CENTS, YEN). A FLOAT NEVER HOLDS AN AMOUNT.
// The currencies are the server's catalogue (server/src/lib/finance/currency.ts). Changing the currency relabels amounts, it never converts.

// -- TYPES -- //

class Currency {
  const Currency(this.code, this.symbol, this.digits, this.name);

  /// ISO 4217 code.
  final String code;

  /// What is written in front of an amount.
  final String symbol;

  /// Digits after the decimal point: 2 for centavos and cents, 0 for yen and won.
  final int digits;
  final String name;
}

// -- CONSTANTS -- //

const String defaultCurrency = 'PHP';

/// The server holds amounts in a 32 bit integer.
const int maxMinor = 2147483647;

const List<Currency> currencies = <Currency>[
  Currency('PHP', '₱', 2, 'Philippine peso'),
  Currency('USD', r'$', 2, 'US dollar'),
  Currency('EUR', '€', 2, 'Euro'),
  Currency('GBP', '£', 2, 'Pound sterling'),
  Currency('JPY', '¥', 0, 'Japanese yen'),
  Currency('KRW', '₩', 0, 'South Korean won'),
  Currency('CNY', 'CN¥', 2, 'Chinese yuan'),
  Currency('HKD', r'HK$', 2, 'Hong Kong dollar'),
  Currency('SGD', r'S$', 2, 'Singapore dollar'),
  Currency('AUD', r'A$', 2, 'Australian dollar'),
  Currency('NZD', r'NZ$', 2, 'New Zealand dollar'),
  Currency('CAD', r'C$', 2, 'Canadian dollar'),
  Currency('CHF', 'CHF ', 2, 'Swiss franc'),
  Currency('INR', '₹', 2, 'Indian rupee'),
  Currency('IDR', 'Rp', 2, 'Indonesian rupiah'),
  Currency('MYR', 'RM', 2, 'Malaysian ringgit'),
  Currency('THB', '฿', 2, 'Thai baht'),
  Currency('VND', '₫', 0, 'Vietnamese dong'),
  Currency('TWD', r'NT$', 2, 'New Taiwan dollar'),
  Currency('AED', 'AED ', 2, 'UAE dirham'),
  Currency('SAR', 'SAR ', 2, 'Saudi riyal'),
];

// -- FUNCTIONS -- //

/// The currency of a code. An unknown code falls back to pesos, so a screen never breaks on a value from a newer server.
Currency currencyOf(String code) => currencies.firstWhere(
  (c) => c.code == code,
  orElse: () => currencies.first,
);

String _grouped(int whole) => whole.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

/// ₱1,234.50, $1,234.50 or ¥1,234, with a minus sign for a negative amount. Built from integers, so it is exact.
String formatMoney(int minor, [String code = defaultCurrency]) {
  final c = currencyOf(code);
  final abs = minor.abs();
  final sign = minor < 0 ? '-' : '';
  if (c.digits == 0) return '$sign${c.symbol}${_grouped(abs)}';
  final cents = (abs % 100).toString().padLeft(2, '0');
  return '$sign${c.symbol}${_grouped(abs ~/ 100)}.$cents';
}

/// The amount for a text field, without the symbol, for putting back in the field: 18000 PHP is "180.00" and 180 JPY is "180".
String plainAmount(int minor, [String code = defaultCurrency]) {
  final c = currencyOf(code);
  final abs = minor.abs();
  final sign = minor < 0 ? '-' : '';
  if (c.digits == 0) return '$sign$abs';
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}

/// What a person typed ("180", "1,250.50", "₱ 90", "usd 5") as minor units, or null when it is not an amount of this currency.
/// A currency with no decimals refuses a decimal point.
int? parseMoney(String text, [String code = defaultCurrency]) {
  final c = currencyOf(code);
  var cleaned = text.trim();
  final symbol = c.symbol.trim().toLowerCase();
  final lower = cleaned.toLowerCase();
  if (lower.startsWith(symbol)) {
    cleaned = cleaned.substring(symbol.length);
  } else if (lower.startsWith(c.code.toLowerCase())) {
    cleaned = cleaned.substring(c.code.length);
  }
  cleaned = cleaned.replaceAll(RegExp(r'[,\s]'), '');
  final m =
      (c.digits == 0 ? RegExp(r'^(\d+)$') : RegExp(r'^(\d+)(?:\.(\d{1,2}))?$'))
          .firstMatch(cleaned);
  if (m == null) return null;
  final whole = int.tryParse(m.group(1) ?? '');
  if (whole == null) return null;
  final int minor;
  if (c.digits == 0) {
    minor = whole;
  } else {
    final frac = (m.group(2) ?? '').padRight(2, '0');
    minor = whole * 100 + (int.tryParse(frac.isEmpty ? '0' : frac) ?? 0);
  }
  return minor > maxMinor ? null : minor;
}
