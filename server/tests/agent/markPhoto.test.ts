// MARK FROM A CHAT PHOTO (BTL-20261031-1011): THE ASSISTANT PROPOSES A CROP AS A CARD; ONLY THE PERSON'S PHONE CAN SUPPLY THE PICTURE WITH THE APPROVAL

// -- TYPES -- //
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { buildTools } from '../../src/lib/server/agent/tools';
import { agentAction, auditEvent, picture, requestLog } from '../../src/lib/server/db/schema';
import { withUser } from '../../src/lib/server/db/tenant';
import { createAction, decideAction } from '../../src/lib/server/ops/actions';
import { archiveAccount, listAccounts } from '../../src/lib/server/ops/accounts';
import { createBill, updateBill } from '../../src/lib/server/ops/bills';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { cardEvents, play, seedPerson, stubModel, toolEvents } from './support';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]).toString(
	'base64'
);
const IMG = { mediaType: 'image/jpeg' as const, data: 'AAAA' };
const BOX = { x: 0.1, y: 0.1, width: 0.5, height: 0.5, photo: 1 };

// -- STATES -- //

let t: TestDb;

// -- FUNCTIONS -- //

const agentOf = (f: Awaited<ReturnType<typeof seedPerson>>) => ({
	handle: t.handle,
	actor: { userId: f.userId, kind: 'agent' as const, tool: 'test' }
});
const call = (args: Record<string, unknown>) =>
	stubModel([
		{ calls: [['mark_from_photo', { target: 'account', name: 'GCash', ...BOX, ...args }]] }
	]);

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('the mark_from_photo tool', () => {
	it('is offered with no picture or id field', () => {
		const tool = buildTools().find((x) => x.name === 'mark_from_photo');
		expect(tool?.kind).toBe('gated');
		const props = Object.keys(
			(tool?.parameters as { properties: Record<string, unknown> }).properties
		);
		expect(props).not.toContain('imageData');
		expect(props).not.toContain('accountId');
		expect(props).not.toContain('imageId');
		expect(props).toEqual(
			expect.arrayContaining(['target', 'name', 'photo', 'x', 'y', 'width', 'height'])
		);
	});

	it('always becomes a card when a photo is in the message, and changes nothing', async () => {
		const f = await seedPerson(t);
		const events = await play({
			f,
			model: call({}),
			text: 'use this for GCash',
			images: [IMG]
		});
		expect(cardEvents(events)).toHaveLength(1);
		expect(cardEvents(events)[0]?.summary).toContain('photo 1');
		// The app is told which card the phone must finish itself, and no other card carries a verb
		expect(cardEvents(events)[0]?.verb).toBe('mark_from_photo');
		expect(toolEvents(events)[0]?.status).toBe('needs_approval');
		const accounts = await listAccounts(f.ctx);
		expect(accounts.every((a) => a.imageId === null)).toBe(true);
	});

	it('also works from the text read from a photo when the picture itself was not used', async () => {
		const f = await seedPerson(t);
		const events = await play({
			f,
			model: call({}),
			text: 'use this for GCash',
			ocrTexts: ['GCash logo']
		});
		expect(cardEvents(events)).toHaveLength(1);
	});

	it('refuses a photo number the message did not carry, and a message with no photo', async () => {
		const f = await seedPerson(t);
		const none = await play({ f, model: call({}), text: 'make it nicer' });
		expect(cardEvents(none)).toHaveLength(0);
		expect(toolEvents(none)[0]?.message).toContain('no photo');
		const high = await play({
			f,
			model: call({ photo: 2 }),
			text: 'this one',
			images: [IMG]
		});
		expect(cardEvents(high)).toHaveLength(0);
		expect(toolEvents(high)[0]?.message).toContain('photo 2 does not exist');
	});

	it('refuses a box outside the photo and a name that does not exist', async () => {
		const f = await seedPerson(t);
		const wide = await play({
			f,
			model: call({ x: 0.7, width: 0.6 }),
			text: 'x',
			images: [IMG]
		});
		expect(cardEvents(wide)).toHaveLength(0);
		const nobody = await play({
			f,
			model: call({ name: 'Nowhere Bank' }),
			text: 'x',
			images: [IMG]
		});
		expect(cardEvents(nobody)).toHaveLength(0);
		expect(toolEvents(nobody)[0]?.message).toContain('Nowhere Bank');
	});

	it('is refused outright when the assistant calls it directly', async () => {
		const f = await seedPerson(t);
		await expect(
			invokeVerb(agentOf(f), 'mark_from_photo', { target: 'account', name: 'GCash', ...BOX })
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
	});
});

describe('approving a photo card', () => {
	const makeCard = async (
		f: Awaited<ReturnType<typeof seedPerson>>,
		target: 'account' | 'bill' = 'account'
	) =>
		createAction(agentOf(f), {
			verb: 'mark_from_photo',
			args: { target, name: target === 'account' ? 'GCash' : 'Rent', ...BOX }
		});

	it('refuses the assistant sending the picture itself', async () => {
		const f = await seedPerson(t);
		await expect(
			createAction(agentOf(f), {
				verb: 'mark_from_photo',
				args: { target: 'account', name: 'GCash', ...BOX, imageData: PNG }
			})
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('applies the picture the phone sends, as the person, and keeps it off the card', async () => {
		const f = await seedPerson(t);
		const card = await makeCard(f);
		const done = await decideAction(f.ctx, {
			actionId: card.actionId,
			decision: 'approve',
			imageData: PNG
		});
		expect(done.status).toBe('applied');
		const gcash = (await listAccounts(f.ctx)).find((a) => a.id === f.gcash);
		expect(gcash?.imageId).toMatch(/^[0-9a-f-]{36}$/);
		const rows = await withUser(t.handle, f.userId, (tx) =>
			tx.select().from(picture).where(eq(picture.userId, f.userId))
		);
		expect(rows).toHaveLength(1);
		// The card row holds the plan only: no bytes in its arguments or its result
		const stored = await withUser(t.handle, f.userId, (tx) =>
			tx.select().from(agentAction).where(eq(agentAction.id, card.actionId))
		);
		expect(JSON.stringify(stored[0])).not.toContain(PNG);
	});

	it('applies to a bill too', async () => {
		const f = await seedPerson(t);
		const card = await makeCard(f, 'bill');
		const done = await decideAction(f.ctx, {
			actionId: card.actionId,
			decision: 'approve',
			imageData: PNG
		});
		expect(done.status).toBe('applied');
	});

	it('fails with a clear reason when no picture comes, and can be approved again with one', async () => {
		const f = await seedPerson(t);
		const card = await makeCard(f);
		const first = await decideAction(f.ctx, { actionId: card.actionId, decision: 'approve' });
		expect(first.status).toBe('failed');
		expect(JSON.stringify(first.result)).toContain('phone');
		const again = await decideAction(f.ctx, {
			actionId: card.actionId,
			decision: 'approve',
			imageData: PNG
		});
		expect(again.status).toBe('applied');
	});

	it('refuses a bad picture and a picture sent with another kind of card', async () => {
		const f = await seedPerson(t);
		const card = await makeCard(f);
		const bad = await decideAction(f.ctx, {
			actionId: card.actionId,
			decision: 'approve',
			imageData: Buffer.from('not a picture at all').toString('base64')
		});
		expect(bad.status).toBe('failed');
		const other = await createAction(agentOf(f), {
			verb: 'account_create',
			args: { name: 'Another', kind: 'bank' }
		});
		await expect(
			decideAction(f.ctx, { actionId: other.actionId, decision: 'approve', imageData: PNG })
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('does nothing when the card is rejected', async () => {
		const f = await seedPerson(t);
		const card = await makeCard(f);
		const no = await decideAction(f.ctx, { actionId: card.actionId, decision: 'reject' });
		expect(no.status).toBe('rejected');
		expect((await listAccounts(f.ctx)).every((a) => a.imageId === null)).toBe(true);
	});
});

describe('approving a photo card: the edges', () => {
	const makeCard = (
		f: Awaited<ReturnType<typeof seedPerson>>,
		target: 'account' | 'bill' = 'account',
		name = target === 'account' ? 'GCash' : 'Rent'
	) => createAction(agentOf(f), { verb: 'mark_from_photo', args: { target, name, ...BOX } });
	let n = 0;
	const req = (f: Awaited<ReturnType<typeof seedPerson>>) => ({
		...f.ctx,
		requestId: `mark-edge-${++n}`
	});
	const rent = (f: Awaited<ReturnType<typeof seedPerson>>) =>
		createBill(req(f), {
			name: 'Rent',
			category: 'bills',
			accountId: f.rcbc,
			kind: 'fixed',
			amount: 500_000,
			schedule: { kind: 'monthly', day: 5 },
			weekendRule: 'none',
			deferrable: false
		});

	it('an expired card is closed and writes nothing, even with a picture', async () => {
		const f = await seedPerson(t);
		const card = await makeCard(f);
		await withUser(t.handle, f.userId, (tx) =>
			tx
				.update(agentAction)
				.set({ expiresAt: new Date(Date.now() - 60_000) })
				.where(eq(agentAction.id, card.actionId))
		);
		const done = await decideAction(f.ctx, {
			actionId: card.actionId,
			decision: 'approve',
			imageData: PNG
		});
		expect(done.status).toBe('expired');
		expect((await listAccounts(f.ctx)).every((a) => a.imageId === null)).toBe(true);
	});

	it('a second approval of an applied card is refused and changes nothing', async () => {
		const f = await seedPerson(t);
		const card = await makeCard(f);
		await decideAction(f.ctx, { actionId: card.actionId, decision: 'approve', imageData: PNG });
		const before = (await listAccounts(f.ctx)).find((a) => a.id === f.gcash)?.imageId;
		await expect(
			decideAction(f.ctx, { actionId: card.actionId, decision: 'approve', imageData: PNG })
		).rejects.toMatchObject({ code: 'CONFLICT' });
		expect((await listAccounts(f.ctx)).find((a) => a.id === f.gcash)?.imageId).toBe(before);
	});

	it("another person cannot answer someone else's card", async () => {
		const f = await seedPerson(t);
		const other = await seedPerson(t);
		const card = await makeCard(f);
		await expect(
			decideAction(other.ctx, { actionId: card.actionId, decision: 'approve', imageData: PNG })
		).rejects.toMatchObject({ code: 'NOT_FOUND' });
		expect((await listAccounts(f.ctx)).every((a) => a.imageId === null)).toBe(true);
	});

	it('prefers the live bill of a name, and refuses when two live ones share it', async () => {
		const f = await seedPerson(t);
		const twin = await rent(f);
		// Two live bills called Rent: the card cannot know which, so it fails and writes nothing
		const clash = await makeCard(f, 'bill');
		const failed = await decideAction(f.ctx, {
			actionId: clash.actionId,
			decision: 'approve',
			imageData: PNG
		});
		expect(failed.status).toBe('failed');
		expect(JSON.stringify(failed.result)).toContain('More than one');
		// Switched off, the twin steps aside and the live Rent gets the picture
		await updateBill(req(f), { billId: twin.id, active: false });
		const ok = await makeCard(f, 'bill');
		const done = await decideAction(f.ctx, {
			actionId: ok.actionId,
			decision: 'approve',
			imageData: PNG
		});
		expect(done.status).toBe('applied');
	});

	it('still finds a hidden account when nothing live has the name', async () => {
		const f = await seedPerson(t);
		await archiveAccount(req(f), { accountId: f.maya });
		const card = await makeCard(f, 'account', 'Maya');
		const done = await decideAction(f.ctx, {
			actionId: card.actionId,
			decision: 'approve',
			imageData: PNG
		});
		expect(done.status).toBe('applied');
	});

	it('leaves no picture bytes in the request log or the audit trail', async () => {
		const f = await seedPerson(t);
		const card = await makeCard(f);
		await decideAction(f.ctx, { actionId: card.actionId, decision: 'approve', imageData: PNG });
		const logs = await withUser(t.handle, f.userId, (tx) =>
			tx.select().from(requestLog).where(eq(requestLog.userId, f.userId))
		);
		const trail = await withUser(t.handle, f.userId, (tx) =>
			tx.select().from(auditEvent).where(eq(auditEvent.userId, f.userId))
		);
		expect(logs.length).toBeGreaterThan(0);
		expect(trail.length).toBeGreaterThan(0);
		expect(JSON.stringify(logs)).not.toContain(PNG);
		expect(JSON.stringify(trail)).not.toContain(PNG);
	});
});
