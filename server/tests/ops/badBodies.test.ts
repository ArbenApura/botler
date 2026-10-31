// A BODY THAT IS NOT AN OBJECT (null, a string, a number, an array) IS A 400 FOR EVERY VERB, NEVER A 500: THE OPERATIONS LAYER ANSWERS IT WITH AN OpsError CODE INVALID.

// -- TYPES -- //
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { fail } from '../../src/lib/server/api/http';
import { OpsError } from '../../src/lib/server/ops/context';
import { invokeVerb, VERBS } from '../../src/lib/server/ops/registry';
import { createTestDb } from '../support/testDb';
import { seedPerson } from '../agent/support';

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

describe('a body that is not an object', () => {
	it('is refused as INVALID by every verb, and the HTTP edge turns it into a 400', async () => {
		const f = await seedPerson(t);
		const ctx = { ...f.ctx, requestId: 'req-bad-body-0001' };
		const odd: unknown[] = [null, 'text', 5, [], true];
		const problems: string[] = [];
		for (const v of VERBS)
			for (const body of odd) {
				try {
					await invokeVerb(ctx, v.name, body);
					problems.push(`${v.name}(${JSON.stringify(body)}) was accepted`);
				} catch (e) {
					if (!(e instanceof OpsError) || e.code !== 'INVALID')
						problems.push(`${v.name}(${JSON.stringify(body)}) threw ${String(e)}`);
					else expect((await fail(e)).status).toBe(400);
				}
			}
		expect(problems).toEqual([]);
	}, 60_000);
});
