// THE LEDGER MODEL (decision, P2.7)
// - Types: income (+ the account), expense (- the account), refund (+ the account), transfer (- the source and its fee, + the destination),
//   adjustment (signed, the difference found when a real balance is counted).
// - Balance = the latest snapshot of the account plus the signed effect of every transaction after it. No snapshot counts as zero.
// - A transfer between own accounts is never spending. Its fee is. Spending is expenses plus fees minus refunds.
// - Drift = counted balance minus expected balance, stored as a signed adjustment. It is shown as untracked spending only when negative.

// -- TYPES -- //

export type TxnType = 'income' | 'expense' | 'transfer' | 'refund' | 'adjustment';

export type Txn = {
	type: TxnType;
	accountId: string;
	/** The destination of a transfer. */
	toAccountId?: string | null;
	/** Centavos. Above zero for every type but an adjustment, which is signed. */
	amount: number;
	/** Charged to the source account of a transfer. */
	fee?: number;
	occurredAt: Date;
	voided?: boolean;
};

export type Snapshot = { amount: number; takenAt: Date };

// -- CONSTANTS -- //

export const TXN_TYPES = ['income', 'expense', 'transfer', 'refund', 'adjustment'] as const;

// -- FUNCTIONS -- //

/** How one transaction changes one account's balance. */
export function effectOn(t: Txn, accountId: string): number {
	if (t.voided) return 0;
	const fee = t.fee ?? 0;
	switch (t.type) {
		case 'income':
		case 'refund':
			return t.accountId === accountId ? t.amount : 0;
		case 'expense':
			return t.accountId === accountId ? -t.amount : 0;
		case 'adjustment':
			return t.accountId === accountId ? t.amount : 0;
		case 'transfer': {
			let delta = 0;
			if (t.accountId === accountId) delta -= t.amount + fee;
			if (t.toAccountId === accountId) delta += t.amount;
			return delta;
		}
	}
}

/** The balance of an account: the latest snapshot plus what happened after it. `txns` may hold other accounts' rows. */
export function balanceOf(
	accountId: string,
	snapshot: Snapshot | null,
	txns: readonly Txn[]
): number {
	let balance = snapshot?.amount ?? 0;
	const since = snapshot?.takenAt.getTime() ?? -Infinity;
	for (const t of txns) {
		if (t.occurredAt.getTime() > since) balance += effectOn(t, accountId);
	}
	return balance;
}

/** Counted minus expected. Negative means money went somewhere that was not recorded. */
export const driftOf = (expected: number, counted: number): number => counted - expected;

/** What was spent in a set of transactions: expenses and transfer fees, less refunds. Transfers themselves are not spending. */
export function spendingOf(txns: readonly Txn[]): number {
	let total = 0;
	for (const t of txns) {
		if (t.voided) continue;
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
