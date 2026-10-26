// THE CACHE BENCH: ONE FIXED 12 TURN CONVERSATION RUN THROUGH THE REAL TURN LOOP, THE REAL PROMPT AND TOOLS AND THE REAL CLIENTS.
// The network is a fake that hashes the REAL wire body and simulates each provider's prompt cache, so the numbers move when the
// bytes of the prompt move. Token counts are chars / 4 on the wire (the estimate core.ts uses), so the figures are for comparison,
// not billing. Set BENCH_OUT to a file path to also write the tables as Markdown. The owner's M1 and M2 runs are the real check.

// -- TYPES -- //
import type { Fixture } from '../agent/support';
import type { TurnModel } from '../../src/lib/server/agent/turn';
import type { ChatMessage } from '../../src/lib/server/proxy/types';
import type { Usage } from '../../src/lib/server/proxy/limits';
import type { TestDb } from '../support/testDb';
// -- DEP-MODULES -- //
import { createHash } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
// -- MODULES -- //
import { SYSTEM_PREFIX } from '../../src/lib/server/agent/prompt';
import { buildTools, toDefs } from '../../src/lib/server/agent/tools';
import { historyStart } from '../../src/lib/server/agent/chat';
import { runTurn } from '../../src/lib/server/agent/turn';
import { createAnthropicClient } from '../../src/lib/server/proxy/anthropic';
import { createModelClient } from '../../src/lib/server/proxy/deepseek';
import { DEFAULT_LIMITS } from '../../src/lib/server/proxy/limits';
import { createTestDb } from '../support/testDb';
import { seedPerson } from '../agent/support';

// -- TYPES -- //

type Provider = 'anthropic' | 'deepseek';

/** What the fake model does on one call of a turn: ask for tools, or write the answer. */
type Round = { tools: string[] } | { say: string };

type Row = {
	turn: number;
	call: number;
	prompt: number;
	read: number;
	write: number;
	uncached: number;
	out: number;
	/** What the client recorded for the cap (promptTokens + completionTokens). */
	recorded: number;
	/** The cache read tokens the client reported, when it reads them. */
	reportedRead: number | null;
};

type Report = {
	provider: Provider;
	rows: Row[];
	/** Hash of the wire prefix up to each cache breakpoint (Anthropic), per call, for the stability asserts. */
	prefixHashes: string[][];
	/** The sizes in characters of every tool result the model saw in the last call of each turn. */
	toolResultChars: number[][];
	/** Per call: the hash of every block, the hashes at the cache markers, and whether a marker other than the last sits on the volatile context. */
	calls: { turn: number; call: number; all: Set<string>; marks: string[]; volatileMark: boolean }[];
	/** The distinct tool definitions sent over the whole conversation. */
	toolsSent: Set<string>;
};

// -- CONSTANTS -- //

const MODEL_MIN_TOKENS = 512;
const LOOKBACK = 20;
const UNIT_CHARS = 256;
const WEIGHTS = {
	anthropic: { read: 10, write: 125 },
	deepseek: { read: 2, write: 100 }
} as const;
/** Dollars per million tokens, from the price pages read 2026-10-24: [uncached input, cache write, cache read, output]. */
const PRICES = {
	anthropic: { input: 0.1, write: 0.125, read: 0.01, out: 0.5 },
	deepseek: { input: 0.15, write: 0.15, read: 0.003, out: 0.6 }
} as const;

const WORDS =
	'rent bills payday gcash savings goal reminder budget balance transfer groceries lunch electricity water internet salary allowance emergency fund'.split(
		' '
	);
const text = (seed: number, chars: number) => {
	let out = '';
	for (let i = 0; out.length < chars; i++) out += `${WORDS[(seed * 7 + i * 3) % WORDS.length]} `;
	return out.trim().slice(0, chars);
};

const READS = [
	'accounts_list',
	'bills_list',
	'goals_list',
	'income_list',
	'assets_summary',
	'rules_list',
	'split_list',
	'task_list',
	'event_list',
	'routine_list'
];

