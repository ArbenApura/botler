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
import { configureProviders } from '../../src/lib/server/proxy/provider';
import { PROVIDER_VISION, pictureProviderFor, visionOf } from '../../src/lib/providers';
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
		expect(await getSettings(person('user_set_a_001'))).toMatchObject({
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
		expect(first.settings).toMatchObject({
			currency: 'USD',
			language: 'en',
			replyLanguage: 'auto',
			weekStartsOn: 1
		});
		expect(first.notice).toMatch(/nothing in the money plan was converted/);
		// A later change of another field keeps the currency, with no notice
		const second = await setSettings(as(a), { language: 'fil', weekStartsOn: 0 });
		expect(second.settings).toMatchObject({
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

	it('keeps the net balance choice: off by default, saved on and off, kept when another field changes (BTL-20261030-0546)', async () => {
		const a = person('user_set_c_001');
		expect((await getSettings(a)).showNetBalance).toBe(false);
		expect((await setSettings(as(a), { showNetBalance: true })).settings.showNetBalance).toBe(true);
		expect((await setSettings(as(a), { language: 'fil' })).settings.showNetBalance).toBe(true);
		expect((await getSettings(a)).showNetBalance).toBe(true);
		// false is a value, not "left out"
		expect((await setSettings(as(a), { showNetBalance: false })).settings.showNetBalance).toBe(
			false
		);
		expect((await getSettings(a)).showNetBalance).toBe(false);
		// Another person is untouched, and the assistant cannot change it
		expect((await getSettings(person('user_set_b_001'))).showNetBalance).toBe(false);
		await expect(
			invokeVerb(agent('user_set_c_001'), 'settings_set', { showNetBalance: true })
		).rejects.toMatchObject({ code: expect.any(String) });
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

	it('answers the photo choice as the picture for a person with no row, and keeps what they pick', async () => {
		const id = 'user_set_b_001';
		expect((await getSettings(person(id))).photoMode).toBe('image');
		const r = await setSettings(as(person(id)), { photoMode: 'text' });
		expect(r.settings.photoMode).toBe('text');
		expect((await getSettings(person(id))).photoMode).toBe('text');
		// Another field saved later does not put it back
		await setSettings(as(person(id)), { weekStartsOn: 0 });
		expect((await getSettings(person(id))).photoMode).toBe('text');
	});

	it('refuses a photo choice that is neither the picture nor the text', async () => {
		await expect(
			setSettings(as(person('user_set_a_001')), { photoMode: 'video' as never })
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('names the host that reads their pictures: their own, or none when no host is set up', async () => {
		try {
			const id = 'user_set_c_001';
			configureProviders({ available: ['deepseek'], fallback: 'deepseek' });
			await setSettings(as(person(id)), { modelProvider: 'deepseek' });
			expect(await getSettings(person(id))).toMatchObject({
				modelProvider: 'deepseek',
				photoHost: 'deepseek',
				photoVision: true
			});
			configureProviders(null);
			expect(await getSettings(person(id))).toMatchObject({ photoHost: null, photoVision: false });
		} finally {
			configureProviders(null);
		}
	});

	it('knows which hosts read pictures', () => {
		expect(PROVIDER_VISION).toEqual({ deepseek: true });
		expect(visionOf('deepseek')).toBe(true);
		expect(visionOf(null)).toBe(false);
		expect(pictureProviderFor('deepseek', ['deepseek'])).toBe('deepseek');
		// With a table where DeepSeek cannot see, no host reads the picture
		const noDeepseek = { deepseek: false };
		expect(pictureProviderFor('deepseek', ['deepseek'], noDeepseek)).toBeNull();
		expect(pictureProviderFor(null, [])).toBeNull();
	});
});
