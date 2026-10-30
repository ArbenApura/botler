// REAL PICTURES TO THE ASSISTANT (BTL-20261030-0654): CHECKED BY THEIR OWN BYTES, GIVEN ONLY TO A HOST THAT READS PICTURES WHEN THE PERSON CHOSE
// THE PICTURE, NEVER MASKED OR MANGLED, NEVER ON A TEXT-ONLY WIRE, AND TAINTING THE TURN WHETHER OR NOT THERE IS TEXT

// -- TYPES -- //
import type { TurnEvent } from '../../src/lib/server/agent/turn';
import type { ChatImage } from '../../src/lib/server/proxy/types';
import type { CompletionRequest } from '../../src/lib/server/proxy/types';
import type { ModelClient } from '../../src/lib/server/proxy/deepseek';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { handleChat, chatInput } from '../../src/lib/server/agent/chat';
import {
	isBase64,
	MAX_IMAGE_SIDE,
	MAX_IMAGES,
	readImages,
	sniffImage
} from '../../src/lib/server/agent/images';
import { buildMessages } from '../../src/lib/server/agent/prompt';
import { listBills } from '../../src/lib/server/ops/bills';
import { setSettings } from '../../src/lib/server/ops/settings';
import {
	estimateJsonTokens,
	IMAGE_TOKENS,
	maskMessages,
	withoutImages
} from '../../src/lib/server/proxy/core';
import { createModelClient } from '../../src/lib/server/proxy/deepseek';
import { DEFAULT_LIMITS } from '../../src/lib/server/proxy/limits';
import { createMasker } from '../../src/lib/server/proxy/mask';
import { configureProviders } from '../../src/lib/server/proxy/provider';
import { createProviderRouter } from '../../src/lib/server/proxy/router';
import { play, seedPerson, stubModel, toolEvents } from './support';
import { createTestDb } from '../support/testDb';

// -- STATES -- //

let t: TestDb;
let n = 0;

// -- FUNCTIONS -- //

/** A real minimal JPEG header with a frame of the given size, padded: enough for the checks, not a picture anyone could see. */
function jpeg(width: number, height: number, pad = 64): Buffer {
	const frame = Buffer.alloc(19);
	frame[0] = 0xff;
	frame[1] = 0xc0;
	frame.writeUInt16BE(17, 2);
	frame[4] = 8;
	frame.writeUInt16BE(height, 5);
	frame.writeUInt16BE(width, 7);
	frame[9] = 3;
	return Buffer.concat([
		Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x04, 0x00, 0x00]),
		frame,
		Buffer.alloc(pad)
	]);
}

function png(width: number, height: number): Buffer {
	const b = Buffer.alloc(40);
	Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(b);
	b.writeUInt32BE(13, 8);
	b.write('IHDR', 12, 'latin1');
	b.writeUInt32BE(width, 16);
	b.writeUInt32BE(height, 20);
	return b;
}

function webp(width: number, height: number): Buffer {
	const b = Buffer.alloc(40);
	b.write('RIFF', 0, 'latin1');
	b.write('WEBP', 8, 'latin1');
	b.write('VP8X', 12, 'latin1');
	b.writeUIntLE(width - 1, 24, 3);
	b.writeUIntLE(height - 1, 27, 3);
	return b;
}

const b64 = (b: Buffer) => b.toString('base64');
/** A picture whose base64 holds a long run of digits and a card-like number, which a text masker would change. */
const digitsPicture = (): ChatImage => ({
	mediaType: 'image/jpeg',
	data: `${b64(jpeg(800, 600, 3000))}${'1234567890123456'.repeat(4)}`
});
const picture = (): ChatImage => ({ mediaType: 'image/jpeg', data: b64(jpeg(800, 600)) });

const base = { clientMessageId: 'pictures-test-0001', text: 'what is this' };

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
});