/** The 12 turns. Turns 1, 3, 8 and 10 run two tool rounds, turn 6 asks for ten reads at once, the rest answer straight away. */
const TURNS: { user: string; rounds: Round[] }[] = Array.from({ length: 12 }, (_, i) => {
	const n = i + 1;
	const answer = { say: text(n, 600 + (n % 4) * 150) };
	const user = `${n}. ${text(n + 40, 90 + (n % 3) * 60)}`;
	if (n === 1)
		return { user, rounds: [{ tools: ['accounts_list'] }, { tools: ['bills_list'] }, answer] };
	if (n === 3)
		return {
			user,
			rounds: [{ tools: ['bills_list', 'goals_list'] }, { tools: ['assets_summary'] }, answer]
		};
	if (n === 6) return { user, rounds: [{ tools: READS }, answer] };
	if (n === 8)
		return { user, rounds: [{ tools: ['accounts_list'] }, { tools: ['goals_list'] }, answer] };
	if (n === 10)
		return { user, rounds: [{ tools: ['bills_list'] }, { tools: ['income_list'] }, answer] };
	return { user, rounds: [answer] };
});

/** Seconds on the virtual clock: one model call takes 8, a turn follows the last by 20, and a long gap sits before turn 9. */
const CALL_SECONDS = 8;
const TURN_GAP_SECONDS = 20;
const LONG_GAP_BEFORE_TURN = 9;
const LONG_GAP_SECONDS = 6 * 60;

// -- STATES -- //

let t: TestDb;
let person: Fixture;
const reports: Report[] = [];

// -- FUNCTIONS -- //

const est = (chars: number) => Math.ceil(chars / 4);

/** The history the turn loop gets: the stepwise window of chat.ts history(), each side cut at 1,500 characters. */
function historyFor(done: { user: string; reply: string }[]): ChatMessage[] {
	return done.slice(historyStart(done.length)).flatMap((d): ChatMessage[] => [
		{ role: 'user', content: d.user.slice(0, 1500) },
		{ role: 'assistant', content: d.reply.slice(0, 1500) }
	]);
}

/** One simulated clock shared by the fake network and the harness. */
function createClock() {
	let ms = Date.parse('2026-10-26T09:00:00+08:00');
	return {
		now: () => ms,
		advance: (seconds: number) => {
			ms += seconds * 1000;
		}
	};
}

// -- SIMULATED PROVIDERS -- //

type Block = { json: string; tokens: number; ttl?: number };

function anthropicBlocks(body: Record<string, unknown>) {
	const blocks: Block[] = [];
	const marks: number[] = [];
	const push = (value: unknown) => {
		const v = { ...(value as Record<string, unknown>) };
		const cc = v.cache_control as { ttl?: string } | undefined;
		delete v.cache_control;
		const json = JSON.stringify(v);
		blocks.push({ json, tokens: est(json.length), ttl: cc?.ttl === '1h' ? 3600 : 300 });
		if (cc) marks.push(blocks.length - 1);
	};
	for (const tool of (body.tools as unknown[] | undefined) ?? []) push(tool);
	const system = body.system;
	if (typeof system === 'string') push({ type: 'text', text: system });
	else for (const s of (system as unknown[] | undefined) ?? []) push(s);
	for (const m of body.messages as { role: string; content: string | unknown[] }[]) {
		if (typeof m.content === 'string') push({ role: m.role, type: 'text', text: m.content });
		else for (const b of m.content) push({ role: m.role, ...(b as object) });
	}
	return { blocks, marks };
}

function createAnthropicSim(clock: ReturnType<typeof createClock>) {
	const cache = new Map<string, number>();
	return (body: Record<string, unknown>) => {
		const { blocks, marks } = anthropicBlocks(body);
		const hashes: string[] = [];
		const prefixTokens: number[] = [];
		let h = '';
		let sum = 0;
		for (const b of blocks) {
			h = createHash('sha1').update(h).update(b.json).digest('hex');
			sum += b.tokens;
			hashes.push(h);
			prefixTokens.push(sum);
		}
		const valid = marks.filter((m) => prefixTokens[m]! >= MODEL_MIN_TOKENS);
		let hit = -1;
		for (const m of valid)
			for (let j = m; j > Math.max(-1, m - LOOKBACK); j--) {
				const until = cache.get(hashes[j]!);
				if (until !== undefined && until > clock.now()) {
					hit = Math.max(hit, j);
					break;
				}
			}
		const last = valid.length ? Math.max(...valid) : -1;
		const read = hit >= 0 ? prefixTokens[hit]! : 0;
		const write = last > hit ? prefixTokens[last]! - read : 0;
		const total = sum;
		for (const m of valid) cache.set(hashes[m]!, clock.now() + blocks[m]!.ttl! * 1000);
		if (hit >= 0) cache.set(hashes[hit]!, clock.now() + blocks[hit]!.ttl! * 1000);
		return {
			read,
			write,
			uncached: total - read - write,
			total,
			prefixes: valid.map((m) => hashes[m]!),
			all: new Set(hashes),
			// A marker before the last one must never sit on the turn context, which changes on every call
			volatileMark: valid.slice(0, -1).some((m) => blocks[m]!.json.includes('<context>\\n'))
		};
	};
}

