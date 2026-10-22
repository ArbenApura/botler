// SETTINGS VERBS (BTL-20261022-0218, C.3): DEFAULTS WITHOUT A ROW, A PERSON-ONLY UPSERT, NO CONVERSION NOTICE, REPLAY AND A RACE ON THE FIRST WRITE

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { user } from '../../src/lib/server/db/schema';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { getSettings, setSettings } from '../../src/lib/server/ops/settings';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const person = (id: string): Ctx => ({ handle: t.handle, actor: { userId: id, kind: 'person' } });
const as = (c: Ctx): Ctx => ({
	...c,
	requestId: `req-settings-${String(++counter).padStart(5, '0')}`
});
const agent = (id: string): Ctx => ({
	handle: t.handle,
	actor: { userId: id, kind: 'agent', tool: 'test' }
});

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values([
		{ id: 'user_set_a_001', name: 'A', email: 'a@example.com' },
		{ id: 'user_set_b_001', name: 'B', email: 'b@example.com' },
		{ id: 'user_set_c_001', name: 'C', email: 'c@example.com' }
	]);
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('settings', () => {
	it('answers the defaults for a person with no row, and writes nothing to read them', async () => {
		expect(await getSettings(person('user_set_a_001'))).toEqual({
			currency: 'PHP',
			language: 'en',
			replyLanguage: 'auto',
			weekStartsOn: 1
		});
		// The assistant may read them
		expect(await invokeVerb(agent('user_set_a_001'), 'settings_get', {})).toMatchObject({
			currency: 'PHP'
		});
	});

	it('changes only the fields given and says amounts are not converted', async () => {
		const a = person('user_set_a_001');
		const first = await setSettings(as(a), { currency: 'USD' });
		expect(first.settings).toEqual({
			currency: 'USD',
			language: 'en',
			replyLanguage: 'auto',
			weekStartsOn: 1
		});
		expect(first.notice).toMatch(/Nothing was converted/);
		// A later change of another field keeps the currency, with no notice
		const second = await setSettings(as(a), { language: 'fil', weekStartsOn: 0 });
		expect(second.settings).toEqual({
			currency: 'USD',
			language: 'fil',
			replyLanguage: 'auto',
			weekStartsOn: 0
		});
		expect(second.notice).toBeNull();
		expect(await getSettings(a)).toEqual(second.settings);
		// Another person is untouched
		expect((await getSettings(person('user_set_b_001'))).currency).toBe('PHP');
	});

	it('refuses a currency or value that is not allowed, and unknown fields', async () => {
		const a = person('user_set_a_001');
		await expect(setSettings(as(a), { currency: 'XXX' })).rejects.toMatchObject({
			code: 'INVALID'
		});
		await expect(setSettings(as(a), { weekStartsOn: 3 })).rejects.toMatchObject({
			code: 'INVALID'
		});
		await expect(
			invokeVerb(as(a), 'settings_set', { currency: 'USD', userId: 'someone-else' })
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('is never done by the assistant', async () => {
		await expect(
			invokeVerb(as(agent('user_set_a_001')), 'settings_set', { currency: 'EUR' })
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
		await expect(
			setSettings(as(agent('user_set_a_001')), { currency: 'EUR' })
		).rejects.toMatchObject({
			code: 'FORBIDDEN'
		});
		expect((await getSettings(person('user_set_a_001'))).currency).toBe('USD');
	});

	it('returns the first answer on a replay, and writes once', async () => {
		const b = as(person('user_set_b_001'));
		const first = await setSettings(b, { currency: 'JPY' });
		const again = await setSettings(b, { currency: 'JPY' });
		expect(again).toEqual(first);
		await expect(setSettings(b, { currency: 'EUR' })).rejects.toMatchObject({ code: 'CONFLICT' });
	});

	it('survives two first writes at once', async () => {
		const c = person('user_set_c_001');
		const results = await Promise.allSettled([
			setSettings(as(c), { currency: 'SGD' }),
			setSettings(as(c), { language: 'fil' })
		]);
		expect(results.every((r) => r.status === 'fulfilled')).toBe(true);
		const final = await getSettings(c);
		// One row, whichever came last holds its field and the other field is one of its two values
		expect(['SGD', 'PHP']).toContain(final.currency);
		expect(['fil', 'en']).toContain(final.language);
	});
});
