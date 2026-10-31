// MARK FROM THE WEB (BTL-20261031-1334): THE ASSISTANT PROPOSES A LOGO LOOKUP AS A CARD; THE PHONE DOWNLOADS, CUTS AND SENDS THE PICTURE WITH THE APPROVAL

// -- TYPES -- //
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { buildTools } from '../../src/lib/server/agent/tools';
import { createAction, decideAction } from '../../src/lib/server/ops/actions';
import { listAccounts } from '../../src/lib/server/ops/accounts';
import { invokeVerb } from '../../src/lib/server/ops/registry';
import { cardEvents, play, seedPerson, stubModel, toolEvents } from './support';
import { createTestDb } from '../support/testDb';

// -- CONSTANTS -- //

const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]).toString(
	'base64'
);

// -- STATES -- //

let t: TestDb;

// -- FUNCTIONS -- //

const agentOf = (f: Awaited<ReturnType<typeof seedPerson>>) => ({
	handle: t.handle,
	actor: { userId: f.userId, kind: 'agent' as const, tool: 'test' }
});
const call = (args: Record<string, unknown>) =>
	stubModel([
		{
			calls: [['mark_from_web', { target: 'account', name: 'GCash', domain: 'gcash.com', ...args }]]
		}
	]);

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('the mark_from_web tool', () => {
	it('is gated and offered with no picture or id field', () => {
		const tool = buildTools().find((x) => x.name === 'mark_from_web');
		expect(tool?.kind).toBe('gated');
		const props = Object.keys(
			(tool?.parameters as { properties: Record<string, unknown> }).properties
		);
		expect(props).not.toContain('imageData');
		expect(props).not.toContain('accountId');
		expect(props).toEqual(expect.arrayContaining(['target', 'name', 'domain', 'urls']));
	});

	it('becomes a card that names the domain, and changes nothing', async () => {
		const f = await seedPerson(t);
		const events = await play({ f, model: call({}), text: 'find a logo for GCash' });
		expect(cardEvents(events)).toHaveLength(1);
		expect(cardEvents(events)[0]?.summary).toContain('gcash.com');
		expect(cardEvents(events)[0]?.verb).toBe('mark_from_web');
		expect(toolEvents(events)[0]?.status).toBe('needs_approval');
		expect((await listAccounts(f.ctx)).every((a) => a.imageId === null)).toBe(true);
	});

	it('accepts plain https picture addresses', async () => {
		const f = await seedPerson(t);
		const events = await play({
			f,
			model: call({
				domain: undefined,
				urls: ['https://upload.wikimedia.org/wikipedia/commons/a/ab/GCash_logo.png']
			}),
			text: 'logo'
		});
		expect(cardEvents(events)).toHaveLength(1);
	});

	it('refuses a request with neither a domain nor an address', async () => {
		const f = await seedPerson(t);
		const events = await play({ f, model: call({ domain: undefined }), text: 'logo' });
		expect(cardEvents(events)).toHaveLength(0);
		expect(toolEvents(events)[0]?.message).toContain('domain');
	});

	it('refuses a domain that is not a plain public host name', async () => {
		const f = await seedPerson(t);
		for (const domain of [
			'localhost',
			'192.168.0.1',
			'https://gcash.com',
			'gcash.com/logo',
			'gcash.com:8080',
			'bank.internal'
		]) {
			const events = await play({ f, model: call({ domain }), text: 'logo' });
			expect(cardEvents(events), domain).toHaveLength(0);
		}
	});

	it('refuses addresses that could carry text out or reach the inside', async () => {
		const f = await seedPerson(t);
		for (const url of [
			'http://gcash.com/logo.png',
			'https://gcash.com/logo.png?balance=12345',
			'https://gcash.com/logo.png#frag',
			'https://127.0.0.1/logo.png',
			'https://user:pw@gcash.com/logo.png',
			'https://gcash.com:8443/logo.png'
		]) {
			const events = await play({ f, model: call({ urls: [url] }), text: 'logo' });
			expect(cardEvents(events), url).toHaveLength(0);
		}
	});

	it('refuses a name that does not exist', async () => {
		const f = await seedPerson(t);
		const events = await play({ f, model: call({ name: 'Nowhere Bank' }), text: 'logo' });
		expect(cardEvents(events)).toHaveLength(0);
		expect(toolEvents(events)[0]?.message).toContain('Nowhere Bank');
	});

	it('is refused outright when the assistant calls it directly', async () => {
		const f = await seedPerson(t);
		await expect(
			invokeVerb(agentOf(f), 'mark_from_web', {
				target: 'account',
				name: 'GCash',
				domain: 'gcash.com'
			})
		).rejects.toMatchObject({ code: 'FORBIDDEN' });
	});
});

describe('approving a web picture card', () => {
	const makeCard = (
		f: Awaited<ReturnType<typeof seedPerson>>,
		target: 'account' | 'bill' = 'account'
	) =>
		createAction(agentOf(f), {
			verb: 'mark_from_web',
			args: { target, name: target === 'account' ? 'GCash' : 'Rent', domain: 'gcash.com' }
		});

	it('refuses the assistant sending the picture itself', async () => {
		const f = await seedPerson(t);
		await expect(
			createAction(agentOf(f), {
				verb: 'mark_from_web',
				args: { target: 'account', name: 'GCash', domain: 'gcash.com', imageData: PNG }
			})
		).rejects.toMatchObject({ code: 'INVALID' });
	});

	it('applies the picture the phone sends, as the person', async () => {
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

	it('does nothing when the card is rejected', async () => {
		const f = await seedPerson(t);
		const card = await makeCard(f);
		const no = await decideAction(f.ctx, { actionId: card.actionId, decision: 'reject' });
		expect(no.status).toBe('rejected');
		expect((await listAccounts(f.ctx)).every((a) => a.imageId === null)).toBe(true);
	});
});

describe('mark_from_web after untrusted text', () => {
	it('allows a short plain domain but no picture addresses', async () => {
		const f = await seedPerson(t);
		const ok = await play({
			f,
			model: call({}),
			text: 'find a logo for GCash',
			ocrTexts: ['a receipt']
		});
		expect(cardEvents(ok)).toHaveLength(1);
		const urls = await play({
			f,
			model: call({ domain: undefined, urls: ['https://upload.wikimedia.org/a.png'] }),
			text: 'find a logo for GCash',
			ocrTexts: ['a receipt']
		});
		expect(cardEvents(urls)).toHaveLength(0);
		expect(toolEvents(urls)[0]?.message).toContain('Untrusted');
	});

	it('refuses a domain that could carry text out', async () => {
		const f = await seedPerson(t);
		for (const domain of [
			'balance-1234567-gcash.example.com',
			'a-b-c-d-e.example.com',
			`${'x'.repeat(40)}.com`
		]) {
			const events = await play({
				f,
				model: call({ domain }),
				text: 'logo',
				ocrTexts: ['a receipt']
			});
			expect(cardEvents(events), domain).toHaveLength(0);
		}
	});
});
