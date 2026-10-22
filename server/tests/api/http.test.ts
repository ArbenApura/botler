// THE SHARED HTTP HELPERS: REFUSED REQUESTS NEVER REACH THE DATABASE, THE ERROR SHAPE IS ONE, THE BODY IS CAPPED.

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { callerCtx, fail, readJson } from '../../src/lib/server/api/http';
import { OpsError } from '../../src/lib/server/ops/context';

describe('api helpers', () => {
	it('answers 401 when nobody is signed in, without touching the database', async () => {
		const r = await callerCtx({ user: null }, new Request('http://x/api/v1/devices'));
		expect('response' in r && r.response.status).toBe(401);
	});

	it('refuses an Idempotency-Key that is too short or too long', async () => {
		const user = { id: 'user_anna_0001', name: 'A', email: 'a@example.com' };
		for (const key of ['short', 'x'.repeat(81)]) {
			const r = await callerCtx(
				{ user },
				new Request('http://x/api/v1/devices', { headers: { 'idempotency-key': key } })
			);
			expect('response' in r && r.response.status).toBe(400);
		}
	});

	it('refuses a body over 64 KB, declared or actual', async () => {
		const big = 'x'.repeat(64 * 1024 + 1);
		await expect(
			readJson(new Request('http://x', { method: 'POST', body: JSON.stringify({ big }) }))
		).rejects.toMatchObject({ code: 'INVALID' });
		await expect(
			readJson(
				new Request('http://x', {
					method: 'POST',
					body: '{}',
					headers: { 'content-length': '70000' }
				})
			)
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('refuses a body that is not JSON and reads a good one', async () => {
		await expect(
			readJson(new Request('http://x', { method: 'POST', body: '{nope' }))
		).rejects.toBeInstanceOf(OpsError);
		expect(await readJson(new Request('http://x', { method: 'POST', body: '{"a":1}' }))).toEqual({
			a: 1
		});
	});

	it('maps each error code to its status and hides unexpected errors', async () => {
		const cases: [OpsError['code'], number][] = [
			['INVALID', 400],
			['FORBIDDEN', 403],
			['NOT_FOUND', 404],
			['CONFLICT', 409],
			['LIMIT', 429],
			['UNAVAILABLE', 503]
		];
		for (const [code, status] of cases) expect(fail(new OpsError(code, 'm')).status).toBe(status);
		const res = fail(new Error('secret detail about rent'));
		expect(res.status).toBe(500);
		expect(await res.text()).not.toContain('rent');
	});
});
