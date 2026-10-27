// THE calc VERB: WORKED OUT LINES FOR THE ASSISTANT, MONEY ONLY THROUGH finance/currency.ts, A STRICT INPUT, AND NO DATABASE NEEDED

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { buildTools } from '../../src/lib/server/agent/tools';
import { invokeVerb, verbByName } from '../../src/lib/server/ops/registry';

// -- CONSTANTS -- //

// The verb reads nothing, so no database is behind the context
const handle = {} as Ctx['handle'];
const agent: Ctx = { handle, actor: { userId: 'user_calc_0001', kind: 'agent', tool: 'calc' } };
const person: Ctx = { handle, actor: { userId: 'user_calc_0001', kind: 'person' } };

type Out = { lines: Record<string, unknown>[] };

const run = async (ctx: Ctx, lines: unknown[]) => (await invokeVerb(ctx, 'calc', { lines })) as Out;

// -- TESTS -- //

describe('the calc verb', () => {
	it('is a read verb the assistant may call, with a description that teaches its use', () => {
		const v = verbByName('calc');
		expect(v).toMatchObject({ kind: 'read', agent: true });
		expect(v?.description).toMatch(/exact/);
		expect(v?.description).toMatch(/pmt/);
		expect(v?.description).toMatch(/line1/);
		const tool = buildTools().find((t) => t.name === 'calc');
		expect(tool).toMatchObject({ kind: 'read', taints: false });
		expect(JSON.stringify(tool?.parameters)).not.toMatch(/user_?id/i);
	});

	it('returns exact values, rounded values for reading, and the line numbers and names', async () => {
		const out = await run(agent, [
			{ name: 'pay', expr: '25000' },
			{ expr: '1/3*3' },
			{ expr: "add_days('2026-10-27', 5)" }
		]);
		expect(out.lines[0]).toMatchObject({
			line: 1,
			name: 'pay',
			ok: true,
			type: 'number',
			value: '25000'
		});
		expect(out.lines[1]).toMatchObject({
			ok: true,
			value: '0.9999999999999999999999999999999999999999',
			shown: '1'
		});
		expect(out.lines[2]).toMatchObject({ type: 'date', value: '2026-11-01' });
	});

	it('writes a line as money through the currency table: its own unit by default, or the smallest unit', async () => {
		const out = await run(agent, [
			{ expr: '1234.565', currency: 'PHP' },
			{ expr: '180', currency: 'JPY' },
			{ expr: '1.5', currency: 'KWD' },
			{ expr: '12345', currency: 'USD', unit: 'minor' },
			{ expr: '100 * 5%', currency: 'PHP', unit: 'major' }
		]);
		expect(out.lines[0]).toMatchObject({ minor: 123457, money: '₱1,234.57' });
		expect(out.lines[1]).toMatchObject({ minor: 180 });
		expect(out.lines[2]).toMatchObject({ minor: 1500 });
		expect(out.lines[3]).toMatchObject({ minor: 12345 });
		expect(String(out.lines[3]?.money)).toContain('123.45');
		expect(out.lines[4]).toMatchObject({ minor: 500, money: '₱5.00' });
	});

	it('says why a line has no money form, and no integer is a float', async () => {
		const out = await run(agent, [
			{ expr: "'2026-10-27'", currency: 'PHP' },
			{ expr: '1e30', currency: 'PHP' }
		]);
		expect(out.lines[0]).toMatchObject({ ok: true, note: expect.stringMatching(/date/) });
		expect(out.lines[1]).toMatchObject({ ok: true, note: expect.stringMatching(/too large/) });
		expect(out.lines[1]).not.toHaveProperty('minor');
	});

	it('reports a failed line with its place, and works out the others', async () => {
		const out = await run(person, [{ expr: '1 / 0' }, { expr: '2 + 2' }]);
		expect(out.lines[0]).toMatchObject({
			ok: false,
			line: 1,
			position: 2,
			error: expect.stringMatching(/zero/)
		});
		expect(out.lines[1]).toMatchObject({ ok: true, value: '4' });
	});

	it('refuses a key it does not know (a forged user id), too many lines, none, and a bad currency', async () => {
		await expect(
			invokeVerb(agent, 'calc', { lines: [{ expr: '1' }], userId: 'someone-else' })
		).rejects.toMatchObject({ code: 'INVALID' });
		await expect(
			invokeVerb(agent, 'calc', { lines: [{ expr: '1', user_id: 'x' }] })
		).rejects.toMatchObject({ code: 'INVALID' });
		await expect(
			run(
				agent,
				Array.from({ length: 61 }, () => ({ expr: '1' }))
			)
		).rejects.toMatchObject({
			code: 'INVALID'
		});
		await expect(run(agent, [])).rejects.toMatchObject({ code: 'INVALID' });
		await expect(run(agent, [{ expr: '1', currency: 'ZZZ' }])).rejects.toMatchObject({
			code: 'INVALID'
		});
		await expect(run(agent, [{ expr: 'x'.repeat(501) }])).rejects.toMatchObject({
			code: 'INVALID'
		});
	});

	it('answers an unknown caller with a refusal and never works out anything', async () => {
		await expect(
			invokeVerb({ handle, actor: { userId: '', kind: 'agent' } }, 'calc', {
				lines: [{ expr: '1' }]
			})
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
	});
});
