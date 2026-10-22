// LOAD TEST (P4.10): RETRIEVAL OVER 50,000 FACTS WITH REAL INDEXES (the full-text index and the vector index).
// It takes a few minutes to fill the table, so it runs only on request:   BOTLER_LOAD_TEST=1 yarn vitest run tests/memory/load
// Target: the database part of one retrieval (keywords and vectors, scored, packed in the budget) answers in under 250 ms at the 95th percentile.

// -- TYPES -- //
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { writeFileSync } from 'node:fs';
import { sql } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { user } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { loadMemoryContext } from '../../src/lib/server/memory/retrieve';
import { createTestDb } from '../support/testDb';
import { hashVector } from '../support/embed';

// -- CONSTANTS -- //

const FACTS = 50_000;
const TARGET_P95_MS = 250;
const ON = process.env.BOTLER_LOAD_TEST === '1';
const USER = 'user_load_00001';

// -- STATES -- //

let t: TestDb;

// -- LIFECYCLES -- //

beforeAll(async () => {
	if (!ON) return;
	t = await createTestDb();
	await t.handle.db.insert(user).values({ id: USER, name: 'Load', email: 'load@example.com' });
	await withUser(t.handle, USER, (tx) =>
		tx.execute(sql`
			insert into memory_fact (user_id, text, text_hash, importance, embedding, embedding_model, valid_from)
			select ${USER},
			       'fact ' || g || ' about ' || (array['sister','rent','coffee','dog','travel','work','gym','birthday','parents','savings'])[1 + g % 10] || ' ' || md5(g::text),
			       md5(g::text || 'x'),
			       1 + g % 5,
			       (select array_agg(random())::real[]::vector from generate_series(1, 384) s where g is not null),
			       'test-hash-v1',
			       now() - (g % 400) * interval '1 day'
			from generate_series(1, ${FACTS}) g`)
	);
	await withUser(t.handle, USER, (tx) => tx.execute(sql`analyze memory_fact`));
}, 900_000);

afterAll(async () => {
	if (ON) await t.close();
});

// -- TESTS -- //

describe.skipIf(!ON)('retrieval over 50,000 facts', () => {
	it('answers within the target', async () => {
		const ctx = { handle: t.handle, actor: { userId: USER, kind: 'person' as const } };
		const queries = [
			'my sister birthday',
			'rent due',
			'coffee shop',
			'dog food',
			'travel plans',
			'work meeting',
			'gym schedule',
			'parents allowance',
			'savings goal',
			'birthday gift'
		];
		const times: number[] = [];
		for (let round = 0; round < 3; round++)
			for (const q of queries) {
				const embedder = { model: 'test-hash-v1', embed: async () => [hashVector(q)] };
				const started = performance.now();
				const result = await loadMemoryContext(ctx, { query: q, embedder });
				times.push(performance.now() - started);
				expect(result.lines.length).toBeGreaterThan(0);
				expect(result.tokens).toBeLessThanOrEqual(700);
			}
		times.sort((a, b) => a - b);
		const p95 = times[Math.floor(times.length * 0.95) - 1] ?? 0;
		const report = JSON.stringify({
			facts: FACTS,
			runs: times.length,
			medianMs: Math.round(times[times.length / 2] ?? 0),
			p95Ms: Math.round(p95),
			maxMs: Math.round(times.at(-1) ?? 0)
		});
		// The numbers go to a file when asked, because the test runner hides console output
		if (process.env.BOTLER_LOAD_OUT) writeFileSync(process.env.BOTLER_LOAD_OUT, report);
		expect(p95).toBeLessThan(TARGET_P95_MS);
	}, 300_000);
});
