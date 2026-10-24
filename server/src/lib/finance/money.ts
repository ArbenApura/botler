// MONEY: PHP AS INTEGER CENTAVOS EVERYWHERE. A FLOAT NEVER HOLDS AN AMOUNT. PESOS ARE ONLY READ FROM TEXT AT THE EDGE AND SHOWN AS TEXT.

// -- CONSTANTS -- //

/** The largest amount a column can hold (a 64 bit column read back as a safe integer), enough for rupiah, dong and rial. */
export const MAX_MINOR = Number.MAX_SAFE_INTEGER;

/** The name the code used while amounts were 32 bit centavos; the same limit as MAX_MINOR. */
export const MAX_CENTAVOS = MAX_MINOR;

// -- FUNCTIONS -- //

export const isMinorAmount = (n: unknown): n is number =>
	typeof n === 'number' && Number.isSafeInteger(n) && Math.abs(n) <= MAX_MINOR;

/** The name the code used while amounts were centavos only. */
export const isCentavos = isMinorAmount;

/** Pesos typed by a person (180 or 180.5) to centavos, rounded to the nearest centavo. Used on input only. */
export function pesosToCentavos(pesos: number): number {
	const c = Math.round(pesos * 100);
	if (!isCentavos(c)) throw new RangeError('Amount is out of range');
	return c;
}

/** ₱1,234.50 with a minus sign for a negative amount. Built from integers, so it is exact. */
export function formatPhp(centavos: number): string {
	if (!Number.isSafeInteger(centavos)) throw new RangeError('Not an amount in centavos');
	const abs = Math.abs(centavos);
	const pesos = String(Math.trunc(abs / 100)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
	const cents = String(abs % 100).padStart(2, '0');
	return `${centavos < 0 ? '-' : ''}₱${pesos}.${cents}`;
}

/** floor(amount * numerator / denominator) in integers, without a float rounding step. */
export function mulDiv(amount: number, numerator: number, denominator: number): number {
	return Number((BigInt(amount) * BigInt(numerator)) / BigInt(denominator));
}
