// SECRETS AND TOKENS: GOOGLE TOKENS ARE ENCRYPTED AT REST, MISSING CONFIGURATION STOPS THE SERVER, A DEAD PUSH TOKEN IS DROPPED.

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { variables } from '../../src/env';
import { parseAllowList } from '../../src/lib/server/auth/allowlist';
import { createAuth } from '../../src/lib/server/auth/auth';
import { user } from '../../src/lib/server/db/schema';
import {
	listDevices,
	registerDevice,
	unregisterDeviceByToken
} from '../../src/lib/server/ops/devices';
import { createTestDb } from '../support/testDb';
import { assertProviderKeys } from '../../src/lib/server/proxy/provider';

// -- FUNCTIONS -- //

type Standard = { '~standard': { validate(v: unknown): unknown } };

/** Runs one variable through its schema: returns the value, or throws the schema's message. */
function check(name: keyof typeof variables, value: string | undefined): unknown {
	const out = (variables[name].schema as unknown as Standard)['~standard'].validate(value) as {
		value?: unknown;
		issues?: { message: string }[];
	};
	if (out.issues?.length) throw new Error(out.issues.map((i) => i.message).join('; '));
	return out.value;
}

// -- STATES -- //

let t: TestDb;
let anna: Ctx;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db
		.insert(user)
		.values({ id: 'user_anna_0001', name: 'Anna', email: 'a@example.com' });
	anna = { handle: t.handle, actor: { userId: 'user_anna_0001', kind: 'person' } };
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('secrets and tokens', () => {
	it("is set up to encrypt Google tokens at rest (the encryption itself is Better Auth's)", async () => {
		const auth = createAuth({
			handle: t.handle,
			config: {
				secret: 'x'.repeat(40),
				baseUrl: 'http://localhost:5280',
				google: { clientId: 'id', clientSecret: 'secret' },
				allow: parseAllowList('a@example.com'),
				disableRateLimit: true
			}
		});
		const ctx = await auth.$context;
		expect(ctx.options.account?.encryptOAuthTokens).toBe(true);
	});

	it('stops the server when required configuration is missing', () => {
		const required = [
			'BOTLER_BASE_URL',
			'BETTER_AUTH_SECRET',
			'GOOGLE_CLIENT_ID',
			'GOOGLE_CLIENT_SECRET',
			'ALLOWED_EMAILS'
		] as const;
		for (const name of required) {
			expect(() => check(name, undefined), `${name} must be required`).toThrow();
			expect(() => check(name, '  '), `${name} must refuse blanks`).toThrow();
		}
		expect(() => check('BETTER_AUTH_SECRET', 'too-short')).toThrow(/32 characters/);
	});

	it('validates the model provider and its conditional key', () => {
		expect(check('MODEL_PROVIDER', undefined)).toBe('deepseek');
		expect(check('MODEL_PROVIDER', 'deepseek')).toBe('deepseek');
		// Anthropic was removed: naming it stops the server
		expect(() => check('MODEL_PROVIDER', 'anthropic')).toThrow();
		expect(() => check('MODEL_PROVIDER', 'antropic')).toThrow();
		// The cross-variable requirement is plain code (proxy/provider.ts), so the matrix is tested there itself
	});

	it('has no separate web search key: search and page reading use the DeepSeek key and address', () => {
		expect(Object.keys(variables)).not.toContain('TAVILY_API_KEY');
		expect(check('DEEPSEEK_BASE_URL', undefined)).toBe('https://api.deepseek.com');
		expect(check('DEEPSEEK_BASE_URL', ' https://api.deepseek.com/ ')).toBe(
			'https://api.deepseek.com'
		);
	});

	it('requires the key of the chosen provider and refuses a name outside the list', () => {
		expect(() => assertProviderKeys('deepseek', { deepseek: '' })).toThrow(/DEEPSEEK_API_KEY/);
		expect(() => assertProviderKeys('deepseek', { deepseek: 'sk-dsk' })).not.toThrow();
		expect(() => assertProviderKeys('anthropic', { deepseek: 'sk-dsk' })).toThrow(/MODEL_PROVIDER/);
		expect(() => assertProviderKeys('mistral', { deepseek: 'k' })).toThrow(/MODEL_PROVIDER/);
	});

	it('has no feed outside production when none is set, trims it, and stops the server on an address that is not https', () => {
		expect(check('FX_RATES_URL', undefined)).toBe('');
		expect(check('FX_RATES_URL', '  ')).toBe('');
		expect(check('FX_RATES_URL', ' https://rates.example.com/latest ')).toBe(
			'https://rates.example.com/latest'
		);
		for (const bad of [
			'http://rates.example.com',
			'ftp://x.test',
			'not an address',
			'https://u:p@x.test/'
		])
			expect(() => check('FX_RATES_URL', bad), bad).toThrow();
	});

	it('rejects a bad cap instead of falling back silently', () => {
		expect(check('BOTLER_CHAT_TOKEN_CAP', undefined)).toBe(8_000_000);
		expect(() => check('BOTLER_CHAT_TOKEN_CAP', '-5')).toThrow();
		expect(() => check('BOTLER_CHAT_TOKEN_CAP', 'abc')).toThrow();
	});

	it('drops a dead push token and ignores one that is already gone', async () => {
		await registerDevice(
			{ ...anna, requestId: 'req-secret-reg-0001' },
			{ platform: 'android', pushToken: 'token-dead-0123456789', label: 'Old phone' }
		);
		expect(await listDevices(anna)).toHaveLength(1);
		await unregisterDeviceByToken(
			{ ...anna, requestId: 'req-secret-del-0001' },
			'token-dead-0123456789'
		);
		expect(await listDevices(anna)).toHaveLength(0);
		await unregisterDeviceByToken(
			{ ...anna, requestId: 'req-secret-del-0002' },
			'token-dead-0123456789'
		);
	});
});
