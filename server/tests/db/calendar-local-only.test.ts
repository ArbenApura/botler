// MIGRATION 0019: THE EVENTS COPIED FROM GOOGLE ARE REMOVED PERSON BY PERSON (FORCED ROW LEVEL SECURITY BINDS THE MIGRATING OWNER), WITH THEIR REMINDERS, AND NOTHING ELSE IS TOUCHED.
// The test database runs as a superuser, so this pins the logic of the statement; the per person loop is what keeps it working for a
// non-superuser owner, whose only delete policy reads app.user_id.

// -- TYPES -- //
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { seedPerson } from '../agent/support';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('migration 0019 purge of Google copies', () => {
	it('removes only the google events and their reminders, for every person', async () => {
		const a = await seedPerson(t);
		const b = await seedPerson(t);
		const file = readFileSync(
			new URL('../../src/lib/server/db/migrations/0019_calendar_local_only.sql', import.meta.url),
			'utf8'
		);
		const purge = file.split('--> statement-breakpoint')[0]!;
		expect(purge).toContain('DELETE FROM "calendar_event"');

		// The new check no longer allows the old source, so it is lifted for this test only
		await t.handle.owner.query(
			'ALTER TABLE calendar_event DROP CONSTRAINT calendar_event_source_chk'
		);
		const ids: Record<string, string> = {};
		for (const [who, person] of [
			['a', a],
			['b', b]
		] as const) {
			for (const source of ['google', 'botler']) {
				const [row] = await t.handle.owner.query<{ id: string }>(
					`INSERT INTO calendar_event (user_id, title, starts_at, ends_at, source)
					 VALUES ($1, $2, '2026-11-01T01:00:00Z', '2026-11-01T02:00:00Z', $3) RETURNING id`,
					[person.userId, `${who} ${source}`, source]
				);
				ids[`${who}-${source}`] = row!.id;
				await t.handle.owner.query(
					`INSERT INTO reminder (user_id, kind, ref_key, title, remind_at)
					 VALUES ($1, 'event', $2, $3, '2026-11-01T01:00:00Z')`,
					[person.userId, `event:${row!.id}`, `${who} ${source}`]
				);
			}
		}

		await t.handle.owner.query(purge);

		const events = await t.handle.owner.query<{ title: string }>(
			'SELECT title FROM calendar_event'
		);
		const titles = events.map((e) => e.title);
		expect(titles).toEqual(expect.arrayContaining(['a botler', 'b botler']));
		expect(titles.some((x) => x.endsWith(' google'))).toBe(false);
		const keys = (
			await t.handle.owner.query<{ ref_key: string }>('SELECT ref_key FROM reminder')
		).map((r) => r.ref_key);
		expect(keys).toContain(`event:${ids['a-botler']}`);
		expect(keys).toContain(`event:${ids['b-botler']}`);
		expect(keys).not.toContain(`event:${ids['a-google']}`);
		expect(keys).not.toContain(`event:${ids['b-google']}`);
	});
});