function createDeepseekSim() {
	const store = new Set<string>();
	return (body: Record<string, unknown>) => {
		const messages = body.messages as unknown[];
		const input = [
			JSON.stringify(body.tools ?? []),
			...messages.map((m) => JSON.stringify(m))
		].join('\n');
		const total = est(input.length);
		const units = Math.floor(input.length / UNIT_CHARS);
		const h = createHash('sha1');
		const at: string[] = [];
		for (let k = 1; k <= units; k++) {
			h.update(input.slice((k - 1) * UNIT_CHARS, k * UNIT_CHARS));
			at.push(h.copy().digest('hex'));
		}
		let hitUnits = 0;
		for (let k = units; k >= 1; k--)
			if (store.has(at[k - 1]!)) {
				hitUnits = k;
				break;
			}
		for (const a of at) store.add(a);
		const read = Math.min(total, est(hitUnits * UNIT_CHARS));
		return {
			read,
			write: 0,
			uncached: total - read,
			total,
			prefixes: [] as string[],
			all: new Set<string>(),
			volatileMark: false
		};
	};
}

const sse = (events: unknown[]) =>
	new Response(events.map((e) => `data: ${JSON.stringify(e)}\n\n`).join('') + 'data: [DONE]\n\n', {
		status: 200
	});

