// -- DEP-TYPES -- //
import type { RequestHandler } from './$types';
// -- MODULES -- //
import { callerCtx, fail, json } from '#lib/server/api/http.js';
import { listActions } from '#lib/server/ops/actions.js';

// -- FUNCTIONS -- //

const STATUSES = ['pending', 'applied', 'rejected', 'failed', 'expired'] as const;

/** The approval cards of the caller, newest first. ?status=pending for the ones waiting. */
export const GET: RequestHandler = async ({ locals, request, url }) => {
	const c = await callerCtx(locals, request);
	if ('response' in c) return c.response;
	try {
		const s = url.searchParams.get('status');
		const status = STATUSES.find((x) => x === s);
		return json({ actions: await listActions(c.ctx, status) });
	} catch (e) {
		return fail(e);
	}
};
