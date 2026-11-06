// A MOVE INTO A CASH ACCOUNT FOR SPENDING GETS A HINT, AND A WRITE HANDS BACK THE ID UNDO TAKES (BTL-20261106-1502)

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { spendingTransferHint } from '../../src/lib/server/ops/ledger';

// -- TESTS -- //

describe('spendingTransferHint', () => {
	it('asks when money goes to a cash account for pocket money', () => {
		expect(spendingTransferHint('cash', 'ATM withdrawal for pocket money')).toContain('expense');
		expect(spendingTransferHint('cash', 'weekly allowance')).not.toBeNull();
	});
	it('says nothing for an explicit stash, another kind of account, or a plain note', () => {
		expect(spendingTransferHint('cash', 'move to my cash stash')).toBeNull();
		expect(spendingTransferHint('cash', 'keep pocket money in the safe')).toBeNull();
		expect(spendingTransferHint('bank', 'ATM withdrawal for pocket money')).toBeNull();
		expect(spendingTransferHint('cash', '')).toBeNull();
	});
});
