// THE MODEL SERVER CHOICE (BTL-20261026-0443): A PERSON-ONLY SETTING, REFUSED WITHOUT A KEY, AUDITED, FOLLOWED BY EVERY MODEL CALL
// OF THAT PERSON (CHAT AND JOBS), FALLING BACK WHEN THE KEY IS GONE, WITH ONE RATE LIMIT SHARED BY BOTH PROVIDERS

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { ModelClient } from '../../src/lib/server/proxy/deepseek';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { asc, eq } from 'drizzle-orm';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { SELECTABLE_PROVIDERS, USAGE_PROVIDERS } from '../../src/lib/providers';
import { auditEvent, user } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { getSettings, setSettings } from '../../src/lib/server/ops/settings';
import { createAnthropicClient } from '../../src/lib/server/proxy/anthropic';
import { createModelClient } from '../../src/lib/server/proxy/deepseek';
import { createRateLimiter, DEFAULT_LIMITS } from '../../src/lib/server/proxy/limits';
import {
	configureProviders,
	effectiveProvider,
	providersWithKeys
} from '../../src/lib/server/proxy/provider';
import { createProviderRouter } from '../../src/lib/server/proxy/router';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const person = (id: string): Ctx => ({ handle: t.handle, actor: { userId: id, kind: 'person' } });
const job = (id: string): Ctx => ({
	handle: t.handle,
	actor: { userId: id, kind: 'person' },
	via: 'job',
	channel: 'job'
});
const as = (c: Ctx): Ctx => ({
	...c,
	requestId: `req-provider-${String(++counter).padStart(5, '0')}`
});
const trail = (id: string) =>
	withUser(t.handle, id, (tx) =>
		tx.select().from(auditEvent).where(eq(auditEvent.userId, id)).orderBy(asc(auditEvent.seq))
	);

/** A stand-in client that only says which provider answered. */
const stub = (name: string): ModelClient =>
	({
		complete: async () => ({ content: name }),
		stream: async function* () {
			yield { type: 'delta', text: name };
		}
	}) as unknown as ModelClient;

const BOTH = ['anthropic', 'deepseek'] as const;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values([
		{ id: 'user_prov_a_01', name: 'A', email: 'prov-a@example.com' },
		{ id: 'user_prov_b_01', name: 'B', email: 'prov-b@example.com' },
		{ id: 'user_prov_c_01', name: 'C', email: 'prov-c@example.com' }
	]);
});

afterAll(async () => {
	await t.close();
});

beforeEach(() => {
	configureProviders({ available: BOTH, fallback: 'anthropic' });
});

afterEach(() => {
	configureProviders(null);
});

// -- TESTS -- //

describe('the provider lists', () => {
	it('keeps unknown out of what a person can choose, and the database check in step with the list', () => {
		expect(SELECTABLE_PROVIDERS).not.toContain('unknown');
		expect(USAGE_PROVIDERS).toEqual([...SELECTABLE_PROVIDERS, 'unknown']);
		const sql = readFileSync(
			join(__dirname, '../../src/lib/server/db/migrations/0029_model_provider.sql'),
			'utf8'
		);
		const list = SELECTABLE_PROVIDERS.map((p) => `'${p}'`).join(', ');
		expect(sql).toContain(`"model_provider" in (${list})`);
	});

	it('offers the providers that have a key and falls back when a choice lost its key', () => {
		expect(providersWithKeys({ anthropic: 'k', deepseek: '' })).toEqual(['anthropic']);
		expect(effectiveProvider('deepseek', BOTH, 'anthropic')).toBe('deepseek');
		expect(effectiveProvider('deepseek', ['anthropic'], 'anthropic')).toBe('anthropic');
		expect(effectiveProvider(null, BOTH, 'deepseek')).toBe('deepseek');
		expect(effectiveProvider('unknown', BOTH, 'anthropic')).toBe('anthropic');
	});
});

