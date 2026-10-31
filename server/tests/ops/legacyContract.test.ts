// THE CONTRACT OF THE OLD APPS: THE REQUEST AND ANSWER SHAPES OF memory_wipe, memory_export, profile_set, notebook_get, notebook_edit (THE OVERVIEW PAGE OF AN EXTRA
// NOTEBOOK) AND sync_get (AN OLD CURSOR, NO REQUEST ID) MUST KEEP WORKING WHATEVER THE NEWER APP ADDS. NEW FIELDS MAY BE ADDED; NONE MAY GO OR CHANGE MEANING.

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { createNotebook } from '../../src/lib/server/ops/notebook';
import { sumMinor } from '../../src/lib/server/ops/shared';
import { createTestDb } from '../support/testDb';
import { seedPerson } from '../agent/support';

// -- STATES -- //

let t: TestDb;
let n = 0;

// -- FUNCTIONS -- //

const rid = () => `req-leg-${String(++n).padStart(6, '0')}`;
const write = (c: Ctx): Ctx => ({ ...c, requestId: rid() });
/** The caller as the oldest app sends it: no request id on a read. */
const bare = (c: Ctx): Ctx => ({ ...c, requestId: undefined });

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('memory_export', () => {
	it('keeps every key an old app reads and only adds new ones', async () => {
		const f = await seedPerson(t);
		const out = (await invokeVerb(bare(f.ctx), 'memory_export', {})) as Record<string, unknown>;
		expect(Object.keys(out)).toEqual(
			expect.arrayContaining(['exportedAt', 'profile', 'memory', 'finance'])
		);
		expect(Object.keys(out.memory as object)).toEqual(
			expect.arrayContaining(['facts', 'summaries', 'notebook', 'conversations'])
		);
		const finance = out.finance as Record<string, unknown[]>;
		for (const key of [
			'accounts',
			'incomeSchedules',
			'bills',
			'billPayments',
			'goals',
			'rules',
			'transactions',
			'balanceSnapshots',
			'splits'
		])
			expect(Array.isArray(finance[key]), key).toBe(true);
		expect(finance.accounts?.length).toBeGreaterThan(0);
		// What was added: wallets, per-date bill changes, settings and the schedule
		expect(Array.isArray(finance.accountWallets)).toBe(true);
		expect(Array.isArray(finance.billOverrides)).toBe(true);
		expect(Array.isArray(out.settings)).toBe(true);
		const schedule = out.schedule as Record<string, unknown>;
		for (const key of ['tasks', 'events', 'routines', 'reminders'])
			expect(Array.isArray(schedule[key]), key).toBe(true);
		// Never a secret
		expect(JSON.stringify(out)).not.toMatch(/pushToken|push_token|password|accessToken/i);
	});

	it('is the person only', async () => {
		const f = await seedPerson(t);
		await expect(
			invokeVerb({ ...write(f.ctx), actor: { ...f.ctx.actor, kind: 'agent' } }, 'memory_export', {})
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
	});
});

describe('memory_wipe', () => {
	it('still takes only {confirm: true}, refuses anything else, and is the person only', async () => {
		const f = await seedPerson(t);
		await expect(invokeVerb(write(f.ctx), 'memory_wipe', {})).rejects.toMatchObject({
			code: 'INVALID'
		});
		await expect(invokeVerb(write(f.ctx), 'memory_wipe', { confirm: false })).rejects.toMatchObject(
			{ code: 'INVALID' }
		);
		await expect(
			invokeVerb({ ...write(f.ctx), actor: { ...f.ctx.actor, kind: 'agent' } }, 'memory_wipe', {
				confirm: true
			})
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
		const done = (await invokeVerb(write(f.ctx), 'memory_wipe', { confirm: true })) as Record<
			string,
			unknown
		>;
		for (const key of ['facts', 'summaries', 'conversations'])
			expect(typeof done[key], key).toBe('number');
		// The finance data stays
		const accounts = (await invokeVerb(bare(f.ctx), 'accounts_list', {})) as unknown[];
		expect(accounts.length).toBeGreaterThan(0);
	});
});

describe('profile_set', () => {
	it('still saves persona, about and people from the old request, and shows in the export', async () => {
		const f = await seedPerson(t);
		const saved = await invokeVerb(write(f.ctx), 'profile_set', {
			persona: 'brief',
			about: 'Likes tea',
			people: ['Anna', 'Ben']
		});
		expect(saved).toEqual({ saved: true });
		const out = (await invokeVerb(bare(f.ctx), 'memory_export', {})) as {
			profile: { persona: string; about: string; people: string[] }[];
		};
		expect(out.profile[0]).toMatchObject({
			persona: 'brief',
			about: 'Likes tea',
			people: ['Anna', 'Ben']
		});
		// A field left out stays as it was
		await invokeVerb(write(f.ctx), 'profile_set', { about: 'Likes coffee' });
		const again = (await invokeVerb(bare(f.ctx), 'memory_export', {})) as typeof out;
		expect(again.profile[0]).toMatchObject({ persona: 'brief', about: 'Likes coffee' });
	});
});

describe('notebook_get and notebook_edit (legacy contract)', () => {
	type Edited = { notebook: string; version: number; section: string; changed: boolean };
	const text = async (c: Ctx, args: Record<string, unknown> = {}) =>
		((await invokeVerb(bare(c), 'notebook_get', args)) as { text: string }).text;

	it('read and edit the main notebook with the old request shapes', async () => {
		const f = await seedPerson(t);
		const before = (await invokeVerb(bare(f.ctx), 'notebook_get', {})) as {
			kind: string;
			version: number;
		};
		expect(before.kind).toBe('main');
		const added = (await invokeVerb(write(f.ctx), 'notebook_edit', {
			op: 'add',
			heading: 'People',
			line: 'Anna is my sister.'
		})) as Edited;
		expect(added).toMatchObject({ changed: true });
		expect(added.version).toBeGreaterThan(before.version);
		expect(await text(f.ctx)).toContain('Anna is my sister.');
		const replaced = (await invokeVerb(write(f.ctx), 'notebook_edit', {
			op: 'replace',
			find: 'Anna is my sister.',
			replacement: 'Anna is my younger sister.'
		})) as Edited;
		expect(replaced.changed).toBe(true);
		expect(await text(f.ctx)).toContain('younger sister');
		await invokeVerb(write(f.ctx), 'notebook_edit', {
			op: 'remove',
			find: 'Anna is my younger sister.'
		});
		expect(await text(f.ctx)).not.toContain('Anna');
	});

	it('see an extra notebook as its page titled Overview', async () => {
		const f = await seedPerson(t);
		await createNotebook(write(f.ctx), {
			title: 'Trip',
			summary: 'Flights and hotels',
			text: '# Flights\nCebu on the 5th'
		});
		const read = (await invokeVerb(bare(f.ctx), 'notebook_get', { notebook: 'Trip' })) as {
			kind: string;
			title: string;
			text: string;
		};
		expect(read).toMatchObject({ kind: 'extra', title: 'Trip' });
		expect(read.text).toContain('Cebu on the 5th');
		const edited = (await invokeVerb(write(f.ctx), 'notebook_edit', {
			notebook: 'Trip',
			op: 'add',
			heading: 'Hotels',
			line: 'Book the one near the pier.'
		})) as Edited;
		expect(edited.changed).toBe(true);
		expect(await text(f.ctx, { notebook: 'Trip' })).toContain('Book the one near the pier.');
		// The same text is on the page called Overview
		const outline = (await invokeVerb(bare(f.ctx), 'notebook_outline', {})) as unknown;
		expect(JSON.stringify(outline)).toContain('Overview');
	});
});

describe('sync_get', () => {
	it('answers an old cursor with no request id, and keeps every field the old app reads', async () => {
		const f = await seedPerson(t);
		const out = (await invokeVerb(bare(f.ctx), 'sync_get', { cursor: '2:1793000000000' })) as {
			cursor: string;
			changed: boolean;
			reminders?: unknown[];
			summary: Record<string, unknown>;
			serverTime: string;
		};
		expect(typeof out.cursor).toBe('string');
		expect(out.changed).toBe(true);
		expect(Array.isArray(out.reminders)).toBe(true);
		for (const key of [
			'total',
			'currency',
			'totalMissing',
			'ratesAsOf',
			'nextBill',
			'firstEventToday'
		])
			expect(out.summary, key).toHaveProperty(key);
		expect(Number.isInteger(out.summary.total)).toBe(true);
		const same = (await invokeVerb(bare(f.ctx), 'sync_get', { cursor: out.cursor })) as typeof out;
		expect(same.changed).toBe(false);
		expect(same.reminders).toBeUndefined();
	});
});

describe('amounts past the safe integer', () => {
	it('are refused at the edge, and a sum past it throws instead of losing digits', async () => {
		const f = await seedPerson(t);
		await expect(
			invokeVerb(write(f.ctx), 'expense_log', {
				accountId: f.rcbc,
				amount: Number.MAX_SAFE_INTEGER + 1,
				category: 'food'
			})
		).rejects.toMatchObject({ code: 'INVALID' });
		expect(sumMinor([Number.MAX_SAFE_INTEGER, 0])).toBe(Number.MAX_SAFE_INTEGER);
		expect(() => sumMinor([Number.MAX_SAFE_INTEGER, 1])).toThrow(/too large/);
		expect(() => sumMinor([-Number.MAX_SAFE_INTEGER, -1])).toThrow(/too large/);
		expect(sumMinor(['9007199254740000', 991, 0n])).toBe(9007199254740991);
	});
});
