// SHARED HTTP HELPERS FOR /api/v1: THE SIGNED IN CALLER, A SAFE JSON BODY, AND ONE ERROR SHAPE. ROUTES HOLD NO RULES, THEY CALL OPS VERBS.

// -- TYPES -- //
import type { Ctx } from '../ops/context';
// -- MODULES -- //
import { OpsError } from '../ops/context';

// -- CONSTANTS -- //

/** The most a request body may hold: 64 KB. */
const MAX_BODY = 64 * 1024;

const STATUS: Record<OpsError['code'], number> = {
	INVALID: 400,
	NOT_FOUND: 404,
	FORBIDDEN: 403,
	CONFLICT: 409,
	BUSY_CHAT: 409,
	LIMIT: 429,
	UNAVAILABLE: 503
};

// -- FUNCTIONS -- //

/** A JSON response that is never cached, because every answer is about one person. */
export function json(data: unknown, status = 200): Response {
	return new Response(JSON.stringify(data), {
		status,
		headers: { 'content-type': 'application/json', 'cache-control': 'no-store' }
	});
}

/** The one error shape: { error: { code, message } }. An unexpected error says nothing about the cause. */
export function fail(e: unknown): Response {
	if (e instanceof OpsError)
		return json({ error: { code: e.code, message: e.message } }, STATUS[e.code]);
	console.error('Unexpected error in an API route', e instanceof Error ? e.name : typeof e);
	return json({ error: { code: 'INTERNAL', message: 'Something went wrong' } }, 500);
}

/** Which way in the app says it came: the screens, the home-screen widget or the offline outbox. Anything else is the screens. */
export function channelOf(request: Request): 'app' | 'widget' | 'outbox' {
	const said = request.headers.get('x-botler-channel');
	return said === 'widget' || said === 'outbox' ? said : 'app';
}

/** The context of the signed in person, or an UNAUTHENTICATED response. The user id comes from the session only. */
export async function callerCtx(
	locals: App.Locals,
	request: Request
): Promise<{ ctx: Ctx } | { response: Response }> {
	if (!locals.user)
		return {
			response: json({ error: { code: 'UNAUTHENTICATED', message: 'Sign in first' } }, 401)
		};
	const requestId = request.headers.get('idempotency-key') ?? undefined;
	if (requestId && (requestId.length < 8 || requestId.length > 80))
		return {
			response: json(
				{ error: { code: 'INVALID', message: 'Idempotency-Key must be 8 to 80 characters' } },
				400
			)
		};
	// Loaded here, after the checks above, so a refused request never touches the database and the helpers can be tested alone
	const { getDb } = await import('../db');
	const handle = await getDb();
	return {
		ctx: {
			handle,
			actor: { userId: locals.user.id, kind: 'person' },
			requestId,
			channel: channelOf(request)
		}
	};
}

/**
 * Reads a JSON body of at most max bytes (64 KB unless a route asks for more). The body is counted as it arrives and the read stops at the
 * limit, so a body that names no length cannot be buffered whole before it is refused. Anything else is INVALID.
 */
export async function readJson(request: Request, max: number = MAX_BODY): Promise<unknown> {
	// A declared size over the cap is refused before any of the body is read
	if (Number(request.headers.get('content-length') ?? 0) > max)
		throw new OpsError('INVALID', 'The request is too large');
	const reader = request.body?.getReader();
	const chunks: Uint8Array[] = [];
	let total = 0;
	while (reader) {
		const { done, value } = await reader.read();
		if (done) break;
		total += value.byteLength;
		if (total > max) {
			await reader.cancel().catch(() => undefined);
			throw new OpsError('INVALID', 'The request is too large');
		}
		chunks.push(value);
	}
	const text = Buffer.concat(chunks).toString('utf8');
	try {
		return JSON.parse(text) as unknown;
	} catch {
		throw new OpsError('INVALID', 'The request body is not valid JSON');
	}
}
