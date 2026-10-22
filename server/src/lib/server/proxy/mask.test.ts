// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { createMasker } from './mask';

describe('payload masker', () => {
	it('hides long account numbers, with or without separators', () => {
		const m = createMasker();
		const out = m.mask('RCBC 1234567890123 and 4567-8901-2345-6789');
		expect(out).not.toMatch(/1234567890123|4567/);
		expect(out).toContain('[ACCT_1]');
	});

	it('hides a card number that passes the Luhn check as a card', () => {
		const m = createMasker();
		const out = m.mask('card 4539 1488 0343 6467');
		expect(out).toContain('[CARD_1]');
		expect(out).not.toMatch(/4539/);
	});

	it('hides Philippine mobile numbers in common forms', () => {
		const m = createMasker();
		const out = m.mask('send to 0917 123 4567 or +63 917 123 4567 or 09171234567');
		expect(out).not.toMatch(/917/);
		// The same number gets the same placeholder
		expect(out.match(/\[PHONE_1\]/g)?.length).toBe(3);
	});

	it('hides emails', () => {
		const out = createMasker().mask('mail me at arben@example.com');
		expect(out).toBe('mail me at [EMAIL_1]');
	});

	it('leaves money amounts and short numbers alone', () => {
		const m = createMasker();
		const text = 'Meralco 2,300.50 due on the 15th, lunch 180, bonus 1,250,000, rent 35000';
		expect(m.mask(text)).toBe(text);
	});

	it('treats an eight digit number as an account only after an account word', () => {
		const m = createMasker();
		expect(m.mask('transfer 12345678 pesos')).toBe('transfer 12345678 pesos');
		expect(m.mask('account no. 12345678')).toContain('[ACCT_1]');
	});

	it('hides listed names whole word and case-insensitively, and not parts of other words', () => {
		const m = createMasker(['Maria', 'Tatay Ben']);
		const out = m.mask('Give Maria 5,000, ask tatay ben, then Mariana');
		expect(out).toBe('Give [NAME_1] 5,000, ask [NAME_2], then Mariana');
	});

	it('restores the original values in a reply', () => {
		const m = createMasker(['Maria']);
		m.mask('Send 5,000 to Maria at 09171234567');
		expect(m.unmask('Done: [NAME_1] got it, called [PHONE_1].')).toBe(
			'Done: Maria got it, called 09171234567.'
		);
		expect(m.unmask('[ACCT_9] stays')).toBe('[ACCT_9] stays');
	});

	it('restores a placeholder that a stream split across chunks', () => {
		const m = createMasker(['Maria']);
		m.mask('Maria');
		const s = m.streamUnmasker();
		const out = [s.push('Hello [NA'), s.push('ME_'), s.push('1], bye [x'), s.flush()].join('');
		expect(out).toBe('Hello Maria, bye [x');
	});

	it('counts what it masked without exposing values', () => {
		const m = createMasker(['Maria']);
		m.mask('Maria 09171234567 a@b.co');
		expect(m.counts()).toEqual({ NAME: 1, PHONE: 1, EMAIL: 1 });
	});
});