/** Runs the 12 turns for one provider and returns one row per model call. */
async function runConversation(provider: Provider): Promise<Report> {
	const clock = createClock();
	const rows: Row[] = [];
	const prefixHashes: string[][] = [];
	const toolResultChars: number[][] = [];
	const calls: Report['calls'] = [];
	const toolsSent = new Set<string>();
	const sink: Usage[] = [];
	const sim = provider === 'anthropic' ? createAnthropicSim(clock) : createDeepseekSim();
	let turnIndex = 0;
	let callInTurn = 0;
	let lastBody: Record<string, unknown> = {};

	const fetchFake = (async (_url: string, init: RequestInit) => {
		const body = JSON.parse(String(init.body)) as Record<string, unknown>;
		lastBody = body;
		const used = sim(body);
		prefixHashes.push(used.prefixes);
		toolsSent.add(JSON.stringify(body.tools ?? []));
		const step = TURNS[turnIndex]!.rounds[callInTurn] ?? { say: 'ok' };
		callInTurn += 1;
		calls.push({
			turn: turnIndex + 1,
			call: callInTurn,
			all: used.all,
			marks: used.prefixes,
			volatileMark: used.volatileMark
		});
		clock.advance(CALL_SECONDS);
		const id = (k: number) => `call_${turnIndex}_${callInTurn}_${k}`;
		const outChars =
			'say' in step ? step.say.length : step.tools.reduce((n, name) => n + name.length + 20, 0);
		const out = est(outChars);
		rows.push({
			turn: turnIndex + 1,
			call: callInTurn,
			prompt: used.total,
			read: used.read,
			write: used.write,
			uncached: used.uncached,
			out,
			recorded: 0,
			reportedRead: null
		});
		if (provider === 'anthropic') {
			const events: unknown[] = [
				{
					type: 'message_start',
					message: {
						usage: {
							input_tokens: used.uncached,
							cache_read_input_tokens: used.read,
							cache_creation_input_tokens: used.write,
							output_tokens: 1
						}
					}
				}
			];
			if ('say' in step) {
				events.push(
					{ type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } },
					{ type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: step.say } }
				);
			} else {
				step.tools.forEach((name, k) => {
					events.push(
						{
							type: 'content_block_start',
							index: k,
							content_block: { type: 'tool_use', id: id(k), name }
						},
						{
							type: 'content_block_delta',
							index: k,
							delta: { type: 'input_json_delta', partial_json: '{}' }
						}
					);
				});
			}
			events.push(
				{
					type: 'message_delta',
					delta: { stop_reason: 'say' in step ? 'end_turn' : 'tool_use' },
					usage: { output_tokens: out }
				},
				{ type: 'message_stop' }
			);
			return sse(events);
		}
		const delta =
			'say' in step
				? { content: step.say }
				: {
						tool_calls: step.tools.map((name, k) => ({
							index: k,
							id: id(k),
							function: { name, arguments: '{}' }
						}))
					};
		return sse([
			{ choices: [{ delta }] },
			{ choices: [{ delta: {}, finish_reason: 'say' in step ? 'stop' : 'tool_calls' }] },
			{
				choices: [],
				usage: {
					prompt_tokens: used.total,
					completion_tokens: out,
					prompt_cache_hit_tokens: used.read,
					prompt_cache_miss_tokens: used.uncached
				}
			}
		]);
	}) as unknown as typeof fetch;

	const limits = {
		...DEFAULT_LIMITS,
		ratePerMinute: 100_000,
		chatTokenCap: 1_000_000_000,
		globalTokenCap: 1_000_000_000
	};
	const client =
		provider === 'anthropic'
			? createAnthropicClient({
					apiKey: 'sk-ant-bench',
					baseUrl: 'https://model.test',
					model: 'claude-haiku-5-5',
					limits,
					fetch: fetchFake,
					sleep: async () => undefined
				})
			: createModelClient({
					apiKey: 'sk-ds-bench',
					baseUrl: 'https://model.test',
					model: 'deepseek-flash',
					limits,
					fetch: fetchFake,
					sleep: async () => undefined
				});
	const model: TurnModel = {
		async *stream(ctx, req) {
			for await (const ev of client.stream(ctx, req)) {
				if (ev.type === 'done') sink.push(ev.completion.usage);
				yield ev;
			}
		}
	};

	const done: { user: string; reply: string }[] = [];
	const memories = [
		'- Prefers short answers.',
		'- Gets paid on the 15th and the 30th.',
		'- Saves for a trip.'
	];
	for (turnIndex = 0; turnIndex < TURNS.length; turnIndex++) {
		callInTurn = 0;
		clock.advance(turnIndex + 1 === LONG_GAP_BEFORE_TURN ? LONG_GAP_SECONDS : TURN_GAP_SECONDS);
		const first = rows.length;
		let reply = '';
		for await (const ev of runTurn({
			ctx: person.ctx,
			model,
			history: historyFor(done),
			userText: TURNS[turnIndex]!.user,
			turnKey: `bench-${provider}-${turnIndex}`,
			now: new Date(clock.now()),
			memories,
			currency: 'PHP',
			replyLanguage: 'en'
		}))
			if (ev.type === 'done') reply = ev.reply;
		done.push({ user: TURNS[turnIndex]!.user, reply });
		// What the client recorded for each call of this turn
		rows.slice(first).forEach((r, i) => {
			const u = sink[first + i] as (Usage & { cacheReadTokens?: number }) | undefined;
			r.recorded = (u?.promptTokens ?? 0) + (u?.completionTokens ?? 0);
			r.reportedRead = u?.cacheReadTokens ?? null;
		});
		// Sizes of the tool results the model saw in the last call of the turn
		const msgs = lastBody.messages as { role: string; content: unknown }[];
		const lengths: number[] = [];
		for (const m of msgs) {
			if (m.role === 'tool') lengths.push(String(m.content).length);
			else if (Array.isArray(m.content))
				for (const b of m.content as { type?: string; content?: unknown }[])
					if (b.type === 'tool_result') lengths.push(String(b.content).length);
		}
		toolResultChars.push(lengths);
	}
	return { provider, rows, prefixHashes, toolResultChars, calls, toolsSent };
}

// -- REPORT -- //

const sumOf = (rows: Row[], pick: (r: Row) => number) => rows.reduce((n, r) => n + pick(r), 0);

function summary(report: Report) {
	const { provider, rows } = report;
	const w = WEIGHTS[provider];
	const p = PRICES[provider];
	const prompt = sumOf(rows, (r) => r.prompt);
	const read = sumOf(rows, (r) => r.read);
	const write = sumOf(rows, (r) => r.write);
	const uncached = sumOf(rows, (r) => r.uncached);
	const out = sumOf(rows, (r) => r.out);
	const oldRule = sumOf(rows, (r) => r.prompt + r.out);
	const newRule = sumOf(
		rows,
		(r) => r.uncached + r.out + Math.ceil((r.read * w.read + r.write * w.write) / 100)
	);
	const dollars = (uncached * p.input + write * p.write + read * p.read + out * p.out) / 1e6;
	const after1 = rows.filter((r) => r.turn > 1 || r.call > 1);
	const shareAfterFirst =
		sumOf(after1, (r) => r.read) /
		Math.max(
			1,
			sumOf(after1, (r) => r.prompt)
		);
	return {
		calls: rows.length,
		prompt,
		read,
		write,
		uncached,
		out,
		oldRule,
		newRule,
		dollars,
		shareAfterFirst
	};
}