afterEach(() => configureProviders(null));

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('checking a picture by its bytes', () => {
	it('reads the type and size from a JPEG, a PNG and a WebP, ignoring what the client says', () => {
		const out = readImages([
			{ data: b64(jpeg(1200, 900)), mediaType: 'image/png' },
			{ data: b64(png(640, 480)) },
			{ data: b64(webp(300, 200)) }
		]);
		expect(out.map((i) => i.mediaType)).toEqual(['image/jpeg', 'image/png', 'image/webp']);
		expect(sniffImage(jpeg(1200, 900))).toMatchObject({ width: 1200, height: 900 });
		expect(sniffImage(webp(300, 200))).toMatchObject({ width: 300, height: 200 });
	});

	it('refuses what is not base64, not a picture, empty, or too large in pixels', () => {
		expect(isBase64('abcd')).toBe(true);
		expect(isBase64('ab cd')).toBe(false);
		expect(isBase64('abcde')).toBe(false);
		const refuse = (data: string) => () => readImages([{ data }]);
		expect(refuse('not base64 at all!!!!')).toThrow();
		expect(refuse(b64(Buffer.from('GIF89a plain text pretending to be a picture')))).toThrow();
		expect(refuse(b64(jpeg(MAX_IMAGE_SIDE + 1, 100)))).toThrow();
		expect(refuse(b64(png(100, MAX_IMAGE_SIDE + 1)))).toThrow();
		expect(refuse(b64(jpeg(0, 0)))).toThrow();
		// A header cut short reads past its end and is refused, not crashed on
		expect(refuse(b64(Buffer.from([0xff, 0xd8, 0xff, 0xe0])))).toThrow();
		expect(refuse(b64(jpeg(800, 600, 2_100_000)))).toThrow();
	});

	it('says nothing about the picture when it refuses', () => {
		const data = b64(Buffer.from('SECRET-PICTURE-CONTENT-0123456789'));
		let message = '';
		try {
			readImages([{ data }]);
		} catch (e) {
			message = e instanceof Error ? e.message : '';
		}
		expect(message).not.toContain('SECRET');
		expect(message).not.toContain(data);
	});

	it('limits the count, the size together and the keys of the body', () => {
		const one = { data: b64(jpeg(10, 10)) };
		expect(chatInput.safeParse({ ...base, images: Array(MAX_IMAGES).fill(one) }).success).toBe(
			true
		);
		expect(chatInput.safeParse({ ...base, images: Array(MAX_IMAGES + 1).fill(one) }).success).toBe(
			false
		);
		const big = { data: 'A'.repeat(1_400_000) };
		expect(chatInput.safeParse({ ...base, images: [big, big, big, big, big, big] }).success).toBe(
			false
		);
		expect(chatInput.safeParse({ ...base, images: [{ ...one, extra: 1 }] }).success).toBe(false);
		// An older app sends none and is accepted as before
		expect(chatInput.safeParse(base).success).toBe(true);
	});
});

describe('the pictures in the messages', () => {
	it('puts them on the last user message and says so in the words', () => {
		const messages = buildMessages({
			now: new Date(),
			history: [],
			userText: 'what is this',
			images: [picture(), picture()]
		});
		const last = messages.at(-1);
		expect(last && 'images' in last ? last.images : []).toHaveLength(2);
		expect(String(last?.content)).toContain('2 pictures are attached to this message.');
		const plain = buildMessages({ now: new Date(), history: [], userText: 'hi' }).at(-1);
		expect(plain && 'images' in plain).toBe(false);
	});

	it('is never changed by the masker, whatever digits its base64 holds', () => {
		const img = digitsPicture();
		const out = maskMessages(
			buildMessages({ now: new Date(), history: [], userText: 'x', images: [img] }),
			createMasker([])
		);
		const last = out.at(-1);
		expect(last && 'images' in last ? last.images?.[0]?.data : '').toBe(img.data);
	});

	it('counts a picture as a fixed number of tokens, not by its base64', () => {
		const messages = buildMessages({
			now: new Date(),
			history: [],
			userText: 'x',
			images: Array(6).fill(digitsPicture())
		});
		const withPics = estimateJsonTokens(messages);
		const without = estimateJsonTokens(withoutImages(messages));
		expect(withPics - without).toBeGreaterThanOrEqual(6 * IMAGE_TOKENS - 50);
		expect(withPics - without).toBeLessThanOrEqual(6 * IMAGE_TOKENS + 400);
	});

	it('counts a data URL image part of the DeepSeek wire the same way', () => {
		const url = `data:image/jpeg;base64,${'A'.repeat(900_000)}`;
		const wire = [{ role: 'user', content: [{ type: 'image_url', image_url: { url } }] }];
		const tokens = estimateJsonTokens(wire);
		expect(tokens).toBeGreaterThanOrEqual(IMAGE_TOKENS);
		expect(tokens).toBeLessThan(IMAGE_TOKENS + 100);
	});
});

