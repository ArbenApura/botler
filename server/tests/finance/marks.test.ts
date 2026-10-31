// MARKS (BTL-20261031-0917): AN ICON OR A PICTURE ON AN ACCOUNT OR A BILL, OWNED BY ITS ROW, SET BY THE PERSON OR THE ASSISTANT

// -- TYPES -- //
import type { Ctx } from '../../src/lib/server/ops/context';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { picture, user } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { createAccount, deleteAccount, updateAccount } from '../../src/lib/server/ops/accounts';
import { createBill, deleteBill, updateBill } from '../../src/lib/server/ops/bills';
import { calendarRange } from '../../src/lib/server/ops/calendarRange';
import { accountBalances } from '../../src/lib/server/ops/ledger';
import { balanceSimulate } from '../../src/lib/server/ops/simulate';
import { previewDataReset, resetData } from '../../src/lib/server/ops/dataReset';
import { exportAll } from '../../src/lib/server/ops/memory';
import { getPicture } from '../../src/lib/server/ops/picture';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]).toString(
	'base64'
);
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 9, 9, 9, 9]).toString('base64');
const A = 'user_mrk_0001';
const B = 'user_mrk_0002';

// -- STATES -- //

let t: TestDb;
let counter = 0;

// -- FUNCTIONS -- //

const person = (id: string): Ctx => ({ handle: t.handle, actor: { userId: id, kind: 'person' } });
const agent = (id: string): Ctx => ({
	handle: t.handle,
	actor: { userId: id, kind: 'agent', tool: 'test' }
});
const as = (c: Ctx): Ctx => ({ ...c, requestId: `req-mrk-${String(++counter).padStart(6, '0')}` });
const pictures = (id: string) =>
	withUser(t.handle, id, (tx) => tx.select().from(picture).where(eq(picture.userId, id)));