function table(report: Report): string {
	const s = summary(report);
	const lines = [
		`### ${report.provider} (${s.calls} model calls over 12 turns)`,
		'',
		'| turn | call | prompt | cache read | cache write | uncached | output |',
		'|---|---|---|---|---|---|---|',
		...report.rows.map(
			(r) =>
				`| ${r.turn} | ${r.call} | ${r.prompt} | ${r.read} | ${r.write} | ${r.uncached} | ${r.out} |`
		),
		'',
		`prompt ${s.prompt}, read ${s.read} (${(100 * s.shareAfterFirst).toFixed(1)}% of prompt after the first call), write ${s.write}, uncached ${s.uncached}, output ${s.out}`,
		`per call: prompt ${Math.round(s.prompt / s.calls)}, charged old rule ${Math.round(s.oldRule / s.calls)}, charged new rule ${Math.round(s.newRule / s.calls)}`,
		`total charged: old rule ${s.oldRule}, new rule ${s.newRule}; estimated cost ${s.dollars.toFixed(4)} dollars`,
		`recorded by the client (old rule): ${sumOf(report.rows, (r) => r.recorded)}`
	];
	const all = report.toolResultChars.flat();
	lines.push(
		`tool results in the last call of each turn: ${all.length}, largest ${Math.max(0, ...all)} chars, over 8000 chars: ${all.filter((n) => n > 8000).length}`
	);
	return lines.join('\n');
}

// -- LIFECYCLES -- //

beforeAll(async () => {
	t = await createTestDb();
	person = await seedPerson(t);
});

afterAll(async () => {
	await t.close();
});

// -- TESTS -- //

describe('cache bench', () => {
	it('runs the 12 turn conversation on both providers and prints the tables', async () => {
		reports.push(await runConversation('anthropic'), await runConversation('deepseek'));
		const stable = JSON.stringify(toDefs(buildTools())).length + SYSTEM_PREFIX.length;
		const out = [
			`stable prefix: ${est(stable)} tokens (tools ${JSON.stringify(toDefs(buildTools())).length} chars, SYSTEM_PREFIX ${SYSTEM_PREFIX.length} chars)`,
			...reports.map(table)
		].join('\n\n');
		console.log(out);
		if (process.env.BENCH_OUT) writeFileSync(process.env.BENCH_OUT, out);
		for (const r of reports) {
			expect(r.rows.length).toBeGreaterThanOrEqual(TURNS.length);
			expect(r.rows.every((row) => row.prompt > 0)).toBe(true);
			// The tool definitions are the same bytes on every call of the conversation
			expect(r.toolsSent.size).toBe(1);
		}
		const a = reports.find((r) => r.provider === 'anthropic')!;
		// No marker but the last sits on the volatile context
		expect(a.calls.filter((c) => c.volatileMark)).toEqual([]);
		// The prefix up to the first marker (the tools) is the same bytes on every call
		expect(new Set(a.calls.map((c) => c.marks[0])).size).toBe(1);
		// Two calls in a row in one turn: the earlier call's last marker is inside the later call's bytes
		for (const [i, c] of a.calls.entries()) {
			const next = a.calls[i + 1];
			if (!next || next.turn !== c.turn) continue;
			expect(next.all.has(c.marks.at(-1)!), `turn ${c.turn} call ${c.call}`).toBe(true);
		}
		// Two turns in a row: the history marker of one turn is inside the next turn, unless the window slid
		const first = a.calls.filter((c) => c.call === 1);
		for (const [i, c] of first.entries()) {
			const next = first[i + 1];
			if (!next || c.marks.length < 3) continue;
			if (historyStart(c.turn - 1) !== historyStart(c.turn)) continue;
			expect(next.all.has(c.marks.at(-2)!), `turn ${c.turn}`).toBe(true);
		}
	});
});
