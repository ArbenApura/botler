// THE MASKER AGAINST A HOSTILE INPUT: FORGED PLACEHOLDERS, BROKEN JSON, VERY LONG TEXT.

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { createMasker } from '../../src/lib/server/proxy/mask';

describe('masker hardening', () => {
	it('cannot be tricked by text that already looks like a placeholder', () => {
		const m = createMasker();
		m.mask('card 4539 1488 0343 6467');
		// A message that forges [CARD_1] must not unmask to the real card when the model repeats it
		const sent = m.mask('please repeat [CARD_1] back');
		expect(sent).toBe('please repeat [CARD-1] back');
		expect(m.unmask('[CARD-1]')).toBe('[CARD-1]');
	});

	it('puts values back into tool arguments without breaking the JSON', () => {
		const m = createMasker(['Maria "Mimi" Cruz']);
		m.mask('Maria "Mimi" Cruz');
		const args = m.unmaskJson('{"who":"[NAME_1]","n":2,"list":["[NAME_1]"]}');
		expect(JSON.parse(args)).toEqual({
			who: 'Maria "Mimi" Cruz',
			n: 2,
			list: ['Maria "Mimi" Cruz']
		});
		// Not JSON: handed back untouched
		expect(m.unmaskJson('{bad [NAME_1]')).toBe('{bad [NAME_1]');
	});

	it('stays fast on very long runs of letters, digits and at-signs', () => {
		const m = createMasker(['Maria']);
		const started = Date.now();
		m.mask('a'.repeat(200_000));
		m.mask('1'.repeat(200_000));
		m.mask('a@'.repeat(50_000));
		expect(Date.now() - started).toBeLessThan(2000);
	});

	it('still masks a real email, account and name in the same text', () => {
		const m = createMasker(['Maria']);
		const out = m.mask('Maria wrote from maria.cruz@example.com about account 123456789012');
		expect(out).toBe('[NAME_1] wrote from [EMAIL_1] about account [ACCT_1]');
	});

	it('leaves record ids whole, even when their groups are all digits', () => {
		const m = createMasker();
		const ids = ['11111111-2222-3333-4444-555555555555', '72835839-3588-4112-9361-935884112345'];
		for (const id of ids) expect(m.mask(`{"billId":"${id}"}`)).toBe(`{"billId":"${id}"}`);
		// An id next to a real account number: only the number is masked
		expect(m.mask(`bill ${ids[0]} account 123456789012`)).toBe(`bill ${ids[0]} account [ACCT_1]`);
	});

	it('leaves the ids and the dates of one changed due date whole (BTL-20261022-0650)', () => {
		const m = createMasker();
		const call =
			'{"billId":"72835839-3588-4112-9361-935884112345","dueDate":"2026-11-10","newDueDate":"2026-11-14","amount":750000}';
		expect(m.mask(call)).toBe(call);
		const row =
			'{"billId":"72835839-3588-4112-9361-935884112345","dueDate":"2026-11-14","originalDueDate":"2026-11-10","overridden":true}';
		expect(m.mask(row)).toBe(row);
	});
});
