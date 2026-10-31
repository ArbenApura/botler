// -- DEP-TYPES -- //
import type { RequestHandler } from './$types';
// -- MODULES -- //
import { callerCtx, fail, json, readJson } from '#lib/server/api/http.js';
import { answerDevice } from '#lib/server/agent/device.js';
import { OpsError } from '#lib/server/ops/context.js';

// -- CONSTANTS -- //

/** A phone answer is small (a script's printed text is capped on the phone); this leaves room for a long read of a saved script. */
const BODY_MAX = 96_000;

// -- FUNCTIONS -- //

/**
 * The person's phone answers a call the assistant made to it (a script run, the toolbox): { callId, ok, result }. The call id was made by the
 * server and sent to this person's phone only; an answer for a call that is not waiting for this person (late, repeated, someone else's) is
 * not accepted and changes nothing.
 */
export const POST: RequestHandler = async ({ locals, request }) => {
	const c = await callerCtx(locals, request);
	if ('response' in c) return c.response;
	try {
		const body = await readJson(request, BODY_MAX);
		if (!body || typeof body !== 'object' || Array.isArray(body))
			throw new OpsError('INVALID', 'The request body must be a JSON object');
		const { callId, ok, result } = body as { callId?: unknown; ok?: unknown; result?: unknown };
		if (typeof callId !== 'string' || callId.length < 8 || callId.length > 80)
			throw new OpsError('INVALID', 'callId must be the id the call was sent with');
		if (typeof ok !== 'boolean') throw new OpsError('INVALID', 'ok must be true or false');
		return json({ accepted: answerDevice(c.ctx.actor.userId, callId, ok, result) });
	} catch (e) {
		return fail(e);
	}
};
