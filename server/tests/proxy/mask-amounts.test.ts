// THE MASKER AND MONEY: LONG AMOUNTS IN MINOR UNITS, DATES WITH TIMES AND TIMES IN MILLISECONDS ARE NOT ACCOUNT NUMBERS; REAL ACCOUNT NUMBERS STILL ARE

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { createMasker } from '../../src/lib/server/proxy/mask';
import { peopleNames } from '../../src/lib/server/notebook/text';

// -- TESTS -- //

describe('amounts in tool results', () => {
	it('leaves a nine-digit amount under a money key alone', () => {
		const m = createMasker();
		const json = '{"amount":123456789,"balance":9876543210,"netTotal":-123456789012}';
		expect(m.mask(json)).toBe(json);
		expect(m.counts()).toEqual({});
	});

	it('leaves the amounts of a list and the minor unit keys alone', () => {
		const m = createMasker();
		const json =
			'{"expectedAmount":250000000,"amountMinor":1000000000,"holds":[{"amount":123456789}],"minBalance":0}';
		expect(m.mask(json)).toBe(json);
	});

	it('still masks a ten-digit account number, in a string, in an account key, and as a bare number', () => {
		const m = createMasker();
		expect(m.mask('send it to 1234567890 please')).toBe('send it to [ACCT_1] please');
		expect(m.mask('{"accountNumber":"1234567890"}')).toBe('{"accountNumber":"[ACCT_1]"}');
		// A bare number under an account-like key is an account number, whatever its length
		expect(m.mask('{"accountNumber":1234567890}')).toBe('{"accountNumber":[ACCT_1]}');
		// A digit string is never an amount, even under a money key
		expect(m.mask('{"amount":"1234567890"}')).toBe('{"amount":"[ACCT_1]"}');
	});

	it('does not take the first ten characters of a dashed account number for a date', () => {
		const m = createMasker();
		expect(m.mask('account 1234-56-78-9012 please')).not.toContain('1234-56-78');
		expect(m.mask('on 2026-10-31 at 09:00')).toBe('on 2026-10-31 at 09:00');
	});

	it('keeps masking a card and a phone number in a result', () => {
		const m = createMasker();
		const out = m.mask('{"note":"card 4539 1488 0343 6467","phone":"09171234567"}');
		expect(out).toBe('{"note":"card [CARD_1]","phone":"[PHONE_1]"}');
	});

	it('does not read a date with a time as an account number', () => {
		const m = createMasker();
		for (const text of [
			'2026-10-31 09:00',
			'2026-10-31T09:00:00+08:00',
			'{"at":"2026-10-31 09:00:00","dueDate":"2026-11-10"}',
			'on 2026-10-31 09:15 sharp'
		])
			expect(m.mask(text)).toBe(text);
	});

	it('does not read a time in milliseconds as an account number', () => {
		const m = createMasker();
		const json = '{"createdAtMs":1793423210753,"updatedAt":1793423210753}';
		expect(m.mask(json)).toBe(json);
	});

	it('an account number next to a date and an amount is the only thing masked', () => {
		const m = createMasker();
		const out = m.mask(
			'{"amount":123456789,"date":"2026-10-31 09:00","ref":"account 123456789012"}'
		);
		expect(out).toBe('{"amount":123456789,"date":"2026-10-31 09:00","ref":"account [ACCT_1]"}');
	});
});

describe('family names from the notebook', () => {
	const notebook = `# About you
- Works at Acme Corp

# People
- Maria Cruz (sister)
- Sister: Liza Santos
- loves coffee
- Kuya: Ramon
- Mother

# Preferences and rules
- Pays Rent first
`;

	it('takes the names under People, whole and by first name, and nothing else', () => {
		const names = peopleNames(notebook);
		expect(names).toEqual(
			expect.arrayContaining(['Maria Cruz', 'Maria', 'Cruz', 'Liza Santos', 'Ramon'])
		);
		expect(names).not.toContain('Acme');
		expect(names).not.toContain('Rent');
		expect(names).not.toContain('Mother');
		expect(names).not.toContain('Sister');
	});

	it('masks such a name', () => {
		const m = createMasker(peopleNames(notebook));
		expect(m.mask('Paid Maria Cruz and Ramon')).toBe('Paid [NAME_1] and [NAME_2]');
	});
});