describe('the setting', () => {
	it('starts on the server default, lists only what has a key, and never holds a key', async () => {
		const a = person('user_prov_a_01');
		const view = await getSettings(a);
		expect(view).toMatchObject({
			modelProvider: 'anthropic',
			modelProviderChoice: null,
			availableProviders: ['anthropic', 'deepseek']
		});
		expect(JSON.stringify(view)).not.toMatch(/key|secret/i);
	});

	it('is chosen by the person, can be reset to the default, and is kept by an unrelated change', async () => {
		const a = person('user_prov_a_01');
		const chosen = await setSettings(as(a), { modelProvider: 'deepseek' });
		expect(chosen.settings).toMatchObject({
			modelProvider: 'deepseek',
			modelProviderChoice: 'deepseek'
		});
		// Another field leaves the choice alone
		const other = await setSettings(as(a), { weekStartsOn: 0 });
		expect(other.settings.modelProviderChoice).toBe('deepseek');
		expect(await getSettings(a)).toEqual(other.settings);
		// Another person is untouched
		expect((await getSettings(person('user_prov_b_01'))).modelProviderChoice).toBeNull();
		// Null puts the person back on the default
		const reset = await setSettings(as(a), { modelProvider: null });
		expect(reset.settings).toMatchObject({ modelProvider: 'anthropic', modelProviderChoice: null });
	});

	it('refuses a server without a key, and unknown or invented names', async () => {
		const a = person('user_prov_a_01');
		configureProviders({ available: ['anthropic'], fallback: 'anthropic' });
		await expect(setSettings(as(a), { modelProvider: 'deepseek' })).rejects.toMatchObject({
			code: 'INVALID'
		});
		await expect(
			invokeVerb(as(a), 'settings_set', { modelProvider: 'unknown' })
		).rejects.toMatchObject({ code: 'INVALID' });
		await expect(invokeVerb(as(a), 'settings_set', { modelProvider: 'gpt' })).rejects.toMatchObject(
			{ code: 'INVALID' }
		);
		// With nothing set up at all, nothing can be chosen
		configureProviders(null);
		await expect(setSettings(as(a), { modelProvider: 'anthropic' })).rejects.toMatchObject({
			code: 'INVALID'
		});
	});

	it('is never changed by the assistant', async () => {
		const agent: Ctx = {
			handle: t.handle,
			actor: { userId: 'user_prov_a_01', kind: 'agent', tool: 'test' }
		};
		await expect(
			invokeVerb(as(agent), 'settings_set', { modelProvider: 'deepseek' })
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
	});

	it('leaves an audit row naming only the provider, for a change and for a reset', async () => {
		const c = person('user_prov_c_01');
		await setSettings(as(c), { modelProvider: 'deepseek' });
		await setSettings(as(c), { modelProvider: null });
		const rows = (await trail('user_prov_c_01')).filter((r) => r.entity === 'user_setting');
		const set = rows.at(-2);
		const reset = rows.at(-1);
		expect(set?.after).toMatchObject({ model_provider: 'deepseek' });
		expect(reset?.before).toMatchObject({ model_provider: 'deepseek' });
		expect(reset?.after).toMatchObject({ model_provider: null });
		expect(JSON.stringify([set, reset])).not.toMatch(/key|token/i);
	});
});

describe('the router', () => {
	const router = (available: readonly ('anthropic' | 'deepseek')[] = BOTH) =>
		createProviderRouter({
			clientFor: (p) => stub(p),
			available: () => available,
			fallback: 'anthropic'
		}).client;
	const req = { bucket: 'chat' as const, messages: [{ role: 'user' as const, content: 'hi' }] };

	it('sends a call to the host the person of the call chose, for chat and for jobs', async () => {
		await setSettings(as(person('user_prov_b_01')), { modelProvider: 'deepseek' });
		const r = router();
		expect(await r.complete(person('user_prov_b_01'), req)).toMatchObject({ content: 'deepseek' });
		// A memory job for the same person follows the same choice
		expect(await r.complete(job('user_prov_b_01'), req)).toMatchObject({ content: 'deepseek' });
		const parts: unknown[] = [];
		for await (const e of r.stream(person('user_prov_b_01'), req)) parts.push(e);
		expect(parts).toEqual([{ type: 'delta', text: 'deepseek' }]);
		// A person who chose nothing gets the default
		expect(await r.complete(person('user_prov_a_01'), req)).toMatchObject({ content: 'anthropic' });
	});

	it('falls back to the default, with a note in the log, when the chosen key is gone', async () => {
		const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
		try {
			const out = await router(['anthropic']).complete(person('user_prov_b_01'), req);
			expect(out).toMatchObject({ content: 'anthropic' });
			expect(warn).toHaveBeenCalledWith(expect.stringContaining('provider_choice_unavailable'));
			// The settings show the choice as it was stored and the host that will really run
			configureProviders({ available: ['anthropic'], fallback: 'anthropic' });
			expect(await getSettings(person('user_prov_b_01'))).toMatchObject({
				modelProvider: 'anthropic',
				modelProviderChoice: 'deepseek',
				availableProviders: ['anthropic']
			});
		} finally {
			warn.mockRestore();
		}
	});

	it('stops the call when the settings cannot be read, instead of choosing the default', async () => {
		const broken = { ...person('user_prov_b_01'), actor: { userId: '', kind: 'person' as const } };
		await expect(router().complete(broken, req)).rejects.toThrow();
	});
});

describe('the rate limit', () => {
	it('is one counter for both providers, so switching host gives no second allowance', async () => {
		const shared = createRateLimiter(2);
		const answers = () =>
			new Response(
				JSON.stringify({
					content: [{ type: 'text', text: 'ok' }],
					choices: [{ message: { content: 'ok' }, finish_reason: 'stop' }],
					stop_reason: 'end_turn',
					usage: { input_tokens: 1, output_tokens: 1, prompt_tokens: 1, completion_tokens: 1 }
				}),
				{ status: 200 }
			);
		const f = (async () => answers()) as unknown as typeof fetch;
		const base = {
			apiKey: 'k',
			baseUrl: 'https://model.test',
			limits: { ...DEFAULT_LIMITS, ratePerMinute: 2 },
			rateLimiter: shared,
			fetch: f,
			sleep: async () => undefined
		};
		const anthropic = createAnthropicClient({ ...base, model: 'claude-haiku-5-5' });
		const deepseek = createModelClient({ ...base, model: 'deepseek-flash' });
		const a = person('user_prov_a_01');
		const req = { bucket: 'chat' as const, messages: [{ role: 'user' as const, content: 'hi' }] };
		await anthropic.complete(a, req);
		await deepseek.complete(a, req);
		await expect(anthropic.complete(a, req)).rejects.toMatchObject({ code: 'LIMIT' });
		await expect(deepseek.complete(a, req)).rejects.toMatchObject({ code: 'LIMIT' });
		// Another person has their own allowance
		await expect(deepseek.complete(person('user_prov_b_01'), req)).resolves.toBeDefined();
	});
});
