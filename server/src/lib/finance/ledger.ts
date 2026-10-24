// THE LEDGER MODEL (decision, P2.7)
// - Types: income (+ the account), expense (- the account), refund (+ the account), transfer (- the source and its fee, + the destination),
//   adjustment (signed, the difference found when a real balance is counted).
// - Balance = the latest snapshot of the account's wallet (one currency) plus the signed effect of every transaction in that currency after it. No snapshot counts as zero.
// - An account holds one wallet per currency. A transfer between wallets of different currencies debits the source in its currency and credits to_amount, what really arrived, in the destination's.
// - A transfer between own accounts is never spending. Its fee is. Spending is expenses plus fees minus refunds.
// - Drift = counted balance minus expected balance, stored as a signed adjustment. It is shown as untracked spending only when negative.

// -- TYPES -- //

export type TxnType = 'income' | 'expense' | 'transfer' | 'refund' | 'adjustment';

export type Txn = {
	type: TxnType;
	accountId: string;
	/** The destination of a transfer. */
	toAccountId?: string | null;
	/** Minor units of currency. Above zero for every type but an adjustment, which is signed. */
	amount: number;
	/** The wallet it happens in. For a transfer, the source wallet. */
	currency: string;
	/** Charged to the source wallet of a transfer, in its currency. */
	fee?: number;
	/** A transfer: the currency it lands in (the source's own when it is not set) and what really arrived there (the amount when it is not set). */
	toCurrency?: string | null;
	toAmount?: number | null;
	occurredAt: Date;
	voided?: boolean;
};

/** A count of one wallet. The currency is only a label for the caller, who passes the snapshot of the wallet being added up. */
export type Snapshot = { amount: number; takenAt: Date; currency?: string };

// -- CONSTANTS -- //

export const TXN_TYPES = ['income', 'expense', 'transfer', 'refund', 'adjustment'] as const;

// -- FUNCTIONS -- //

/** How one transaction changes the balance of one wallet: an account in one currency. */
export function effectOn(t: Txn, accountId: string, currency: string): number {
	if (t.voided) return 0;
	const fee = t.fee ?? 0;
	const here = t.accountId === accountId && t.currency === currency;
	switch (t.type) {
		case 'income':
		case 'refund':
			return here ? t.amount : 0;
		case 'expense':
			return here ? -t.amount : 0;
		case 'adjustment':
			return here ? t.amount : 0;
		case 'transfer': {
			let delta = 0;
			if (here) delta -= t.amount + fee;
			if (t.toAccountId === accountId && (t.toCurrency ?? t.currency) === currency)
				delta += t.toAmount ?? t.amount;
			return delta;
		}
	}
}

/** The balance of a wallet: the latest snapshot of it plus what happened after. `txns` may hold other accounts' and currencies' rows. */
export function balanceOf(
	accountId: string,
	currency: string,
	snapshot: Snapshot | null,
	txns: readonly Txn[]
): number {
	let balance = snapshot?.amount ?? 0;
	const since = snapshot?.takenAt.getTime() ?? -Infinity;
	for (const t of txns) {
		if (t.occurredAt.getTime() > since) balance += effectOn(t, accountId, currency);
	}
	return balance;
}

/** Counted minus expected. Negative means money went somewhere that was not recorded. */
export const driftOf = (expected: number, counted: number): number => counted - expected;

/**
 * What was spent in a set of transactions of ONE currency: expenses and transfer fees, less refunds. Transfers themselves are not spending.
 * Rows of another currency are left out, never added in: amounts of different currencies are not a sum.
 */
export function spendingOf(txns: readonly Txn[], currency: string): number {
	let total = 0;
	for (const t of txns) {
		if (t.voided || t.currency !== currency) continue;
		if (t.type === 'expense') total += t.amount;
		else if (t.type === 'refund') total -= t.amount;
		else if (t.type === 'transfer') total += t.fee ?? 0;
	}
	return total;
}

/** The untracked spending shown for a set of drift adjustments: only the negative ones count, as a positive amount. */
export function untrackedSpendingOf(adjustments: readonly number[]): number {
	return adjustments.reduce((sum, a) => (a < 0 ? sum - a : sum), 0);
}
