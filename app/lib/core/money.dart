// MONEY IN THE APP: INTEGERS IN THE MINOR UNIT OF THE PERSON'S CURRENCY EVERYWHERE (CENTAVOS, CENTS, YEN). A FLOAT NEVER HOLDS AN AMOUNT.
// The currencies are the server's catalogue (server/src/lib/finance/currency.ts; scripts/currencies-dart.ts prints this list). A person has a main currency and each account wallet has its own; changing the main currency relabels the plan, it never converts.

// -- TYPES -- //

class Currency {
  const Currency(this.code, this.symbol, this.digits, this.name);

  /// ISO 4217 code.
  final String code;

  /// What is written in front of an amount.
  final String symbol;

  /// Digits after the decimal point: 2 for centavos and cents, 0 for yen and won, 3 for dinars of Kuwait and Bahrain.
  final int digits;
  final String name;
}

// -- CONSTANTS -- //

const String defaultCurrency = 'PHP';

/// The server holds amounts in a 64 bit column and reads them as safe integers (2^53 - 1), the same cap as the server.
const int maxMinor = 9007199254740991;

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
  Currency('AFN', 'AFN ', 2, 'Afghan afghani'),
  Currency('ALL', 'ALL ', 2, 'Albanian lek'),
  Currency('AMD', 'AMD ', 2, 'Armenian dram'),
  Currency('ANG', 'ANG ', 2, 'Netherlands Antillean guilder'),
  Currency('AOA', 'AOA ', 2, 'Angolan kwanza'),
  Currency('ARS', 'ARS ', 2, 'Argentine peso'),
  Currency('AWG', 'AWG ', 2, 'Aruban florin'),
  Currency('AZN', '₼', 2, 'Azerbaijani manat'),
  Currency('BAM', 'BAM ', 2, 'Bosnia-Herzegovina convertible mark'),
  Currency('BBD', 'BBD ', 2, 'Barbadian dollar'),
  Currency('BDT', '৳', 2, 'Bangladeshi taka'),
  Currency('BGN', 'BGN ', 2, 'Bulgarian lev'),
  Currency('BHD', 'BHD ', 3, 'Bahraini dinar'),
  Currency('BIF', 'BIF ', 0, 'Burundian franc'),
  Currency('BMD', 'BMD ', 2, 'Bermudian dollar'),
  Currency('BND', 'BND ', 2, 'Brunei dollar'),
  Currency('BOB', 'BOB ', 2, 'Bolivian boliviano'),
  Currency('BRL', r'R$', 2, 'Brazilian real'),
  Currency('BSD', 'BSD ', 2, 'Bahamian dollar'),
  Currency('BTN', 'BTN ', 2, 'Bhutanese ngultrum'),
  Currency('BWP', 'BWP ', 2, 'Botswana pula'),
  Currency('BYN', 'BYN ', 2, 'Belarusian ruble'),
  Currency('BZD', 'BZD ', 2, 'Belize dollar'),
  Currency('CDF', 'CDF ', 2, 'Congolese franc'),
  Currency('CLP', 'CLP ', 0, 'Chilean peso'),
  Currency('COP', 'COP ', 2, 'Colombian peso'),
  Currency('CRC', '₡', 2, 'Costa Rican colón'),
  Currency('CUP', 'CUP ', 2, 'Cuban peso'),
  Currency('CVE', 'CVE ', 2, 'Cape Verdean escudo'),
  Currency('CZK', 'Kč', 2, 'Czech koruna'),
  Currency('DJF', 'DJF ', 0, 'Djiboutian franc'),
  Currency('DKK', 'DKK ', 2, 'Danish krone'),
  Currency('DOP', 'DOP ', 2, 'Dominican peso'),
  Currency('DZD', 'DZD ', 2, 'Algerian dinar'),
  Currency('EGP', 'E£', 2, 'Egyptian pound'),
  Currency('ERN', 'ERN ', 2, 'Eritrean nakfa'),
  Currency('ETB', 'ETB ', 2, 'Ethiopian birr'),
  Currency('FJD', 'FJD ', 2, 'Fijian dollar'),
  Currency('FKP', 'FKP ', 2, 'Falkland Islands pound'),
  Currency('GEL', '₾', 2, 'Georgian lari'),
  Currency('GHS', 'GHS ', 2, 'Ghanaian cedi'),
  Currency('GIP', 'GIP ', 2, 'Gibraltar pound'),
  Currency('GMD', 'GMD ', 2, 'Gambian dalasi'),
  Currency('GNF', 'GNF ', 0, 'Guinean franc'),
  Currency('GTQ', 'GTQ ', 2, 'Guatemalan quetzal'),
  Currency('GYD', 'GYD ', 2, 'Guyanese dollar'),
  Currency('HNL', 'HNL ', 2, 'Honduran lempira'),
  Currency('HTG', 'HTG ', 2, 'Haitian gourde'),
  Currency('HUF', 'Ft', 2, 'Hungarian forint'),
  Currency('ILS', '₪', 2, 'Israeli new shekel'),
  Currency('IQD', 'IQD ', 3, 'Iraqi dinar'),
  Currency('IRR', 'IRR ', 2, 'Iranian rial'),
  Currency('ISK', 'ISK ', 0, 'Icelandic króna'),
  Currency('JMD', 'JMD ', 2, 'Jamaican dollar'),
  Currency('JOD', 'JOD ', 3, 'Jordanian dinar'),
  Currency('KES', 'KES ', 2, 'Kenyan shilling'),
  Currency('KGS', 'KGS ', 2, 'Kyrgyzstani som'),
  Currency('KHR', '៛', 2, 'Cambodian riel'),
  Currency('KMF', 'KMF ', 0, 'Comorian franc'),
  Currency('KPW', 'KPW ', 2, 'North Korean won'),
  Currency('KWD', 'KWD ', 3, 'Kuwaiti dinar'),
  Currency('KYD', 'KYD ', 2, 'Cayman Islands dollar'),
  Currency('KZT', '₸', 2, 'Kazakhstani tenge'),
  Currency('LAK', '₭', 2, 'Lao kip'),
  Currency('LBP', 'LBP ', 2, 'Lebanese pound'),
  Currency('LKR', 'LKR ', 2, 'Sri Lankan rupee'),
  Currency('LRD', 'LRD ', 2, 'Liberian dollar'),
  Currency('LSL', 'LSL ', 2, 'Lesotho loti'),
  Currency('LYD', 'LYD ', 3, 'Libyan dinar'),
  Currency('MAD', 'MAD ', 2, 'Moroccan dirham'),
  Currency('MDL', 'MDL ', 2, 'Moldovan leu'),
  Currency('MGA', 'MGA ', 2, 'Malagasy ariary'),
  Currency('MKD', 'MKD ', 2, 'Macedonian denar'),
  Currency('MMK', 'MMK ', 2, 'Myanmar kyat'),
  Currency('MNT', '₮', 2, 'Mongolian tögrög'),
  Currency('MOP', 'MOP ', 2, 'Macanese pataca'),
  Currency('MRU', 'MRU ', 2, 'Mauritanian ouguiya'),
  Currency('MUR', 'MUR ', 2, 'Mauritian rupee'),
  Currency('MVR', 'MVR ', 2, 'Maldivian rufiyaa'),
  Currency('MWK', 'MWK ', 2, 'Malawian kwacha'),
  Currency('MXN', r'Mex$', 2, 'Mexican peso'),
  Currency('MZN', 'MZN ', 2, 'Mozambican metical'),
  Currency('NAD', 'NAD ', 2, 'Namibian dollar'),
  Currency('NGN', '₦', 2, 'Nigerian naira'),
  Currency('NIO', 'NIO ', 2, 'Nicaraguan córdoba'),
  Currency('NOK', 'NOK ', 2, 'Norwegian krone'),
  Currency('NPR', 'NPR ', 2, 'Nepalese rupee'),
  Currency('OMR', 'OMR ', 3, 'Omani rial'),
  Currency('PAB', 'PAB ', 2, 'Panamanian balboa'),
  Currency('PEN', 'PEN ', 2, 'Peruvian sol'),
  Currency('PGK', 'PGK ', 2, 'Papua New Guinean kina'),
  Currency('PKR', 'PKR ', 2, 'Pakistani rupee'),
  Currency('PLN', 'zł', 2, 'Polish złoty'),
  Currency('PYG', '₲', 0, 'Paraguayan guaraní'),
  Currency('QAR', 'QAR ', 2, 'Qatari riyal'),
  Currency('RON', 'RON ', 2, 'Romanian leu'),
  Currency('RSD', 'RSD ', 2, 'Serbian dinar'),
  Currency('RUB', '₽', 2, 'Russian ruble'),
  Currency('RWF', 'RWF ', 0, 'Rwandan franc'),
  Currency('SBD', 'SBD ', 2, 'Solomon Islands dollar'),
  Currency('SCR', 'SCR ', 2, 'Seychellois rupee'),
  Currency('SDG', 'SDG ', 2, 'Sudanese pound'),
  Currency('SEK', 'SEK ', 2, 'Swedish krona'),
  Currency('SHP', 'SHP ', 2, 'Saint Helena pound'),
  Currency('SLE', 'SLE ', 2, 'Sierra Leonean leone'),
  Currency('SOS', 'SOS ', 2, 'Somali shilling'),
  Currency('SRD', 'SRD ', 2, 'Surinamese dollar'),
  Currency('SSP', 'SSP ', 2, 'South Sudanese pound'),
  Currency('STN', 'STN ', 2, 'São Tomé and Príncipe dobra'),
  Currency('SVC', 'SVC ', 2, 'Salvadoran colón'),
  Currency('SYP', 'SYP ', 2, 'Syrian pound'),
  Currency('SZL', 'SZL ', 2, 'Swazi lilangeni'),
  Currency('TJS', 'TJS ', 2, 'Tajikistani somoni'),
  Currency('TMT', 'TMT ', 2, 'Turkmenistan manat'),
  Currency('TND', 'TND ', 3, 'Tunisian dinar'),
  Currency('TOP', 'TOP ', 2, 'Tongan paʻanga'),
  Currency('TRY', '₺', 2, 'Turkish lira'),
  Currency('TTD', 'TTD ', 2, 'Trinidad and Tobago dollar'),
  Currency('TZS', 'TZS ', 2, 'Tanzanian shilling'),
  Currency('UAH', '₴', 2, 'Ukrainian hryvnia'),
  Currency('UGX', 'UGX ', 0, 'Ugandan shilling'),
  Currency('UYU', 'UYU ', 2, 'Uruguayan peso'),
  Currency('UZS', 'UZS ', 2, 'Uzbekistani soʻm'),
  Currency('VES', 'VES ', 2, 'Venezuelan bolívar'),
  Currency('VUV', 'VUV ', 0, 'Vanuatu vatu'),
  Currency('WST', 'WST ', 2, 'Samoan tālā'),
  Currency('XAF', 'XAF ', 0, 'Central African CFA franc'),
  Currency('XCD', 'XCD ', 2, 'East Caribbean dollar'),
  Currency('XOF', 'XOF ', 0, 'West African CFA franc'),
  Currency('XPF', 'XPF ', 0, 'CFP franc'),
  Currency('YER', 'YER ', 2, 'Yemeni rial'),
  Currency('ZAR', 'ZAR ', 2, 'South African rand'),
  Currency('ZMW', 'ZMW ', 2, 'Zambian kwacha'),
  Currency('ZWG', 'ZWG ', 2, 'Zimbabwe Gold'),
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

