// -- DEP-TYPES -- //
import type { RequestHandler } from './$types';
// -- MODULES -- //
import { callerCtx, fail, json, readJson } from '#lib/server/api/http.js';
import { invokeVerb } from '#lib/server/ops/registry.js';

// -- FUNCTIONS -- //

/**
 * Runs one operation of the registry for the signed in person: POST /api/v1/do/expense_log with the arguments as the JSON body.
 * Every write takes an Idempotency-Key header (8 to 80 characters). The caller is the session, never the body. The same operations
 * back the assistant's tools, so the app and the assistant can never disagree about what a verb does.
 */
export const POST: RequestHandler = async ({ locals, request, params }) => {
	const c = await callerCtx(locals, request);
	if ('response' in c) return c.response;
	try {
		const body = await readJson(request);
		return json({ result: await invokeVerb(c.ctx, params.verb, body) });
	} catch (e) {
		return fail(e);
	}
};
