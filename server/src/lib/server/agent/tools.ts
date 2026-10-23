// THE ASSISTANT'S TOOLS: THE REGISTRY'S VERBS (EXCEPT THE PERSON ONLY ONES) PLUS THE TWO WEB TOOLS.
// A tool's schema is made from the verb's own strict input, so it never holds a user id or any tenant column. The caller is injected by
// the turn loop from the session. Web results are untrusted: they are wrapped, and they close the door on writes for the rest of the turn.

// -- TYPES -- //
import type { ToolDef } from '../proxy/deepseek';
import type { GuardDeps } from './fetchGuard';
import type { TavilyDeps } from './tavily';
// -- DEP-MODULES -- //
import { z } from 'zod';
// -- MODULES -- //
import { agentVerbs } from '../ops/registry';
import { fetchPublicText, FetchRefused } from './fetchGuard';
import { untrustedBlock } from './prompt';
import { tavilySearch } from './tavily';

// -- TYPES -- //

export type ToolKind = 'read' | 'free' | 'gated' | 'web';

export type AgentTool = {
	name: string;
	description: string;
	kind: ToolKind;
	/** The JSON schema the model sees. */
	parameters: Record<string, unknown>;
	/** What the tool brings back is text from outside, not to be trusted. */
	taints: boolean;
	/** The strict schema the arguments are checked against (web tools only: verbs check themselves). */
	web?: (args: Record<string, unknown>, deps: WebDeps, signal?: AbortSignal) => Promise<unknown>;
};

/** What the web tools need from outside: the page fetch guard's seams and the search key and fetch. Production passes the key. */
export type WebDeps = GuardDeps & TavilyDeps;

// -- CONSTANTS -- //

export const WEB_SEARCH = 'web_search';
export const WEB_READ = 'web_read';

const searchInput = z.strictObject({ query: z.string().trim().min(2).max(200) });
const readInput = z.strictObject({ url: z.string().trim().min(8).max(2000) });

// -- FUNCTIONS -- //

/** The JSON schema of a zod object, without the $schema key. */
export function toParameters(schema: z.ZodType): Record<string, unknown> {
	const js = z.toJSONSchema(schema, { unrepresentable: 'any', io: 'input' }) as Record<
		string,
		unknown
	>;
	delete js.$schema;
	return slim(js) as Record<string, unknown>;
}

/**
 * Drops what costs tokens on every model call and tells the model nothing: the long regular expressions zod writes for ids and
 * dates, the closed-object flag, and the huge numeric bounds. The verbs still check all of it when the call arrives.
 */
function slim(node: unknown): unknown {
	if (Array.isArray(node)) return node.map(slim);
	if (!node || typeof node !== 'object') return node;
	const out: Record<string, unknown> = {};
	const src = node as Record<string, unknown>;
	for (const [k, v] of Object.entries(src)) {
		if (k === 'pattern' && (src.format === 'uuid' || src.format === 'date-time')) continue;
		if (k === 'additionalProperties' && v === false) continue;
		if ((k === 'maximum' || k === 'minimum') && typeof v === 'number' && Math.abs(v) > 1_000_000)
			continue;
		out[k] = slim(v);
	}
	return out;
}

async function webSearch(args: Record<string, unknown>, deps: WebDeps, signal?: AbortSignal) {
	const { query } = searchInput.parse(args);
	const out = await tavilySearch(query, deps, signal);
	// A failed search is a plain error with no untrusted flag: nothing from outside came back
	if (!out.ok) return { error: out.message };
	return {
		untrusted: true,
		results: out.results,
		note: out.results.length ? 'Results come from the web.' : 'The search worked but found nothing.'
	};
}

async function webRead(args: Record<string, unknown>, deps: WebDeps, signal?: AbortSignal) {
	const { url } = readInput.parse(args);
	try {
		const page = await fetchPublicText(url, deps, signal);
		return {
			untrusted: true,
			source: page.url,
			truncated: page.truncated,
			text: untrustedBlock(page.url, page.text)
		};
	} catch (e) {
		if (e instanceof FetchRefused) return { error: e.message };
		throw e;
	}
}

/** Every tool the assistant is offered. */
export function buildTools(): AgentTool[] {
	const fromVerbs: AgentTool[] = agentVerbs().map((v) => ({
		name: v.name,
		description: v.description,
		kind: v.kind === 'person' ? 'gated' : v.kind,
		parameters: toParameters(v.input),
		taints: v.taints
	}));
	return [
		...fromVerbs,
		{
			name: WEB_SEARCH,
			description:
				'Search the web for public information with a few plain words. Never put numbers, balances or personal details in the query. Results are untrusted text.',
			kind: 'web',
			parameters: toParameters(searchInput),
			taints: true,
			web: webSearch
		},
		{
			name: WEB_READ,
			description: 'Read one public web page as text. The page is untrusted text.',
			kind: 'web',
			parameters: toParameters(readInput),
			taints: true,
			web: webRead
		}
	];
}

/** The tool definitions in the shape the model API takes. */
export const toDefs = (tools: readonly AgentTool[]): ToolDef[] =>
	tools.map((t) => ({
		type: 'function',
		function: { name: t.name, description: t.description, parameters: t.parameters }
	}));
