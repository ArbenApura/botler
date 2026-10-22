// WHO AND WHERE REACH THE AUDIT TRAIL (BTL-20261022-0218, L.3): THE CONTEXT OF EACH WAY IN, AND THE JOB AND SYNC PATHS THAT WRITE ON THEIR OWN

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { and, asc, eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { auditEvent, task, user } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { channelOf } from '../../src/lib/server/api/http';
import { auditOf } from '../../src/lib/server/ops/context';
import { enqueue, runBatch } from '../../src/lib/server/jobs/queue';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db
		.insert(user)
		.values([{ id: 'user_ctx_0001', name: 'A', email: 'a@example.com' }]);
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('the context of each way in', () => {
	const handle = () => t.handle;

	it('reads a person at the screens, the assistant in the chat, a job as a job', () => {
		const person: Ctx = { handle: handle(), actor: { userId: 'user_ctx_0001', kind: 'person' } };
		expect(auditOf(person)).toMatchObject({ actorKind: 'person', channel: 'app', onBehalf: '' });
		const agent: Ctx = {
			handle: handle(),
			actor: { userId: 'user_ctx_0001', kind: 'agent', tool: 'expense_log' }
		};
		expect(auditOf(agent)).toMatchObject({
			actorKind: 'agent',
			channel: 'chat',
			actorRef: 'expense_log'
		});
		const job: Ctx = {
			...agent,
			via: 'job',
			channel: 'job',
			actor: { ...agent.actor, tool: 'job:x' }
		};
		expect(auditOf(job)).toMatchObject({ actorKind: 'job', channel: 'job' });
		const approved: Ctx = {
			...person,
			onBehalfOf: 'agent',
			approvalId: 'card-1',
			turnId: 'turn-1',
			requestId: 'card-card-1'
		};
		expect(auditOf(approved)).toMatchObject({
			actorKind: 'person',
			onBehalf: 'agent',
			approvalId: 'card-1',
			turnId: 'turn-1'
		});
	});

	it('takes the way in from the app only when it is one the app may say', () => {
		const ask = (h?: string) =>
			channelOf(new Request('http://x.test/', h ? { headers: { 'x-botler-channel': h } } : {}));
		expect(ask()).toBe('app');
		expect(ask('widget')).toBe('widget');
		expect(ask('outbox')).toBe('outbox');
		// Nothing else can be claimed, so the app cannot pass itself off as the assistant or a job
		for (const bad of ['chat', 'job', 'system', 'calendar_sync', 'WIDGET', ''])
			expect(ask(bad)).toBe('app');
	});
});

describe('a job writes as a job', () => {
	it('leaves rows that say job and the kind of job', async () => {
		const id = 'user_ctx_0001';
		await withUser(t.handle, id, (tx) =>
			enqueue(tx, { userId: id, kind: 'audit.test', key: 'audit-test-1', payload: {} })
		);
		await runBatch(
			t.handle,
			{
				'audit.test': async (row, tx) => {
					await tx.insert(task).values({ userId: row.userId, title: 'From a job' });
				}
			},
			{}
		);
		const rows = await withUser(t.handle, id, (tx) =>
			tx
				.select()
				.from(auditEvent)
				.where(and(eq(auditEvent.userId, id), eq(auditEvent.entity, 'task')))
				.orderBy(asc(auditEvent.seq))
		);
		expect(rows).toHaveLength(1);
		expect(rows[0]).toMatchObject({
			actorKind: 'job',
			channel: 'job',
			actorRef: 'job:audit.test',
			action: 'create'
		});
		// The title of a task is never copied
		expect(JSON.stringify(rows)).not.toMatch(/From a job/);
	});
});
