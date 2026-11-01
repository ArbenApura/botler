// THE LANGUAGE AND CURRENCY LINES (BTL-20261022-0218, C.5): THE CACHED PREFIX NEVER CHANGES, THE PER-TURN CONTEXT CARRIES THE SETTING

// -- TYPES -- //
import type { ReplyLanguage } from '../../src/lib/server/db/schema/settings';
// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { REPLY_LANGUAGES } from '../../src/lib/server/db/schema/settings';
import {
	buildMessages,
	currencyLine,
	languageLine,
	SYSTEM_PREFIX
} from '../../src/lib/server/agent/prompt';

// -- TESTS -- //

describe('the assistant context', () => {
	const NOW = new Date('2026-10-22T04:00:00Z');
	const build = (replyLanguage: ReplyLanguage, currency: string) =>
		buildMessages({ now: NOW, history: [], userText: 'hi', replyLanguage, currency });

	it('keeps the system prefix identical for every setting, so the model host can cache it', () => {
		for (const mode of ['auto', 'en', 'fil', 'taglish'] as const)
			for (const currency of ['PHP', 'USD', 'JPY']) {
				const m = build(mode, currency);
				expect(m[0]).toEqual({ role: 'system', content: SYSTEM_PREFIX });
			}
		expect(SYSTEM_PREFIX).not.toMatch(/always Filipino|Taglish, a natural|\bUSD\b|\bJPY\b/);
	});

	it('puts the reply language and the currency in the context block of the last message', () => {
		const context = (build('fil', 'JPY').at(-1) as { content: string }).content;
		expect(context).toContain('Reply language: always Filipino.');
		expect(context).toContain('Japanese yen (JPY, written ¥)');
		expect(context).toContain('whole JPY');
	});

	it('says auto is English and never starts Taglish on its own', () => {
		const line = languageLine('auto');
		expect(line).toMatch(/Reply language: English/);
		expect(line).toMatch(/never start speaking it on your own/);
	});

	it('names every fixed reply language, so none falls back to the auto line', () => {
		for (const mode of REPLY_LANGUAGES.filter((m) => !['auto', 'en', 'fil', 'taglish'].includes(m)))
			expect(languageLine(mode)).toMatch(/^Reply language: always [A-Z]/);
		expect(languageLine('ja')).toContain('Japanese');
	});

	it('explains the smallest unit for hundredths and for whole units', () => {
		expect(currencyLine('PHP')).toContain('5 PHP is 500');
		expect(currencyLine('USD')).toContain('US dollar (USD, written $)');
		expect(currencyLine('KRW')).toContain('180 KRW is 180');
	});

	it('defaults to pesos and auto when nothing is given', () => {
		const m = buildMessages({ now: NOW, history: [], userText: 'hi' });
		const context = (m.at(-1) as { content: string }).content;
		expect(context).toContain('Philippine peso (PHP');
		expect(context).toContain('Reply language: English.');
	});
});
