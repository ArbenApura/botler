// THE IDEMPOTENCY CONTRACT: A WRITE WITH THE SAME REQUEST ID IS APPLIED ONCE, A REPLAY RETURNS THE FIRST RESULT,
// THE SAME ID WITH OTHER INPUT IS REFUSED, AND A FAILED WRITE LEAVES THE ID FREE FOR A RETRY.

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { requestLog, undoJournal, user } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { OpsError, recordUndo, runWrite } from '../../src/lib/server/ops/context';
import { listDevices, registerDevice } from '../../src/lib/server/ops/devices';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let anna: Ctx;
let ben: Ctx;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values([
		{ id: 'user_anna_0001', name: 'Anna', email: 'anna@example.com' },
		{ id: 'user_ben_00001', name: 'Ben', email: 'ben@example.com' }
	]);
	anna = { handle: t.handle, actor: { userId: 'user_anna_0001', kind: 'person' } };
	ben = { handle: t.handle, actor: { userId: 'user_ben_00001', kind: 'person' } };
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('idempotent writes', () => {
	const phone = {
		platform: 'android' as const,
		pushToken: 'token-idem-0123456789',
		label: 'Phone'
	};

	it('applies a write once and replays the same answer', async () => {
		const ctx = { ...anna, requestId: 'req-idem-first-0001' };
		const first = await registerDevice(ctx, phone);
		const again = await registerDevice(ctx, phone);
		expect(again).toEqual(first);
		expect(await listDevices(anna)).toHaveLength(1);
		const rows = await withUser(t.handle, 'user_anna_0001', (tx) => tx.select().from(requestLog));
		expect(rows.filter((r) => r.requestId === 'req-idem-first-0001')).toHaveLength(1);
	});

	it('refuses the same id with a different request', async () => {
		const ctx = { ...anna, requestId: 'req-idem-first-0001' };
		await expect(registerDevice(ctx, { ...phone, label: 'Another name' })).rejects.toMatchObject({
			code: 'CONFLICT'
		});
	});

	it('lets two people use the same id without touching each other', async () => {
		const r = await registerDevice({ ...ben, requestId: 'req-idem-first-0001' }, phone);
		expect(r.label).toBe('Phone');
		expect(await listDevices(ben)).toHaveLength(1);
	});

	it('handles two identical requests that arrive at the same time', async () => {
		const ctx = { ...anna, requestId: 'req-idem-parallel-1' };
		const input = { ...phone, pushToken: 'token-idem-parallel-1' };
		const [a, b] = await Promise.all([registerDevice(ctx, input), registerDevice(ctx, input)]);
		expect(a).toEqual(b);
		const rows = await listDevices(anna);
		expect(rows.filter((r) => r.id === a.id)).toHaveLength(1);
	});

	it('leaves the id free when the write fails, so a retry runs it', async () => {
		const ctx = { ...anna, requestId: 'req-idem-failing-1' };
		await expect(
			runWrite(ctx, 'test.fail', { n: 1 }, async () => {
				throw new OpsError('UNAVAILABLE', 'boom');
			})
		).rejects.toMatchObject({ code: 'UNAVAILABLE' });
		// The failed attempt left no claim behind
		const claims = await withUser(t.handle, 'user_anna_0001', (tx) =>
			tx.select().from(requestLog).where(eq(requestLog.requestId, 'req-idem-failing-1'))
		);
		expect(claims).toHaveLength(0);
		const ok = await runWrite(ctx, 'test.fail', { n: 1 }, async () => ({ done: true }));
		expect(ok).toEqual({ done: true });
	});

	it('rolls a failed write back completely, including its claim and its undo entry', async () => {
		const ctx = { ...anna, requestId: 'req-idem-rollback-1' };
		await expect(
			runWrite(ctx, 'test.rollback', {}, async (tx, userId) => {
				await recordUndo(tx, userId, ctx.requestId, {
					verb: 'test.rollback',
					entity: 'device',
					entityId: 'x',
					before: null,
					after: { a: 1 }
				});
				throw new Error('fail after writing');
			})
		).rejects.toThrow();
		const journal = await withUser(t.handle, 'user_anna_0001', (tx) =>
			tx.select().from(undoJournal).where(eq(undoJournal.verb, 'test.rollback'))
		);
		expect(journal).toHaveLength(0);
	});

	it('writes an undo entry with the row before and after', async () => {
		const ctx = { ...anna, requestId: 'req-idem-undo-0001' };
		await runWrite(ctx, 'test.undo', {}, async (tx, userId) => {
			await recordUndo(tx, userId, ctx.requestId, {
				verb: 'test.undo',
				entity: 'device',
				entityId: 'abc',
				before: { label: 'old' },
				after: { label: 'new', when: new Date('2026-10-21T00:00:00Z') }
			});
			return null;
		});
		const [entry] = await withUser(t.handle, 'user_anna_0001', (tx) =>
			tx.select().from(undoJournal).where(eq(undoJournal.verb, 'test.undo'))
		);
		expect(entry?.before).toEqual({ label: 'old' });
		expect(entry?.after).toEqual({ label: 'new', when: '2026-10-21T00:00:00.000Z' });
		expect(entry?.undoneAt).toBeNull();
	});

	it('refuses a request id that is too short or too long', async () => {
		await expect(
			runWrite({ ...anna, requestId: 'short' }, 'v', {}, async () => null)
		).rejects.toMatchObject({ code: 'INVALID' });
		await expect(
			runWrite({ ...anna, requestId: 'x'.repeat(81) }, 'v', {}, async () => null)
		).rejects.toMatchObject({ code: 'INVALID' });
	});
});
