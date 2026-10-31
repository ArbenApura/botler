// CURRENCIES: THE CATALOGUE OF ISO 4217 CODES (BTL-20261022-0218, ADR 2; BTL-20261023-1407). AMOUNTS ARE ALWAYS INTEGERS IN THE CURRENCY'S MINOR UNIT (CENTAVOS, CENTS, YEN, FILS).
// A float never holds an amount. A person has a main currency and each account wallet has its own; changing the main currency relabels the money plan, it never converts it.
// The cap of money.ts (a safe integer) holds for every currency.

// -- MODULES -- //
import { isMinorAmount } from './money';

// -- TYPES -- //

export type Currency = {
	/** ISO 4217 code. */
	code: string;
	/** What is written in front of an amount. A symbol belongs to one currency alone; the others are written with their code. */
	symbol: string;
	/** Digits after the decimal point: 2 for centavos and cents, 0 for yen and won, 3 for dinars of Kuwait and Bahrain. */
	digits: 0 | 2 | 3;
	name: string;
	/** About what 2,000 pesos is worth, in whole units of this currency, for the size of a balance change that must be confirmed. */
	confirmMajor: number;
};

// -- CONSTANTS -- //

export const DEFAULT_CURRENCY = 'PHP';

/**
 * The other active ISO 4217 currencies: code, symbol ('' writes the code), digits, roughly how many it takes to buy one US dollar, name.
 * The rate is only a reference for the size of a balance change that must be confirmed (35 dollars worth, like 2,000 pesos); the real
 * rates are fetched and stored (finance/fx.ts). A symbol is only given when it belongs to one currency alone.
 */