const schedule = { kind: 'monthly', day: 5 } as const;

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	await t.handle.db.insert(user).values([
		{ id: A, name: 'A', email: 'a-mrk@example.com' },
		{ id: B, name: 'B', email: 'b-mrk@example.com' }
	]);
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('the mark of an account', () => {
	it('takes an icon on create and refuses a key outside the catalogue', async () => {
		const row = await createAccount(as(person(A)), {
			name: 'Rent pot',
			kind: 'bank',
			icon: 'home'
		});
		expect(row).toMatchObject({ icon: 'home', imageId: null });
		await expect(
			createAccount(as(person(A)), { name: 'Bad', kind: 'bank', icon: 'unicorn' as never })
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('stores a picture the person sends, returns only its id, and serves it by id', async () => {
		const row = await createAccount(as(person(A)), { name: 'Photo', kind: 'bank', imageData: PNG });
		expect(row.imageId).toMatch(/^[0-9a-f-]{36}$/);
		expect(row.icon).toBeNull();
		expect(JSON.stringify(row)).not.toContain(PNG);
		const got = await getPicture(person(A), { imageId: row.imageId });
		expect(got).toMatchObject({ id: row.imageId, mime: 'image/png', data: PNG });
		// Another person cannot read it
		await expect(getPicture(person(B), { imageId: row.imageId })).rejects.toMatchObject({
			code: 'NOT_FOUND'
		});
	});

	it('swaps picture and icon, dropping the picture it no longer needs', async () => {
		const made = await createAccount(as(person(A)), { name: 'Swap', kind: 'bank', imageData: PNG });
		const before = (await pictures(A)).length;
		const next = await updateAccount(as(person(A)), { accountId: made.id, imageData: JPEG });
		expect(next.imageId).not.toBe(made.imageId);
		expect((await pictures(A)).length).toBe(before);
		const iconed = await updateAccount(as(person(A)), { accountId: made.id, icon: 'bolt' });
		expect(iconed).toMatchObject({ icon: 'bolt', imageId: null });
		expect((await pictures(A)).length).toBe(before - 1);
		const back = await updateAccount(as(person(A)), { accountId: made.id, imageData: PNG });
		expect(back).toMatchObject({ icon: null });
		const cleared = await updateAccount(as(person(A)), { accountId: made.id, clearImage: true });
		expect(cleared).toMatchObject({ icon: null, imageId: null });
		expect((await pictures(A)).length).toBe(before - 1);
	});

	it('refuses a bad picture, both a picture and an icon, and a picture with a clear', async () => {
		const acc = await createAccount(as(person(A)), { name: 'Strict', kind: 'bank' });
		const call = (extra: Record<string, unknown>) =>
			updateAccount(as(person(A)), { accountId: acc.id, ...extra } as never);
		await expect(call({ imageData: 'not base64!' })).rejects.toMatchObject({ code: 'INVALID' });
		await expect(
			call({ imageData: Buffer.from('plain text file!').toString('base64') })
		).rejects.toMatchObject({ code: 'INVALID' });
		await expect(call({ imageData: PNG, icon: 'home' })).rejects.toMatchObject({ code: 'INVALID' });
		await expect(call({ imageData: PNG, clearImage: true })).rejects.toMatchObject({
			code: 'INVALID'
		});
	});

	it('drops the picture with the account, and returns the removed account without an image id', async () => {
		const acc = await createAccount(as(person(A)), { name: 'Goes', kind: 'cash', imageData: PNG });
		const before = (await pictures(A)).length;
		const gone = await deleteAccount(as(person(A)), { accountId: acc.id });
		expect(gone).toMatchObject({ deleted: true, account: { imageId: null } });
		expect((await pictures(A)).length).toBe(before - 1);
	});
});

describe('the mark of a bill', () => {
	it('takes an icon or a picture, and drops the picture when the bill goes', async () => {
		const acc = await createAccount(as(person(A)), { name: 'Pays', kind: 'bank' });
		const made = await createBill(as(person(A)), {
			name: 'Meralco',
			category: 'utilities',
			accountId: acc.id,
			kind: 'fixed',
			amount: 250_000,
			schedule,
			icon: 'bolt'
		});
		expect(made).toMatchObject({ icon: 'bolt', imageId: null });
		const withPhoto = await updateBill(as(person(A)), { billId: made.id, imageData: JPEG });
		expect(withPhoto).toMatchObject({ icon: null });
		expect(withPhoto.imageId).toBeTruthy();
		const before = (await pictures(A)).length;
		await deleteBill(as(person(A)), { billId: made.id });
		expect((await pictures(A)).length).toBe(before - 1);
	});
});

describe('where the mark shows', () => {
	it('rides on calendar bills (their own mark, else the account mark), paydays and balances, and on the simulation for the app', async () => {
		const acc = await createAccount(as(person(A)), {
			name: 'Marked pay',
			kind: 'bank',
			icon: 'wallet'
		});
		const own = await createBill(as(person(A)), {
			name: 'Own mark',
			category: 'other',
			accountId: acc.id,
			kind: 'fixed',
			amount: 100_00,
			schedule,
			icon: 'tv'
		});
		const plain = await createBill(as(person(A)), {
			name: 'No mark',
			category: 'other',
			accountId: acc.id,
			kind: 'fixed',
			amount: 100_00,
			schedule
		});
		const range = await calendarRange(person(A), { from: '2030-03-01', to: '2030-03-31' });
		const bills = range.items.filter((i) => i.type === 'bill');
		expect(bills.find((i) => i.id === own.id)).toMatchObject({ icon: 'tv', imageId: null });
		expect(bills.find((i) => i.id === plain.id)).toMatchObject({ icon: 'wallet', imageId: null });
		const balances = await accountBalances(person(A));
		expect(balances.find((b) => b.id === acc.id)).toMatchObject({ icon: 'wallet', imageId: null });
		const sim = await balanceSimulate(person(A), { from: '2030-03-01', to: '2030-03-31' });
		expect(sim.marks?.accounts[acc.id]).toEqual({ icon: 'wallet', imageId: null });
		expect(sim.marks?.bills[own.id]).toEqual({ icon: 'tv', imageId: null });
		// The assistant's answer carries no marks
		const forAgent = await balanceSimulate(agent(A), { from: '2030-03-01', to: '2030-03-31' });
		expect(forAgent.marks).toBeUndefined();
	});
});

describe('older apps', () => {
	it('keep working: payloads without the new keys change nothing about the mark', async () => {
		const acc = await createAccount(as(person(A)), { name: 'Old app', kind: 'bank', icon: 'star' });
		const renamed = await invokeVerb(as(person(A)), 'account_update', {
			accountId: acc.id,
			name: 'Old app 2',
			expectVersion: acc.version
		});
		expect(renamed).toMatchObject({ name: 'Old app 2', icon: 'star', imageId: null });
		const made = await invokeVerb(as(person(A)), 'account_create', {
			name: 'Old plain',
			kind: 'cash'
		});
		expect(made).toMatchObject({ icon: null, imageId: null });
	});
});

describe('the assistant', () => {
	it('may set and clear an icon, and clear a picture, but never send one', async () => {
		const acc = await createAccount(as(person(A)), {
			name: 'Agent made',
			kind: 'bank',
			imageData: PNG
		});
		const set = await invokeVerb(as(agent(A)), 'account_update', {
			accountId: acc.id,
			icon: 'piggy'
		});
		expect(set).toMatchObject({ icon: 'piggy', imageId: null });
		await expect(
			invokeVerb(as(agent(A)), 'account_update', { accountId: acc.id, imageData: PNG })
		).rejects.toMatchObject({ code: 'INVALID' });
		await expect(
			invokeVerb(as(agent(A)), 'account_create', { name: 'Sneaky', kind: 'bank', imageData: PNG })
		).rejects.toMatchObject({ code: 'INVALID' });
		await expect(
			invokeVerb(as(agent(A)), 'account_update', { accountId: acc.id, imageId: acc.imageId })
		).rejects.toMatchObject({ code: 'INVALID' });
		// The service itself refuses a picture from the assistant even when the schema is bypassed
		await expect(
			updateAccount(as(agent(A)), { accountId: acc.id, imageData: PNG })
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
		await updateAccount(as(person(A)), { accountId: acc.id, imageData: PNG });
		const cleared = await invokeVerb(as(agent(A)), 'account_update', {
			accountId: acc.id,
			clearImage: true
		});
		expect(cleared).toMatchObject({ imageId: null });
	});

	it('cannot read a picture: picture_get is for the app only', async () => {
		const acc = await createAccount(as(person(A)), {
			name: 'Hidden',
			kind: 'bank',
			imageData: PNG
		});
		await expect(
			invokeVerb(as(agent(A)), 'picture_get', { imageId: acc.imageId })
		).rejects.toBeTruthy();
	});
});

describe('the export and the reset', () => {
	it('exports the pictures beside the accounts', async () => {
		const out = (await exportAll(person(A))) as { finance: { pictures: { id: string }[] } };
		expect(out.finance.pictures.length).toBeGreaterThan(0);
	});

	it('erases the pictures with the money, for the money scope and for everything', async () => {
		await createAccount(as(person(B)), { name: 'Reset me', kind: 'bank', imageData: PNG });
		expect((await pictures(B)).length).toBe(1);
		const preview = await previewDataReset(as(person(B)), { scope: 'money' });
		await resetData(as(person(B)), { scope: 'money', token: preview.token, typed: 'RESET' });
		expect((await pictures(B)).length).toBe(0);
		await createAccount(as(person(B)), { name: 'Again', kind: 'bank', imageData: PNG });
		const all = await previewDataReset(as(person(B)), { scope: 'everything' });
		await resetData(as(person(B)), { scope: 'everything', token: all.token, typed: 'RESET' });
		expect((await pictures(B)).length).toBe(0);
	});
});
