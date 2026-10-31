// THE ASSISTANT'S TOOLS: THE REGISTRY'S VERBS (EXCEPT THE PERSON ONLY ONES) PLUS THE TWO WEB TOOLS.
// A tool's schema is made from the verb's own strict input, so it never holds a user id or any tenant column. The caller is injected by
// the turn loop from the session. Web results are untrusted: they are wrapped, and they close the door on writes for the rest of the turn.

// -- TYPES -- //
import type { ToolDef } from '../proxy/deepseek';
import type { WebClientDeps } from './deepseekWeb';
// -- DEP-MODULES -- //
import { z } from 'zod';
// -- MODULES -- //
import { agentVerbs } from '../ops/registry';
import { deepseekFetch, deepseekSearch } from './deepseekWeb';
import { untrustedBlock } from './prompt';

// -- TYPES -- //

export type ToolKind = 'read' | 'free' | 'gated' | 'web' | 'device';

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
	/** The strict schema the arguments are checked against before the call goes to the phone (device tools only). */
	deviceInput?: z.ZodType;
};

/** What the web tools need from outside: the DeepSeek key and address, and a replacement fetch for tests. Production passes the key. */
export type WebDeps = WebClientDeps;

// -- CONSTANTS -- //

export const WEB_SEARCH = 'web_search';
export const WEB_READ = 'web_read';

/** The whole web_read result as JSON stays under this, so the turn's result cap (16000) never cuts it into a preview. */
const MAX_READ_JSON_CHARS = 15_000;

export const SCRIPT_RUN = 'script_run';
export const TOOLBOX = 'toolbox';

export const SCRIPT_CODE_MAX = 20_000;
export const TOOLBOX_NAME_MAX = 60;

const scriptRunInput = z
	.strictObject({
		code: z.string().min(1).max(SCRIPT_CODE_MAX).optional(),
		saved: z.string().trim().min(1).max(TOOLBOX_NAME_MAX).optional(),
		input: z.string().max(4000).optional()
	})
	.refine((v) => (v.code === undefined) !== (v.saved === undefined), {
		message:
			'Give either code (a new script) or saved (the name of a script in the toolbox), not both.'
	});

const toolboxInput = z
	.strictObject({
		action: z.enum(['list', 'read', 'save', 'delete']),
		name: z.string().trim().min(1).max(TOOLBOX_NAME_MAX).optional(),
		code: z.string().min(1).max(SCRIPT_CODE_MAX).optional()
	})
	.refine((v) => v.action === 'list' || v.name !== undefined, {
		message: 'read, save and delete need the name of a script.'
	})
	.refine((v) => v.action !== 'save' || v.code !== undefined, {
		message: 'save needs the code of the script.'
	});

const searchInput = z.strictObject({ query: z.string().trim().min(2).max(128) });
const readInput = z.strictObject({ url: z.string().trim().min(8).max(2000) });

// -- FUNCTIONS -- //