const EXTRA: readonly (readonly [string, string, 0 | 2 | 3, number, string])[] = [
	['AFN', '', 2, 70, 'Afghan afghani'],
	['ALL', '', 2, 92, 'Albanian lek'],
	['AMD', '', 2, 390, 'Armenian dram'],
	['ANG', '', 2, 1.79, 'Netherlands Antillean guilder'],
	['AOA', '', 2, 920, 'Angolan kwanza'],
	['ARS', '', 2, 1000, 'Argentine peso'],
	['AWG', '', 2, 1.79, 'Aruban florin'],
	['AZN', '₼', 2, 1.7, 'Azerbaijani manat'],
	['BAM', '', 2, 1.8, 'Bosnia-Herzegovina convertible mark'],
	['BBD', '', 2, 2, 'Barbadian dollar'],
	['BDT', '৳', 2, 120, 'Bangladeshi taka'],
	['BGN', '', 2, 1.8, 'Bulgarian lev'],
	['BHD', '', 3, 0.376, 'Bahraini dinar'],
	['BIF', '', 0, 2900, 'Burundian franc'],
	['BMD', '', 2, 1, 'Bermudian dollar'],
	['BND', '', 2, 1.3, 'Brunei dollar'],
	['BOB', '', 2, 6.9, 'Bolivian boliviano'],
	['BRL', 'R$', 2, 5.5, 'Brazilian real'],
	['BSD', '', 2, 1, 'Bahamian dollar'],
	['BTN', '', 2, 84, 'Bhutanese ngultrum'],
	['BWP', '', 2, 13.5, 'Botswana pula'],
	['BYN', '', 2, 3.3, 'Belarusian ruble'],
	['BZD', '', 2, 2, 'Belize dollar'],
	['CDF', '', 2, 2800, 'Congolese franc'],
	['CLP', '', 0, 950, 'Chilean peso'],
	['COP', '', 2, 4100, 'Colombian peso'],
	['CRC', '₡', 2, 510, 'Costa Rican colón'],
	['CUP', '', 2, 24, 'Cuban peso'],
	['CVE', '', 2, 101, 'Cape Verdean escudo'],
	['CZK', 'Kč', 2, 23, 'Czech koruna'],
	['DJF', '', 0, 178, 'Djiboutian franc'],
	['DKK', '', 2, 6.9, 'Danish krone'],
	['DOP', '', 2, 60, 'Dominican peso'],
	['DZD', '', 2, 134, 'Algerian dinar'],
	['EGP', 'E£', 2, 49, 'Egyptian pound'],
	['ERN', '', 2, 15, 'Eritrean nakfa'],
	['ETB', '', 2, 120, 'Ethiopian birr'],
	['FJD', '', 2, 2.25, 'Fijian dollar'],
	['FKP', '', 2, 0.78, 'Falkland Islands pound'],
	['GEL', '₾', 2, 2.7, 'Georgian lari'],
	['GHS', '', 2, 15, 'Ghanaian cedi'],
	['GIP', '', 2, 0.78, 'Gibraltar pound'],
	['GMD', '', 2, 70, 'Gambian dalasi'],
	['GNF', '', 0, 8600, 'Guinean franc'],
	['GTQ', '', 2, 7.7, 'Guatemalan quetzal'],
	['GYD', '', 2, 209, 'Guyanese dollar'],
	['HNL', '', 2, 25, 'Honduran lempira'],
	['HTG', '', 2, 131, 'Haitian gourde'],
	['HUF', 'Ft', 2, 360, 'Hungarian forint'],
	['ILS', '₪', 2, 3.7, 'Israeli new shekel'],
	['IQD', '', 3, 1310, 'Iraqi dinar'],
	['IRR', '', 2, 42000, 'Iranian rial'],
	['ISK', '', 0, 138, 'Icelandic króna'],
	['JMD', '', 2, 157, 'Jamaican dollar'],
	['JOD', '', 3, 0.71, 'Jordanian dinar'],
	['KES', '', 2, 129, 'Kenyan shilling'],
	['KGS', '', 2, 86, 'Kyrgyzstani som'],
	['KHR', '៛', 2, 4050, 'Cambodian riel'],
	['KMF', '', 0, 450, 'Comorian franc'],
	['KPW', '', 2, 900, 'North Korean won'],
	['KWD', '', 3, 0.307, 'Kuwaiti dinar'],
	['KYD', '', 2, 0.83, 'Cayman Islands dollar'],
	['KZT', '₸', 2, 480, 'Kazakhstani tenge'],
	['LAK', '₭', 2, 22000, 'Lao kip'],
	['LBP', '', 2, 89500, 'Lebanese pound'],
	['LKR', '', 2, 295, 'Sri Lankan rupee'],
	['LRD', '', 2, 190, 'Liberian dollar'],
	['LSL', '', 2, 18, 'Lesotho loti'],
	['LYD', '', 3, 4.8, 'Libyan dinar'],
	['MAD', '', 2, 9.9, 'Moroccan dirham'],
	['MDL', '', 2, 17.8, 'Moldovan leu'],
	['MGA', '', 2, 4500, 'Malagasy ariary'],
	['MKD', '', 2, 56, 'Macedonian denar'],
	['MMK', '', 2, 2100, 'Myanmar kyat'],
	['MNT', '₮', 2, 3400, 'Mongolian tögrög'],
	['MOP', '', 2, 8, 'Macanese pataca'],
	['MRU', '', 2, 40, 'Mauritanian ouguiya'],
	['MUR', '', 2, 46, 'Mauritian rupee'],
	['MVR', '', 2, 15.4, 'Maldivian rufiyaa'],
	['MWK', '', 2, 1740, 'Malawian kwacha'],
	['MXN', 'Mex$', 2, 18, 'Mexican peso'],
	['MZN', '', 2, 64, 'Mozambican metical'],
	['NAD', '', 2, 18, 'Namibian dollar'],
	['NGN', '₦', 2, 1600, 'Nigerian naira'],
	['NIO', '', 2, 36.8, 'Nicaraguan córdoba'],
	['NOK', '', 2, 11, 'Norwegian krone'],
	['NPR', '', 2, 134, 'Nepalese rupee'],
	['OMR', '', 3, 0.385, 'Omani rial'],
	['PAB', '', 2, 1, 'Panamanian balboa'],
	['PEN', '', 2, 3.75, 'Peruvian sol'],
	['PGK', '', 2, 4, 'Papua New Guinean kina'],
	['PKR', '', 2, 278, 'Pakistani rupee'],
	['PLN', 'zł', 2, 4, 'Polish złoty'],
	['PYG', '₲', 0, 7800, 'Paraguayan guaraní'],
	['QAR', '', 2, 3.64, 'Qatari riyal'],
	['RON', '', 2, 4.6, 'Romanian leu'],
	['RSD', '', 2, 108, 'Serbian dinar'],
	['RUB', '₽', 2, 90, 'Russian ruble'],
	['RWF', '', 0, 1370, 'Rwandan franc'],
	['SBD', '', 2, 8.4, 'Solomon Islands dollar'],
	['SCR', '', 2, 13.5, 'Seychellois rupee'],
	['SDG', '', 2, 600, 'Sudanese pound'],
	['SEK', '', 2, 10.6, 'Swedish krona'],
	['SHP', '', 2, 0.78, 'Saint Helena pound'],
	['SLE', '', 2, 22.7, 'Sierra Leonean leone'],
	['SOS', '', 2, 571, 'Somali shilling'],
	['SRD', '', 2, 36, 'Surinamese dollar'],
	['SSP', '', 2, 4500, 'South Sudanese pound'],
	['STN', '', 2, 22.5, 'São Tomé and Príncipe dobra'],
	['SVC', '', 2, 8.75, 'Salvadoran colón'],
	['SYP', '', 2, 13000, 'Syrian pound'],
	['SZL', '', 2, 18, 'Swazi lilangeni'],
	['TJS', '', 2, 10.7, 'Tajikistani somoni'],
	['TMT', '', 2, 3.5, 'Turkmenistan manat'],
	['TND', '', 3, 3.1, 'Tunisian dinar'],
	['TOP', '', 2, 2.4, 'Tongan paʻanga'],
	['TRY', '₺', 2, 34, 'Turkish lira'],
	['TTD', '', 2, 6.8, 'Trinidad and Tobago dollar'],
	['TZS', '', 2, 2700, 'Tanzanian shilling'],
	['UAH', '₴', 2, 41, 'Ukrainian hryvnia'],
	['UGX', '', 0, 3700, 'Ugandan shilling'],
	['UYU', '', 2, 41, 'Uruguayan peso'],
	['UZS', '', 2, 12800, 'Uzbekistani soʻm'],
	['VES', '', 2, 40, 'Venezuelan bolívar'],
	['VUV', '', 0, 119, 'Vanuatu vatu'],
	['WST', '', 2, 2.8, 'Samoan tālā'],
	['XAF', '', 0, 600, 'Central African CFA franc'],
	['XCD', '', 2, 2.7, 'East Caribbean dollar'],
	['XOF', '', 0, 600, 'West African CFA franc'],
	['XPF', '', 0, 110, 'CFP franc'],
	['YER', '', 2, 250, 'Yemeni rial'],
	['ZAR', '', 2, 18, 'South African rand'],
	['ZMW', '', 2, 26, 'Zambian kwacha'],
	['ZWG', '', 2, 26, 'Zimbabwe Gold']
];

