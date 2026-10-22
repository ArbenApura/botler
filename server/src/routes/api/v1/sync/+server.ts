// -- DEP-TYPES -- //
import type { RequestHandler } from './$types';
// -- MODULES -- //
import { callerCtx, fail, json } from '#lib/server/api/http.js';
import { syncGet } from '#lib/server/ops/sync.js';

// -- FUNCTIONS -- //

/**
 * What the phone should have: the reminders (replace the whole set of alarms with them), the summary card and the calendar state.
 * ?cursor=<last cursor>: when nothing changed the reminder list is left out and the phone keeps what it has.
 */
export const GET: RequestHandler = async ({ locals, request, url }) => {
	const c = await callerCtx(locals, request);
	if ('response' in c) return c.response;
	try {
		return json(await syncGet(c.ctx, { cursor: url.searchParams.get('cursor') ?? undefined }));
	} catch (e) {
		return fail(e);
	}
};
