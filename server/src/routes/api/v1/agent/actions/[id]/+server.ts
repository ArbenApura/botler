// -- DEP-TYPES -- //
import type { RequestHandler } from './$types';
// -- MODULES -- //
import { callerCtx, fail, json, readJson } from '#lib/server/api/http.js';
import { decideAction } from '#lib/server/ops/actions.js';
import { OpsError } from '#lib/server/ops/context.js';

// -- FUNCTIONS -- //

/**
 * The signed in person answers an approval card: { "decision": "approve" | "reject" }. Approving runs the change now, as the person.
 * The caller here is always a person, from the session, so the assistant has no way to reach this route.
 */
export const POST: RequestHandler = async ({ locals, request, params }) => {
	const c = await callerCtx(locals, request);
	if ('response' in c) return c.response;
	try {
		const body = await readJson(request);
		// A body of null, a list or a bare value is a bad request, not a crash
		if (!body || typeof body !== 'object' || Array.isArray(body))
			throw new OpsError('INVALID', 'The request body must be a JSON object');
		if (
			(body as { decision?: unknown }).decision !== 'approve' &&
			(body as { decision?: unknown }).decision !== 'reject'
		)
			throw new OpsError('INVALID', 'decision must be "approve" or "reject"');
		return json({
			action: await decideAction(c.ctx, {
				actionId: params.id,
				decision: (body as { decision: 'approve' | 'reject' }).decision
			})
		});
	} catch (e) {
		return fail(e);
	}
};