/** The catalogue. Every code here is valid in the database check and the settings. */
export const CURRENCIES: readonly Currency[] = [
	{ code: 'PHP', symbol: '₱', digits: 2, name: 'Philippine peso', confirmMajor: 2000 },
	{ code: 'USD', symbol: '$', digits: 2, name: 'US dollar', confirmMajor: 35 },
	{ code: 'EUR', symbol: '€', digits: 2, name: 'Euro', confirmMajor: 32 },
	{ code: 'GBP', symbol: '£', digits: 2, name: 'Pound sterling', confirmMajor: 27 },
	{ code: 'JPY', symbol: '¥', digits: 0, name: 'Japanese yen', confirmMajor: 5500 },
	{ code: 'KRW', symbol: '₩', digits: 0, name: 'South Korean won', confirmMajor: 48000 },
	{ code: 'CNY', symbol: 'CN¥', digits: 2, name: 'Chinese yuan', confirmMajor: 250 },
	{ code: 'HKD', symbol: 'HK$', digits: 2, name: 'Hong Kong dollar', confirmMajor: 270 },
	{ code: 'SGD', symbol: 'S$', digits: 2, name: 'Singapore dollar', confirmMajor: 47 },
	{ code: 'AUD', symbol: 'A$', digits: 2, name: 'Australian dollar', confirmMajor: 53 },
	{ code: 'NZD', symbol: 'NZ$', digits: 2, name: 'New Zealand dollar', confirmMajor: 58 },
	{ code: 'CAD', symbol: 'C$', digits: 2, name: 'Canadian dollar', confirmMajor: 48 },
	{ code: 'CHF', symbol: 'CHF ', digits: 2, name: 'Swiss franc', confirmMajor: 31 },
	{ code: 'INR', symbol: '₹', digits: 2, name: 'Indian rupee', confirmMajor: 2900 },
	{ code: 'IDR', symbol: 'Rp', digits: 2, name: 'Indonesian rupiah', confirmMajor: 560000 },
	{ code: 'MYR', symbol: 'RM', digits: 2, name: 'Malaysian ringgit', confirmMajor: 155 },
	{ code: 'THB', symbol: '฿', digits: 2, name: 'Thai baht', confirmMajor: 1200 },
	{ code: 'VND', symbol: '₫', digits: 0, name: 'Vietnamese dong', confirmMajor: 880000 },
	{ code: 'TWD', symbol: 'NT$', digits: 2, name: 'New Taiwan dollar', confirmMajor: 1100 },
	{ code: 'AED', symbol: 'AED ', digits: 2, name: 'UAE dirham', confirmMajor: 130 },
	{ code: 'SAR', symbol: 'SAR ', digits: 2, name: 'Saudi riyal', confirmMajor: 130 },
	...EXTRA.map(([code, symbol, digits, perUsd, name]) => ({
		code,
		symbol: symbol || `${code} `,
		digits,
		name,
		confirmMajor: Math.max(1, Math.round(35 * perUsd))
	}))
];

export const CURRENCY_CODES = CURRENCIES.map((c) => c.code);

// -- FUNCTIONS -- //

export const isCurrencyCode = (code: string): boolean => CURRENCIES.some((c) => c.code === code);