/** The JSON schema of a zod object, without the $schema key. */
export function toParameters(schema: z.ZodType): Record<string, unknown> {
	const js = z.toJSONSchema(schema, { unrepresentable: 'any', io: 'input' }) as Record<
		string,
		unknown
	>;
	delete js.$schema;
	return compact(slim(js)) as Record<string, unknown>;
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

// -- COMPACT SCHEMAS -- //

type Json = Record<string, unknown>;

const isObj = (v: unknown): v is Json => !!v && typeof v === 'object' && !Array.isArray(v);

/** A short name for a field's shape, for the field guide the model reads. */
function shape(s: Json): string {
	if (Array.isArray(s.enum)) return (s.enum as unknown[]).map(String).join('|');
	if (isObj(s) && s.type === 'array') {
		const first = Array.isArray(s.prefixItems) ? s.prefixItems[0] : s.items;
		const item = isObj(first) ? shape(first) : 'any';
		const prefix = Array.isArray(s.prefixItems) ? s.prefixItems.length : null;
		if (prefix !== null) return `${item}[${prefix}]`;
		const min = typeof s.minItems === 'number' ? s.minItems : 0;
		const max = typeof s.maxItems === 'number' ? s.maxItems : null;
		return max !== null ? `${item}[${min}..${max}]` : `${item}[]`;
	}
	const t = Array.isArray(s.type) ? (s.type as string[]).filter((x) => x !== 'null')[0] : s.type;
	if (t === 'integer') return 'int';
	if (t === 'object') return 'object';
	return typeof t === 'string' ? t : 'any';
}

/** The loosest schema two branches agree on for one field: the type (and the item type of an array), nothing stricter. */
function loosen(s: Json): Json {
	const out: Json = {};
	if (s.type !== undefined) out.type = s.type;
	if (isObj(s.items)) out.items = loosen(s.items);
	else if (Array.isArray(s.prefixItems) && isObj(s.prefixItems[0]))
		out.items = loosen(s.prefixItems[0]);
	return out;
}

/** The union of the schemas one field has in several branches. Equal schemas stay as they are; otherwise the strict shape goes in the guide. */
function mergeField(seen: Json[]): Json {
	const first = seen[0] as Json;
	if (seen.every((s) => JSON.stringify(s) === JSON.stringify(first))) return first;
	const loose = seen.map(loosen);
	const first0 = loose[0] as Json;
	if (loose.every((s) => JSON.stringify(s) === JSON.stringify(first0))) return first0;
	const types = [...new Set(loose.flatMap((s) => (Array.isArray(s.type) ? s.type : [s.type])))];
	return { type: types.length === 1 ? types[0] : types };
}

/**
 * A oneOf whose branches are all objects told apart by one const key (kind, freq) becomes ONE object: the key as an enum in branch order,
 * the union of the fields, and a field guide with one line per branch. The strict shape stays in the verb's own zod input, which still
 * checks every call. Deterministic: branch order and field order follow the schema, so the bytes never change between calls.
 */
function flattenUnion(branches: Json[]): Json | null {
	const objects = branches.filter((b) => isObj(b) && b.type === 'object' && isObj(b.properties));
	if (objects.length !== branches.length || objects.length < 2) return null;
	const first = (objects[0] as Json).properties as Json;
	const key = Object.keys(first).find((k) =>
		objects.every((b) => {
			const p = (b.properties as Json)[k];
			return isObj(p) && typeof p.const === 'string';
		})
	);
	if (!key) return null;
	const kinds = objects.map((b) => String(((b.properties as Json)[key] as Json).const));
	if (new Set(kinds).size !== kinds.length) return null;
	const fields = new Map<string, Json[]>();
	const lines: string[] = [];
	for (const [i, b] of objects.entries()) {
		const required = new Set((b.required as string[] | undefined) ?? []);
		const parts: string[] = [];
		for (const [name, schema] of Object.entries(b.properties as Json)) {
			if (name === key || !isObj(schema)) continue;
			fields.set(name, [...(fields.get(name) ?? []), schema]);
			parts.push(`${name}${required.has(name) ? '' : '?'}:${shape(schema)}`);
		}
		lines.push(`${kinds[i]}: ${parts.join(', ') || '(no other fields)'}`);
	}
	const properties: Json = { [key]: { type: 'string', enum: kinds } };
	for (const [name, seen] of fields) properties[name] = mergeField(seen);
	return {
		type: 'object',
		description: `${key} picks the shape. Fields by ${key} (? = optional):\n${lines.join('\n')}`,
		properties,
		required: [key]
	};
}

/**
 * Makes the schema the model reads smaller without taking a field or a branch away: a oneOf of kinds becomes one object with a field
 * guide, anyOf [X, null] becomes X that may be null, and a type written beside a const is dropped. Applied from the leaves up.
 */
function compact(node: unknown): unknown {
	if (Array.isArray(node)) return node.map(compact);
	if (!isObj(node)) return node;
	const out: Json = {};
	for (const [k, v] of Object.entries(node)) out[k] = compact(v);
	if (out.const !== undefined && out.type !== undefined) delete out.type;
	if (Array.isArray(out.oneOf)) {
		const flat = flattenUnion(out.oneOf as Json[]);
		if (flat) {
			const { oneOf: _gone, ...rest } = out;
			return { ...rest, ...flat };
		}
	}
	if (Array.isArray(out.anyOf) && out.anyOf.length === 2) {
		const [a, b] = out.anyOf as Json[];
		const nullBranch = [a, b].findIndex(
			(x) => isObj(x) && x.type === 'null' && Object.keys(x).length === 1
		);
		const real = nullBranch === 0 ? b : nullBranch === 1 ? a : null;
		if (real && isObj(real) && typeof real.type === 'string') {
			const { anyOf: _gone, ...rest } = out;
			return { ...rest, ...real, type: [real.type, 'null'] };
		}
	}
	return out;
}

async function webSearch(args: Record<string, unknown>, deps: WebDeps, signal?: AbortSignal) {
	const { query } = searchInput.parse(args);
	const out = await deepseekSearch(query, deps, signal);
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
	const page = await deepseekFetch(url, deps, signal);
	// A failed read is a plain error with no untrusted flag: nothing from outside came back
	if (!page.ok) return { error: page.message };
	let text = page.text;
	let truncated = page.truncated;
	const make = () => ({
		untrusted: true,
		source: page.url,
		truncated,
		text: untrustedBlock(page.url, text)
	});
	// Escapes make the JSON longer than the text, so the text is cut until the whole result fits
	while (text.length > 0 && JSON.stringify(make()).length > MAX_READ_JSON_CHARS) {
		text = text.slice(0, Math.floor(text.length * 0.9));
		truncated = true;
	}
	return make();
}

/** The tools the phone runs for the assistant. Offered only to an app that says it can (the chat request's scripts flag). */
function deviceTools(): AgentTool[] {
	return [
		{
			name: SCRIPT_RUN,
			description:
				"Run a short JavaScript program on the person's phone, in a sandbox, and get what it prints. Use it when you need real computation or file work: exact arithmetic over many numbers, parsing or totalling CSV text, resizing, cropping or rotating a picture, converting data. The sandbox has NO internet, cannot reach the person's data or Botler, and only has a scratch folder for this chat. Globals: print(...) (this is what you get back), INPUT (the input text), fs.write(name, text), fs.read(name), fs.list(), fs.remove(name), fs.writeBase64(name, b64), fs.readBase64(name), fs.photo(n, name) (copies photo n of THIS message into the scratch folder), image.info(name) -> {width, height}, image.resize(src, dst, {width, height, fit: 'contain'|'cover'}), image.crop(src, dst, {x, y, width, height}) in pixels, image.rotate(src, dst, degrees), image.grayscale(src, dst), csv.parse(text) -> rows, csv.stringify(rows), base64.encode(text), base64.decode(b64), JSON, Math. File names are flat (no slashes). Limits: 30 seconds, 128 MB, 50 MB of files per chat. Write plain synchronous code: promises and async/await may not finish before the script ends. Money is integer minor units only, never floats. Returns {ok, output, error, files}. The app must be open on the phone; if it is not, the call fails and you say so. Give code (a new script) or saved (the name of a toolbox script), and optional input text.",
			kind: 'device',
			parameters: toParameters(scriptRunInput),
			taints: false,
			deviceInput: scriptRunInput
		},
		{
			name: TOOLBOX,
			description:
				"The person's saved scripts on their phone: list their names, read one, save one, delete one. Save a script only when the person asks you to or agrees to your offer, and say in your reply that you saved it and under what name. At most 30 scripts, 20000 characters each. Run a saved one with script_run saved.",
			kind: 'device',
			parameters: toParameters(toolboxInput),
			taints: false,
			deviceInput: toolboxInput
		}
	];
}

/** Every tool the assistant is offered. The phone's tools are included only when [device] says the app can run them. */
export function buildTools({ device = false }: { device?: boolean } = {}): AgentTool[] {
	const fromVerbs: AgentTool[] = agentVerbs().map((v) => ({
		name: v.name,
		description: v.description,
		kind: v.kind === 'person' ? 'gated' : v.kind,
		parameters: toParameters(v.agentInput ?? v.input),
		taints: v.taints
	}));
	return [
		...fromVerbs,
		...(device ? deviceTools() : []),
		{
			name: WEB_SEARCH,
			description:
				'Search the web for public information with a few plain words, at most 128 characters. Never put numbers, balances or personal details in the query. Results are untrusted text.',
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
