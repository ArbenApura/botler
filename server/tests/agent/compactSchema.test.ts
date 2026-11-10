// THE COMPACT TOOL SCHEMAS (WHAT THE MODEL READS) AND THE TRIMMED TOOL RESULTS. Compaction must never take a branch or a field away: the verbs still
// check every call with their own strict input, so a valid call for any kind still passes and a wrong field is still refused.

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
import { z } from 'zod';
// -- MODULES -- //
import { buildTools, toParameters } from '../../src/lib/server/agent/tools';
import { trimForModel } from '../../src/lib/server/agent/turn';
import { paydayScheduleInput, recurrenceInput, scheduleInput } from '../../src/lib/server/db/zod';
import { agentVerbs } from '../../src/lib/server/ops/registry';

// -- TYPES -- //

type Json = Record<string, unknown>;

// -- FUNCTIONS -- //

const isObj = (v: unknown): v is Json => !!v && typeof v === 'object' && !Array.isArray(v);

/** The schema as zod writes it, before any slimming or compaction. */
const raw = (schema: z.ZodType): Json =>
	z.toJSONSchema(schema, { unrepresentable: 'any', io: 'input' }) as Json;

/**
 * Walks the original schema next to the compact one. Wherever the original has a oneOf of kinds, the compact node must list every kind in
 * order, hold every field of every branch, and write each field into its kind's guide line, with ? for the optional ones.
 */
function checkUnions(original: unknown, compact: unknown, where: string, seen: { unions: number }) {
	if (Array.isArray(original)) {
		original.forEach((o, i) => checkUnions(o, (compact as unknown[])[i], `${where}[${i}]`, seen));
		return;
	}
	if (!isObj(original)) return;
	const comp = compact as Json;
	if (Array.isArray(original.oneOf)) {
		const branches = original.oneOf as Json[];
		const props = (branches[0]?.properties ?? {}) as Json;
		const key = Object.keys(props).find((k) =>
			branches.every(
				(b) => typeof ((b.properties as Json)?.[k] as Json | undefined)?.const === 'string'
			)
		);
		if (key) {
			seen.unions++;
			const kinds = branches.map((b) => String(((b.properties as Json)[key] as Json).const));
			const cprops = comp.properties as Json;
			expect((cprops[key] as Json).enum, where).toEqual(kinds);
			expect(comp.required, where).toEqual([key]);
			const lines = String(comp.description).split('\n');
			for (const [i, b] of branches.entries()) {
				const line = lines.find((l) => l.startsWith(`${kinds[i]}: `));
				expect(line, `${where} ${kinds[i]}`).toBeTruthy();
				const required = new Set((b.required as string[] | undefined) ?? []);
				for (const name of Object.keys(b.properties as Json)) {
					if (name === key) continue;
					expect(cprops[name], `${where}.${name}`).toBeTruthy();
					expect(line, `${where} ${kinds[i]}.${name}`).toContain(
						`${name}${required.has(name) ? '' : '?'}:`
					);
				}
			}
			// Each branch's own fields are checked inside their nested schemas too
			for (const b of branches)
				for (const [name, sub] of Object.entries(b.properties as Json))
					if (name !== key) checkUnions(sub, cprops[name], `${where}.${name}`, seen);
			return;
		}
	}
	// Only fields that hold a nested schema are followed: slimming removes other keys (patterns, bounds) on purpose
	if (isObj(original.properties))
		for (const [name, sub] of Object.entries(original.properties))
			checkUnions(sub, (comp.properties as Json | undefined)?.[name], `${where}.${name}`, seen);
}

// -- TESTS -- //