/** The currency of a code. An unknown code is a bug, so it throws instead of falling back to pesos. */
export function currencyOf(code: string): Currency {
	const found = CURRENCIES.find((c) => c.code === code);
	if (!found) throw new RangeError(`Unknown currency: ${code}`);
	return found;
}

/** How many minor units make one major unit: 100 for pesos, 1 for yen, 1000 for Kuwaiti dinars. */
export const minorPerMajor = (code: string): number => 10 ** currencyOf(code).digits;

const group = (whole: string) => whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',');

/** The whole part and the fraction of a non negative minor amount, by integer arithmetic only. */
function split(abs: number, digits: number): { whole: string; frac: string } {
	if (digits === 0) return { whole: String(abs), frac: '' };
	const per = 10 ** digits;
	const rest = abs % per;
	return { whole: String((abs - rest) / per), frac: String(rest).padStart(digits, '0') };
}

/** ₱1,234.50, $1,234.50 or ¥1,234, with a minus sign for a negative amount. Built from integers, so it is exact. */
export function formatMoney(minor: number, code: string = DEFAULT_CURRENCY): string {
	if (!Number.isSafeInteger(minor)) throw new RangeError('Not an amount in minor units');
	const c = currencyOf(code);
	const sign = minor < 0 ? '-' : '';
	const { whole, frac } = split(Math.abs(minor), c.digits);
	return `${sign}${c.symbol}${group(whole)}${frac ? `.${frac}` : ''}`;
}

/** The amount for a text field, without the symbol: 18000 PHP is 180.00 and 180 JPY is 180. */
export function plainAmount(minor: number, code: string = DEFAULT_CURRENCY): string {
	const c = currencyOf(code);
	const sign = minor < 0 ? '-' : '';
	const { whole, frac } = split(Math.abs(minor), c.digits);
	return `${sign}${whole}${frac ? `.${frac}` : ''}`;
}

// A currency symbol or code before the digits, which a person may or may not type
const escapeRe = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * The number part of an amount ("1,250.50", "12,50", "180") as minor units of a currency with this many decimals.
 * A lone comma followed by exactly the currency's decimals is a decimal mark; commas in groups of three are thousands;
 * a text that fits both readings, extra decimals, or a number beyond the safe range is null. Never goes through a float.
 */
export function parseDecimalText(raw: string, digits: number): number | null {
	let whole: string;
	let frac = '';
	if (!raw.includes(',')) {
		const m = /^(\d+)(?:\.(\d+))?$/.exec(raw);
		if (!m) return null;
		whole = m[1] as string;
		frac = m[2] ?? '';
	} else if (raw.includes('.')) {
		// A dot and commas: the commas are thousands and the dot is the decimal mark
		const m = /^(\d{1,3}(?:,\d{3})+)\.(\d+)$/.exec(raw);
		if (!m) return null;
		whole = (m[1] as string).replaceAll(',', '');
		frac = m[2] as string;
	} else {
		const parts = raw.split(',');
		if (parts.length > 2) {
			if (!/^\d{1,3}(?:,\d{3})+$/.test(raw)) return null;
			whole = parts.join('');
		} else {
			const [a, b] = parts as [string, string];
			if (!/^\d+$/.test(a) || !/^\d+$/.test(b)) return null;
			const asThousands = a.length <= 3 && b.length === 3;
			const asDecimal = digits > 0 && b.length === digits;
			// Both readings fit (1,250 in a three digit currency): refuse instead of guessing
			if (asThousands && asDecimal) return null;
			if (asThousands) whole = a + b;
			else if (asDecimal) {
				whole = a;
				frac = b;
			} else return null;
		}
	}
	// More decimals than the currency has are never cut off
	if (frac.length > digits) return null;
	const minor = Number(whole + frac.padEnd(digits, '0'));
	return isMinorAmount(minor) ? minor : null;
}

/**
 * What a person typed ("180", "1,250.50", "12,50", "$ 90", "usd 5") as minor units, or null when it is not an amount of this currency.
 * A currency with no decimals refuses a decimal part. Never goes through a float.
 */
export function parseMoney(text: string, code: string = DEFAULT_CURRENCY): number | null {
	const c = currencyOf(code);
	const prefix = new RegExp(`^(?:${escapeRe(c.symbol.trim())}|${c.code})`, 'i');
	const cleaned = text.trim().replace(prefix, '').replace(/\s/g, '');
	return parseDecimalText(cleaned, c.digits);
}

/** The size of a balance change that must be confirmed, in this currency's minor units (2,000 pesos worth). */
export function balanceConfirmThreshold(code: string = DEFAULT_CURRENCY): number {
	const c = currencyOf(code);
	return c.confirmMajor * 10 ** c.digits;
}
