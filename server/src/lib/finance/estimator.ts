// THE VARIABLE BILL ESTIMATOR (decision, P2.9)
// - Window: the latest 6 payments. Fewer than 3 is a cold start: the bill is flagged unknown and the person is asked for an
//   estimate (their answer is used until 3 payments exist).
// - Estimate: the median, after dropping outliers. An outlier is a payment more than 3 times, or less than a third of, the median
//   (a one off double bill or a missed month). The median of what is left is the estimate, rounded to the centavo.

// -- TYPES -- //

export type Estimate = {
	/** Centavos, or null when the bill is unknown and the person must be asked. */
	amount: number | null;
	unknown: boolean;
	basis: 'history' | 'user' | 'none';
	used: number;
	dropped: number;
};

// -- CONSTANTS -- //

export const ESTIMATE_WINDOW = 6;
export const ESTIMATE_MIN_SAMPLES = 3;
const OUTLIER_FACTOR = 3;

// -- FUNCTIONS -- //

/** The median of integers, the two middle values averaged and rounded when the count is even. */
export function median(values: readonly number[]): number {
	if (values.length === 0) throw new RangeError('The median of nothing');
	const sorted = [...values].sort((a, b) => a - b);
	const mid = Math.floor(sorted.length / 2);
	const hi = sorted[mid] as number;
	if (sorted.length % 2 === 1) return hi;
	return Math.round(((sorted[mid - 1] as number) + hi) / 2);
}

/** `history` is the amounts paid so far, newest first, in centavos. `userEstimate` is what the person said when asked. */
export function estimateBill(history: readonly number[], userEstimate?: number | null): Estimate {
	const recent = history.filter((n) => Number.isInteger(n) && n > 0).slice(0, ESTIMATE_WINDOW);
	if (recent.length < ESTIMATE_MIN_SAMPLES) {
		if (userEstimate && userEstimate > 0)
			return { amount: userEstimate, unknown: false, basis: 'user', used: 0, dropped: 0 };
		return { amount: null, unknown: true, basis: 'none', used: 0, dropped: 0 };
	}
	const m = median(recent);
	const kept = recent.filter((n) => n <= m * OUTLIER_FACTOR && n * OUTLIER_FACTOR >= m);
	// Every value is an outlier only when the median itself is odd out, which cannot happen with a median of the same values
	const use = kept.length > 0 ? kept : recent;
	return {
		amount: median(use),
		unknown: false,
		basis: 'history',
		used: use.length,
		dropped: recent.length - use.length
	};
}