describe('the wires', () => {
	it('gives DeepSeek the picture as an image part before the words', async () => {
		const seen: string[] = [];
		const fetchFn = (async (_url: string, init: RequestInit) => {
			seen.push(String(init.body));
			return new Response(
				JSON.stringify({
					choices: [{ message: { content: 'ok' }, finish_reason: 'stop' }],
					usage: { prompt_tokens: 5, completion_tokens: 1 }
				}),
				{ status: 200 }
			);
		}) as unknown as typeof fetch;
		const fx = await seedPerson(t);
		const img = picture();
		await createModelClient({
			apiKey: 'sk-test',
			baseUrl: 'https://model.test',
			model: 'deepseek-chat',
			limits: DEFAULT_LIMITS,
			fetch: fetchFn,
			sleep: async () => undefined
		}).complete(fx.ctx, {
			bucket: 'chat',
			messages: [{ role: 'user', content: 'what is this', images: [img] }]
		});
		const body = JSON.parse(seen[0] ?? '{}') as { messages: { role: string; content: unknown }[] };
		expect(body.messages[0]?.content).toEqual([
			{ type: 'image_url', image_url: { url: `data:image/jpeg;base64,${img.data}` } },
			{ type: 'text', text: 'what is this' }
		]);
		expect(seen[0]).not.toContain('"images"');
	});

	it('puts no picture on a system message of the DeepSeek wire', async () => {
		const seen: string[] = [];
		const fetchFn = (async (_url: string, init: RequestInit) => {
			seen.push(String(init.body));
			return new Response(
				JSON.stringify({
					choices: [{ message: { content: 'ok' }, finish_reason: 'stop' }],
					usage: { prompt_tokens: 5, completion_tokens: 1 }
				}),
				{ status: 200 }
			);
		}) as unknown as typeof fetch;
		const fx = await seedPerson(t);
		const img = picture();
		await createModelClient({
			apiKey: 'sk-test',
			baseUrl: 'https://model.test',
			model: 'deepseek-flash',
			limits: DEFAULT_LIMITS,
			fetch: fetchFn,
			sleep: async () => undefined
		}).complete(fx.ctx, {
			bucket: 'chat',
			messages: [{ role: 'system', content: 'sys', images: [img] }]
		});
		expect(seen[0]).not.toContain(img.data);
	});
});

describe('the router decides on every call', () => {
	async function viaRouter(
		mode: 'image' | 'text',
		available: 'deepseek'[] = ['deepseek'],
		vision: Record<'deepseek', boolean> = { deepseek: true }
	) {
		const fx = await seedPerson(t);
		configureProviders({ available, fallback: 'deepseek' });
		await setSettings(
			{ ...fx.ctx, requestId: `req-pic-${String(++n).padStart(5, '0')}` },
			{ modelProvider: 'deepseek', photoMode: mode }
		);
		const got: Record<string, CompletionRequest | undefined> = {};
		const stub = (name: string): ModelClient =>
			({
				complete: async (_c: unknown, req: CompletionRequest) => {
					got[name] = req;
					return { content: name };
				},
				stream: async function* (_c: unknown, req: CompletionRequest) {
					got[name] = req;
					yield { type: 'delta', text: name };
				}
			}) as unknown as ModelClient;
		const { client } = createProviderRouter({
			clientFor: (p) => stub(p),
			available: () => available,
			fallback: 'deepseek',
			vision
		});
		const req: CompletionRequest = {
			bucket: 'chat',
			messages: [{ role: 'user', content: 'hi', images: [picture()] }]
		};
		await client.complete(fx.ctx, req);
		const sees = (name: string) => {
			const first = got[name]?.messages[0];
			return first && 'images' in first ? first.images : undefined;
		};
		return { answered: Object.keys(got), deepseek: sees('deepseek') };
	}

	it('gives a DeepSeek person the picture on DeepSeek itself, the chat staying where it is', async () => {
		const r = await viaRouter('image');
		expect(r.answered).toEqual(['deepseek']);
		expect(r.deepseek).toHaveLength(1);
	});

	it('drops the picture when the person chose the text', async () => {
		const r = await viaRouter('text');
		expect(r.answered).toEqual(['deepseek']);
		expect(r.deepseek).toBeUndefined();
	});

	it('hands a host that cannot see no picture, also when it is the only one with a key', async () => {
		const r = await viaRouter('image', ['deepseek'], { deepseek: false });
		expect(r.answered).toEqual(['deepseek']);
		expect(r.deepseek).toBeUndefined();
	});

	it('leaves a message with no picture on the host the person chose', async () => {
		const fx = await seedPerson(t);
		configureProviders({ available: ['deepseek'], fallback: 'deepseek' });
		await setSettings(
			{ ...fx.ctx, requestId: `req-pic-${String(++n).padStart(5, '0')}` },
			{ modelProvider: 'deepseek', photoMode: 'image' }
		);
		const used: string[] = [];
		const { client } = createProviderRouter({
			clientFor: (p) =>
				({
					complete: async () => {
						used.push(p);
						return { content: p };
					}
				}) as unknown as ModelClient,
			available: () => ['deepseek'],
			fallback: 'deepseek'
		});
		await client.complete(fx.ctx, { bucket: 'chat', messages: [{ role: 'user', content: 'hi' }] });
		expect(used).toEqual(['deepseek']);
	});
});