describe('compact tool schemas', () => {
	it('keep every branch and every field of each union, and mark what is required, for all tools', () => {
		const seen = { unions: 0 };
		for (const v of agentVerbs()) {
			const compact = buildTools().find((t) => t.name === v.name)?.parameters;
			// Compare field by field on the properties only: slimming is checked by its own tests
			const original = raw(v.input);
			checkUnions(original, compact, v.name, seen);
		}
		// bill_create, bill_update, income_create, income_update, schedule_preview and the routines hold a union
		expect(seen.unions).toBeGreaterThanOrEqual(8);
	});

	it('give the same bytes on two builds', () => {
		expect(JSON.stringify(buildTools().map((t) => t.parameters))).toBe(
			JSON.stringify(buildTools().map((t) => t.parameters))
		);
		expect(toParameters(scheduleInput)).toEqual(toParameters(scheduleInput));
	});

	it('are smaller than the original and have no oneOf left in a kind union', () => {
		const json = JSON.stringify(buildTools().map((t) => t.parameters));
		expect(json).not.toContain('"oneOf"');
		// 33_750 since the icon on four account and bill tools (the enum of 40 keys): they measure 33_164, and the cap keeps about 600 of margin (32_750 before, since the ten page and library tools)
		// 34_700 since mark_from_web: it measures 34_037 and the cap keeps about 600 of margin
		// Health adds its own tools (BTL-20261105-0015): the cap is set again with the measured size when each phase lands
		// 45_300 since the workout, sleep, weight and check-in tools: they measure about 44_700 and the cap keeps about 600 of margin
		// 47_400 since the food nutrients (BTL-20261110-1532): the web and entryId meal items, the extra fields of an estimate, a label and food_edit, and food_brand_search measure 46_809, and the cap keeps about 600 of margin
		expect(json.length).toBeLessThan(47_400);
	});

	it('turn anyOf with null into a nullable type and drop a type beside a const', () => {
		const expense = buildTools().find((t) => t.name === 'expense_log')?.parameters as Json;
		const category = (expense.properties as Json).category as Json;
		expect(category.type).toEqual(['string', 'null']);
		expect(category.anyOf).toBeUndefined();
		expect(JSON.stringify(buildTools().map((t) => t.parameters))).not.toContain('"const"');
	});

	it('still let one valid input per schedule kind and per recurrence kind pass the verbs own check', () => {
		const schedules: unknown[] = [
			{ kind: 'semi_monthly', days: [15, 30] },
			{ kind: 'every_n_days', anchor: '2026-10-01', n: 14 },
			{ kind: 'monthly', day: 5 },
			{ kind: 'weekly', days: [3], everyWeeks: 2, anchor: '2026-10-28' },
			{ kind: 'nth_weekday', n: -1, weekday: 5 },
			{ kind: 'week_of_month', n: 1, basis: 'calendar', pick: 'window' },
			{ kind: 'day_range', from: 5, to: 10 },
			{ kind: 'yearly', month: 12, day: 25 },
			{ kind: 'once', date: '2026-12-25' }
		];
		for (const s of schedules)
			expect(scheduleInput.safeParse(s).success, JSON.stringify(s)).toBe(true);
		const recurrences: unknown[] = [
			{ freq: 'daily', time: '08:00' },
			{ freq: 'weekly', days: [1, 3], time: '08:00' },
			{ freq: 'monthly', day: 1, time: '08:00' },
			{ freq: 'every_n_days', anchor: '2026-10-01', n: 3, time: '08:00' },
			{ freq: 'schedule', schedule: { kind: 'monthly', day: 5 }, time: '08:00' }
		];
		for (const r of recurrences)
			expect(recurrenceInput.safeParse(r).success, JSON.stringify(r)).toBe(true);
	});

	it('still refuse a missing field of the chosen kind by name, and never keep a field of another kind', () => {
		const missing = scheduleInput.safeParse({ kind: 'weekly', day: 5 });
		expect(missing.success).toBe(false);
		expect(JSON.stringify(missing.error?.issues)).toMatch(/days/);
		// A field of another kind is not carried into the stored rule
		const parsed = scheduleInput.parse({ kind: 'monthly', day: 5, days: [1, 2] });
		expect(parsed).toEqual({ kind: 'monthly', day: 5 });
		// The model reads the allowed fields of every kind in the description it was given
		const preview = buildTools().find((t) => t.name === 'schedule_preview')?.parameters as Json;
		const guide = String(((preview.properties as Json).schedule as Json).description);
		expect(guide).toMatch(/monthly: .*day:int, everyMonths\?:int, anchorMonth\?:string/);
		// Only paydays and the preview take start, end and skipped dates: bills and reminders still strip them
		const limits = { startsOn: '2026-11-09', endsOn: '2026-12-31', skipDates: ['2026-11-16'] };
		for (const rule of [
			{ kind: 'weekly', days: [1] },
			{ kind: 'every_n_days', anchor: '2026-11-02', n: 7 },
			{ kind: 'monthly', day: 5 },
			{ kind: 'semi_monthly', days: [15, 30] },
			{ kind: 'nth_weekday', n: 1, weekday: 3 }
		]) {
			expect(paydayScheduleInput.parse({ ...rule, ...limits })).toEqual({ ...rule, ...limits });
			expect(scheduleInput.parse({ ...rule, ...limits })).toEqual(rule);
		}
	});

	it('still lets a tool find currency, toCurrency and toAmount wherever they sit', () => {
		const keys = new Set<string>();
		const walk = (s: unknown) => {
			if (Array.isArray(s)) s.forEach(walk);
			else if (isObj(s))
				for (const [k, v] of Object.entries(s)) {
					keys.add(k);
					walk(v);
				}
		};
		walk(buildTools().find((t) => t.name === 'transfer_record')?.parameters);
		for (const k of ['currency', 'toCurrency', 'toAmount']) expect(keys.has(k), k).toBe(true);
	});
});

describe('the rule tools (BTL-20261029-0119)', () => {
	it('let rule_propose and rule_update name the bill a rule saves for, and never carry a tenant column', () => {
		for (const name of ['rule_propose', 'rule_update']) {
			const text = JSON.stringify(buildTools().find((t) => t.name === name)?.parameters);
			expect(text, name).toContain('fundsBillId');
			expect(text, name).not.toMatch(/userId|user_id/);
		}
	});
});

describe('tool results for the model', () => {
	it('drop userId everywhere and the noise nulls, and keep every null that means something', () => {
		const result = {
			userId: 'u1',
			accounts: [
				{
					id: 'a',
					userId: 'u1',
					name: 'GCash',
					purpose: null,
					archivedAt: null,
					note: null,
					sortOrder: 0
				},
				{
					id: 'b',
					userId: 'u1',
					name: 'Maya',
					purpose: 'Savings',
					archivedAt: '2026-10-01T00:00:00Z'
				}
			],
			bill: { id: 'x', kind: 'variable', amount: null, amountMain: null },
			wallet: { currency: 'USD', value: null, rate: null },
			list: [null, 1]
		};
		const out = trimForModel(result) as Json;
		const text = JSON.stringify(out);
		expect(text).not.toContain('userId');
		expect(out.accounts).toEqual([
			{ id: 'a', name: 'GCash', sortOrder: 0 },
			{ id: 'b', name: 'Maya', purpose: 'Savings', archivedAt: '2026-10-01T00:00:00Z' }
		]);
		// A variable bill's missing amount and a wallet with no rate mean something and stay
		expect(out.bill).toEqual({ id: 'x', kind: 'variable', amount: null, amountMain: null });
		expect(out.wallet).toEqual({ currency: 'USD', value: null, rate: null });
		// An element of an array is never dropped
		expect(out.list).toEqual([null, 1]);
	});
});
