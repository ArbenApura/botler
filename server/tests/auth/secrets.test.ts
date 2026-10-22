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
			'ALLOWED_EMAILS',
			'DEEPSEEK_API_KEY'
		] as const;
		for (const name of required) {
			expect(() => check(name, undefined), `${name} must be required`).toThrow();
			expect(() => check(name, '  '), `${name} must refuse blanks`).toThrow();
		}
		expect(() => check('BETTER_AUTH_SECRET', 'too-short')).toThrow(/32 characters/);
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
