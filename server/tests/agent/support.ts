// SHARED PIECES FOR THE AGENT TESTS: A SCRIPTED STAND-IN FOR THE MODEL, A PUBLIC-LOOKING WEB, AND A SEEDED PERSON

// -- TYPES -- //
import type { GuardDeps, TransportResponse } from '../../src/lib/server/agent/fetchGuard';
import type { TurnEvent, TurnModel } from '../../src/lib/server/agent/turn';
import type { Ctx } from '../../src/lib/server/ops/context';
import type { CompletionRequest, StreamEvent } from '../../src/lib/server/proxy/deepseek';
import type { TestDb } from '../support/testDb';
// -- MODULES -- //
import { runTurn } from '../../src/lib/server/agent/turn';
import { user } from '../../src/lib/server/db/schema';
import { createAccount } from '../../src/lib/server/ops/accounts';
import { createBill } from '../../src/lib/server/ops/bills';
import { createGoal, createIncome } from '../../src/lib/server/ops/planning';

// -- TYPES -- //

/** What the stand-in model does on one call: some text, some tool calls, or both. */
export type Step = { say?: string; calls?: [name: string, args: unknown][] };
export type ScriptFn = (req: CompletionRequest, n: number) => Step;

export type StubModel = TurnModel & { requests: CompletionRequest[] };

export type Fixture = {
	userId: string;
	ctx: Ctx;
	rcbc: string;
	gcash: string;
	maya: string;
	rentBillId: string;
	variableBillId: string;
	goalId: string;
	incomeId: string;
};

// -- FUNCTIONS -- //

let ids = 0;

/** A model that plays a script: step n answers call n. After the script it just says "ok". */
export function stubModel(script: Step[] | ScriptFn): StubModel {
	const requests: CompletionRequest[] = [];
	return {
		requests,
		async *stream(_ctx, req): AsyncGenerator<StreamEvent> {
			const n = requests.length;
			requests.push({ ...req, messages: [...req.messages] });
			const step = typeof script === 'function' ? script(req, n) : (script[n] ?? { say: 'ok' });
			if (step.say) yield { type: 'delta', text: step.say };
			yield {
				type: 'done',
				completion: {
					content: step.say ?? '',
					toolCalls: (step.calls ?? []).map(([name, args], i) => ({
						id: `call_${n}_${i}`,
						type: 'function' as const,
						function: { name, arguments: typeof args === 'string' ? args : JSON.stringify(args) }
					})),
					finishReason: step.calls?.length ? 'tool_calls' : 'stop',
					usage: { promptTokens: 10, completionTokens: 5 }
				}
			};
		}
	};
}

const textPage = (body: string): TransportResponse => ({
	status: 200,
	headers: { 'content-type': 'text/html' },
	body: (async function* () {
		yield new TextEncoder().encode(body);
	})(),
	destroy: () => undefined
});

/** A web where every name is a public address and the given pages exist. */
export function fakeWeb(pages: Record<string, string>): { deps: GuardDeps; requested: string[] } {
	const requested: string[] = [];
	return {
		requested,
		deps: {
			lookup: async () => [{ address: '93.184.216.34', family: 4 }],
			transport: async ({ url }) => {
				requested.push(url.toString());
				const body = pages[url.toString()];
				return body === undefined ? { ...textPage('missing'), status: 404 } : textPage(body);
			}
		}
	};
}

export const asPerson = (handle: Ctx['handle'], userId: string): Ctx => ({
	handle,
	actor: { userId, kind: 'person' }
});

/** A new person with three accounts, a rent bill, a variable bill, a goal and a payday. */
export async function seedPerson(t: TestDb): Promise<Fixture> {
	const userId = `user_agent_${String(++ids).padStart(4, '0')}`;
	await t.handle.db
		.insert(user)
		.values({ id: userId, name: 'Eval', email: `${userId}@example.com` });
	const ctx = asPerson(t.handle, userId);
	const req = () => ({ ...ctx, requestId: `seed-${userId}-${++ids}` });
	const acc = async (name: string, kind: 'bank' | 'ewallet') =>
		(await createAccount(req(), { name, kind, minBalance: 0 })).id;
	const rcbc = await acc('RCBC', 'bank');
	const gcash = await acc('GCash', 'ewallet');
	const maya = await acc('Maya', 'ewallet');
	const bill = (name: string, kind: 'fixed' | 'variable', amount: number | null, day: number) =>
		createBill(req(), {
			name,
			category: 'bills',
			accountId: rcbc,
			kind,
			amount,
			schedule: { kind: 'monthly', day },
			weekendRule: 'none',
			deferrable: false
		});
	const rent = await bill('Rent', 'fixed', 800_000, 1);
	const meralco = await bill('Meralco', 'variable', 300_000, 20);
	const goal = await createGoal(req(), {
		name: 'Emergency fund',
		accountId: maya,
		targetAmount: null,
		perPayday: 100_000
	});
	const income = await createIncome(req(), {
		label: 'Salary',
		accountId: rcbc,
		expectedAmount: 2_500_000,
		schedule: { kind: 'semi_monthly', days: [15, 30] },
		weekendRule: 'before'
	});
	return {
		userId,
		ctx,
		rcbc,
		gcash,
		maya,
		rentBillId: rent.id,
		variableBillId: meralco.id,
		goalId: goal.id,
		incomeId: income.id
	};
}

/** Runs a whole turn and collects its events. */
export async function play(opts: {
	f: Fixture;
	model: TurnModel;
	text: string;
	ocrText?: string;
	web?: GuardDeps;
	turnKey?: string;
	signal?: AbortSignal;
	limits?: Parameters<typeof runTurn>[0]['limits'];
}): Promise<TurnEvent[]> {
	const events: TurnEvent[] = [];
	for await (const e of runTurn({
		ctx: opts.f.ctx,
		model: opts.model,
		history: [],
		userText: opts.text,
		ocrText: opts.ocrText,
		turnKey: opts.turnKey ?? `turn-${opts.f.userId}-${++ids}`,
		web: opts.web,
		signal: opts.signal,
		limits: opts.limits,
		now: new Date('2026-10-21T04:00:00Z')
	}))
		events.push(e);
	return events;
}

export const toolEvents = (events: TurnEvent[]) =>
	events.filter((e): e is Extract<TurnEvent, { type: 'tool' }> => e.type === 'tool');
export const cardEvents = (events: TurnEvent[]) =>
	events.filter((e): e is Extract<TurnEvent, { type: 'card' }> => e.type === 'card');
export const doneEvent = (events: TurnEvent[]) =>
	events.find((e): e is Extract<TurnEvent, { type: 'done' }> => e.type === 'done');
