// THE ONE-OFF NUTRIENT BACKFILL (BTL-20261110-1532): OLD FILIPINO-LIST ENTRIES GET THE FOUR VALUES THEY NEVER HAD, ONLY WHERE UNKNOWN,
// ONLY ON ENTRIES THAT STILL ARE WHAT THE LIST MADE, ONCE PER PERSON, AND ONLY WHEN SOMEONE QUEUES IT

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { and, eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
// -- MODULES -- //
import { foodEntry, job, user } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import {
	NUTRIENT_BACKFILL_JOB,
	NUTRIENT_BACKFILL_SQL
} from '../../src/lib/server/jobs/backfillSql';
import { jobHandlers } from '../../src/lib/server/jobs/handlers';
import { runBatch, scheduleMaintenance } from '../../src/lib/server/jobs/queue';
import { backfillFilipinoNutrients } from '../../src/lib/server/ops/food';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { createTestDb } from '../support/testDb';

// -- TYPES -- //

type Row = {
	id: string;
	name: string;
	grams: number | null;
	kcal: number;
	sugarMg: number | null;
	fibreMg: number | null;
	satFatMg: number | null;
	sodiumMg: number | null;
	version: number;
};

// -- CONSTANTS -- //

const ME = 'user_fill_0001';
const OTHER = 'user_fill_0002';
const DAY = '2030-05-01';
const UNKNOWN = { sugarMg: null, fibreMg: null, satFatMg: null, sodiumMg: null };

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const ctx = (userId = ME): Ctx => ({
	handle: t.handle,
	actor: { userId, kind: 'person' },
	requestId: `req-fill-${String(++counter).padStart(6, '0')}`
});

/** Logs one Filipino dish, then makes the entry what an old one looked like: the four values unknown, plus any other change. */
async function oldEntry(
	foodId: string,
	grams: number,
	change: Partial<typeof foodEntry.$inferInsert> = {},
	userId = ME
): Promise<string> {
	const r = (await invokeVerb(ctx(userId), 'meal_log', {
		day: DAY,
		items: [{ foodId, grams }]
	})) as { entries: { id: string }[] };
	const id = r.entries[0]?.id ?? '';
	await withUser(t.handle, userId, (tx) =>
		tx
			.update(foodEntry)
			.set({ ...UNKNOWN, ...change })
			.where(and(eq(foodEntry.userId, userId), eq(foodEntry.id, id)))
	);
	return id;
}

const rowOf = async (id: string, userId = ME): Promise<Row | undefined> => {
	const [row] = await withUser(t.handle, userId, (tx) =>
		tx
			.select()
			.from(foodEntry)
			.where(and(eq(foodEntry.userId, userId), eq(foodEntry.id, id)))
	);
	return row;
};

const queue = () =>
	t.handle.owner.query(NUTRIENT_BACKFILL_SQL.text, [...NUTRIENT_BACKFILL_SQL.values] as never[]);

const jobsOf = () =>
	t.handle.db
		.select({ userId: job.userId, status: job.status })
		.from(job)
		.where(eq(job.kind, NUTRIENT_BACKFILL_JOB.kind));

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values([
		{ id: ME, name: 'M', email: 'fill1@example.com' },
		{ id: OTHER, name: 'N', email: 'fill2@example.com' }
	]);
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('the nutrient backfill', () => {
	it('is never queued by the hourly schedule', async () => {
		await scheduleMaintenance(t.handle);
		expect(await jobsOf()).toHaveLength(0);
		expect(jobHandlers[NUTRIENT_BACKFILL_JOB.kind]).toBeTypeOf('function');
	});

	it('fills what is unknown, keeps what is known, and leaves changed entries alone', async () => {
		const plain = await oldEntry('fil:adobo_chicken', 200);
		// The person changed the grams later: the entry was scaled from its own numbers and still is the dish
		const regrammed = await oldEntry('fil:kanin', 190);
		await invokeVerb(ctx(), 'food_edit', { entryId: regrammed, grams: 200 });
		const partly = await oldEntry('fil:tocino', 100, { sugarMg: 123 });
		const otherKcal = await oldEntry('fil:sisig', 150, {
			kcal: 999,
			lowKcal: 900,
			highKcal: 1100
		});
		const goneDish = await oldEntry('fil:taho', 250, { sourceRef: 'fil:no_such_dish' });
		const noWeight = await oldEntry('fil:puto', 40, { grams: null });
		const theirs = await oldEntry('fil:adobo_chicken', 100, {}, OTHER);

		await queue();
		await queue();
		expect((await jobsOf()).map((j) => j.userId).sort()).toEqual([ME, OTHER]);
		const log = vi.spyOn(console, 'log').mockImplementation(() => {});
		// One job per person runs in a batch, and the schedule test above left the daily jobs queued too: batches run until this one is through
		for (let i = 0; i < 12 && (await jobsOf()).some((j) => j.status !== 'done'); i += 1)
			await runBatch(t.handle, jobHandlers);
		expect((await jobsOf()).every((j) => j.status === 'done')).toBe(true);
		// The log holds counts only, never a food name
		const lines = log.mock.calls
			.map((c) => String(c[0]))
			.filter((l) => l.includes('nutrient_backfill_done'));
		expect(lines).toHaveLength(2);
		expect(lines.join(' ')).not.toMatch(/adobo|tocino|sisig/i);
		log.mockRestore();

		expect(await rowOf(plain)).toMatchObject({
			kcal: 384,
			sugarMg: 1000,
			fibreMg: 400,
			satFatMg: 6600,
			sodiumMg: 960
		});
		expect(await rowOf(regrammed)).toMatchObject({
			grams: 200,
			sugarMg: 200,
			fibreMg: 800,
			satFatMg: 200,
			sodiumMg: 2
		});
		// The value that was there is kept; only the unknown ones are filled
		expect(await rowOf(partly)).toMatchObject({ sugarMg: 123, satFatMg: 5600, sodiumMg: 750 });
		for (const id of [otherKcal, goneDish, noWeight])
			expect(await rowOf(id), id).toMatchObject(UNKNOWN);
		expect(await rowOf(theirs, OTHER)).toMatchObject({ sugarMg: 500, sodiumMg: 480 });
	});

	it('changes nothing on a second run', async () => {
		const before = await withUser(t.handle, ME, (tx) =>
			tx.select().from(foodEntry).where(eq(foodEntry.userId, ME))
		);
		const again = await withUser(t.handle, ME, (tx) => backfillFilipinoNutrients(tx, ME));
		expect(again).toEqual({ filled: 0, skipped: 3, complete: 3 });
		const after = await withUser(t.handle, ME, (tx) =>
			tx.select().from(foodEntry).where(eq(foodEntry.userId, ME))
		);
		expect(after.map((r) => r.version)).toEqual(before.map((r) => r.version));
		// Queueing again adds no second job for a person who had it
		await queue();
		expect(await jobsOf()).toHaveLength(2);
	});
});