/// How many minor units make one major unit: 100 for pesos, 1 for yen, 1000 for Kuwaiti dinars.
int minorPerMajor(String code) {
  var per = 1;
  for (var i = 0; i < currencyOf(code).digits; i++) {
    per *= 10;
  }
  return per;
}

/// ₱1,234.50, $1,234.50 or ¥1,234, with a minus sign for a negative amount. Built from integers, so it is exact.
String formatMoney(int minor, [String code = defaultCurrency]) {
  final c = currencyOf(code);
  final abs = minor.abs();
  final sign = minor < 0 ? '-' : '';
  if (c.digits == 0) return '$sign${c.symbol}${_grouped(abs)}';
  final per = minorPerMajor(code);
  final frac = (abs % per).toString().padLeft(c.digits, '0');
  return '$sign${c.symbol}${_grouped(abs ~/ per)}.$frac';
}

/// The amount for a text field, without the symbol, for putting back in the field: 18000 PHP is "180.00" and 180 JPY is "180".
String plainAmount(int minor, [String code = defaultCurrency]) {
  final c = currencyOf(code);
  final abs = minor.abs();
  final sign = minor < 0 ? '-' : '';
  if (c.digits == 0) return '$sign$abs';
  final per = minorPerMajor(code);
  return '$sign${abs ~/ per}.${(abs % per).toString().padLeft(c.digits, '0')}';
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
      (c.digits == 0
              ? RegExp(r'^(\d+)$')
              : RegExp(r'^(\d+)(?:\.(\d{1,' + c.digits.toString() + r'}))?$'))
          .firstMatch(cleaned);
  if (m == null) return null;
  final whole = int.tryParse(m.group(1) ?? '');
  if (whole == null) return null;
  final int minor;
  if (c.digits == 0) {
    minor = whole;
  } else {
    final per = minorPerMajor(code);
    // A whole part this large cannot be multiplied without passing the cap
    if (whole > maxMinor ~/ per) return null;
    final frac = (m.group(2) ?? '').padRight(c.digits, '0');
    minor = whole * per + (int.tryParse(frac.isEmpty ? '0' : frac) ?? 0);
  }
  return minor > maxMinor ? null : minor;
}