describe('a chat message with pictures', () => {
	async function chat(mode: 'image' | 'text', extra: Record<string, unknown> = {}) {
		const fx = await seedPerson(t);
		configureProviders({ available: ['deepseek'], fallback: 'deepseek' });
		await setSettings(
			{ ...fx.ctx, requestId: `req-pic-${String(++n).padStart(5, '0')}` },
			{ modelProvider: 'deepseek', photoMode: mode }
		);
		const model = stubModel([{ say: 'I see it.' }]);
		const events: TurnEvent[] = [];
		for await (const e of handleChat(
			fx.ctx,
			{
				...base,
				clientMessageId: `pictures-chat-${String(++n).padStart(6, '0')}`,
				images: [{ data: picture().data }],
				...extra
			},
			{ model, provider: async () => 'deepseek', noMemory: true }
		))
			events.push(e);
		const user = model.requests[0]?.messages.at(-1);
		return { events, images: user && 'images' in user ? user.images : undefined, fx };
	}

	it('hands the picture over and says so, when the person chose it and the host reads it', async () => {
		const r = await chat('image');
		expect(r.images).toHaveLength(1);
		expect(r.events.find((e) => e.type === 'start')).toMatchObject({ usedImages: true });
	});

	it('hands nothing over, and says so, for the text choice', async () => {
		const r = await chat('text');
		expect(r.images).toBeUndefined();
		expect(r.events.find((e) => e.type === 'start')).toMatchObject({ usedImages: false });
	});

	it('hands nothing over when no host is set up on the server', async () => {
		const fx = await seedPerson(t);
		configureProviders(null);
		const model = stubModel([{ say: 'ok' }]);
		const events: TurnEvent[] = [];
		for await (const e of handleChat(
			fx.ctx,
			{
				...base,
				clientMessageId: `pictures-nohost-${String(++n).padStart(6, '0')}`,
				images: [{ data: picture().data }]
			},
			{ model, noMemory: true }
		))
			events.push(e);
		const user = model.requests[0]?.messages.at(-1);
		expect(user && 'images' in user ? user.images : undefined).toBeUndefined();
		expect(events.find((e) => e.type === 'start')).toMatchObject({ usedImages: false });
	});

	it('says nothing about pictures when there were none', async () => {
		const r = await chat('image', { images: undefined });
		expect(r.events.find((e) => e.type === 'start')).not.toHaveProperty('usedImages');
	});

	it('refuses a picture that is not one before the message is claimed', async () => {
		const fx = await seedPerson(t);
		await expect(
			(async () => {
				for await (const _ of handleChat(
					fx.ctx,
					{
						...base,
						clientMessageId: `pictures-bad-${++n}-00001`,
						images: [{ data: b64(Buffer.from('text, not a picture')) }]
					},
					{ model: stubModel([]) }
				));
			})()
		).rejects.toMatchObject({ code: 'INVALID' });
	});
});

describe('a turn that holds a picture', () => {
	it('taints with no text read from it, so a write becomes a card', async () => {
		const fx = await seedPerson(t);
		const model = stubModel([
			{ calls: [['bill_delete', { billId: fx.rentBillId }]] },
			{ say: 'A card.' }
		]);
		const events = await play({ f: fx, model, text: 'remove rent', images: [picture()] });
		expect(toolEvents(events)[0]).toMatchObject({ name: 'bill_delete', status: 'needs_approval' });
		expect(await listBills(fx.ctx)).toHaveLength(2);
	});

	it('taints on a picture that was received and then dropped for the text choice', async () => {
		const fx = await seedPerson(t);
		const model = stubModel([
			{ calls: [['bill_delete', { billId: fx.rentBillId }]] },
			{ say: 'A card.' }
		]);
		const events = await play({ f: fx, model, text: 'remove rent', picturesReceived: 2 });
		expect(toolEvents(events)[0]).toMatchObject({ status: 'needs_approval' });
	});

	it('goes on without the pictures when the host refuses the call once, and says so', async () => {
		const fx = await seedPerson(t);
		let calls = 0;
		const seenImages: boolean[] = [];
		const model = {
			async *stream(_c: unknown, req: CompletionRequest) {
				calls++;
				const last = req.messages.at(-1);
				seenImages.push(Boolean(last && 'images' in last && last.images?.length));
				if (calls === 1) {
					const { OpsError } = await import('../../src/lib/server/ops/context');
					throw new OpsError('UNAVAILABLE', 'The model is not available right now.');
				}
				yield { type: 'delta' as const, text: 'From the text.' };
				yield {
					type: 'done' as const,
					completion: {
						content: 'From the text.',
						toolCalls: [],
						finishReason: 'stop',
						usage: { promptTokens: 10, completionTokens: 5 }
					}
				};
			}
		};
		const events = await play({ f: fx, model, text: 'what is this', images: [picture()] });
		expect(seenImages).toEqual([true, false]);
		expect(events.some((e) => e.type === 'pictures')).toBe(true);
		expect(events.some((e) => e.type === 'fallback')).toBe(false);
		expect(events.find((e) => e.type === 'done')).toMatchObject({ reply: 'From the text.' });
	});
});
