// MIGRATION 0038 NARROWS THE PROVIDER CHECKS TO DEEPSEEK (THE ANTHROPIC SERVER WAS REMOVED). OLD ROWS WRITTEN WHILE ANTHROPIC WAS A CHOICE MUST SURVIVE IT,
// SO THE NEW CHECKS ARE ADDED NOT VALID: THEY GUARD NEW ROWS AND DO NOT RE-CHECK OLD ONES (A DEPLOY MUST NEVER FAIL ON HISTORY).

// -- DEP-MODULES -- //
import { afterAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { createStagedDb, type StagedDb } from '../support/stagedDb';

// -- STATES -- //

const open: StagedDb[] = [];

// -- LIFECYCLES -- //

afterAll(async () => {
	for (const d of open) await d.close();
});

// -- TESTS -- //

describe('migration 0038 (provider checks)', () => {
	it('keeps old anthropic usage and setting rows, and refuses new ones', async () => {
		const db = await createStagedDb({ before: '0038', plainOwner: true });
		open.push(db);
		const q = db.handle.owner.query.bind(db.handle.owner);
		await q(`INSERT INTO "user" (id, name, email) VALUES ('u_prov_0001', 'P', 'p@example.com')`);
		await q(
			`INSERT INTO model_usage (user_id, bucket, month, provider) VALUES ('u_prov_0001', 'chat', '2026-09', 'anthropic')`
		);
		await q(
			`INSERT INTO user_setting (user_id, model_provider) VALUES ('u_prov_0001', 'anthropic')`
		);
		await db.lockDown();

		const applied = await db.finish();
		expect(applied).toContain('0038_chat_turn_run_no');

		const reader = await db.reader();
		try {
			const kept = await reader.query(
				`SELECT provider FROM model_usage WHERE user_id = 'u_prov_0001'`
			);
			expect(kept.rows).toEqual([{ provider: 'anthropic' }]);
			await expect(
				reader.query(
					`INSERT INTO model_usage (user_id, bucket, month, provider) VALUES ('u_prov_0001', 'chat', '2026-10', 'anthropic')`
				)
			).rejects.toThrow();
			// A person who had chosen the removed server is back on the default, and can save a setting again
			const setting = await reader.query(
				`UPDATE user_setting SET photo_mode = 'text' WHERE user_id = 'u_prov_0001' RETURNING model_provider`
			);
			expect(setting.rows).toEqual([{ model_provider: null }]);
			const run = await reader.query(
				`SELECT column_default FROM information_schema.columns WHERE table_name = 'chat_turn' AND column_name = 'run_no'`
			);
			expect(run.rows).toEqual([{ column_default: '0' }]);
		} finally {
			await reader.end();
		}
	});
});
