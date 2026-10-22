// MONEY: PHP AS INTEGER CENTAVOS EVERYWHERE. A FLOAT NEVER HOLDS AN AMOUNT. PESOS ARE ONLY READ FROM TEXT AT THE EDGE AND SHOWN AS TEXT.

// -- CONSTANTS -- //

/** The largest amount a column can hold (a 32 bit integer), about 21 million pesos. */
export const MAX_CENTAVOS = 2_147_483_647;

// -- FUNCTIONS -- //

export const isCentavos = (n: unknown): n is number =>
	typeof n === 'number' && Number.isSafeInteger(n) && Math.abs(n) <= MAX_CENTAVOS;

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
