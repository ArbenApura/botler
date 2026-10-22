// -- DEP-TYPES -- //
import type { RequestHandler } from './$types';
// -- ENVS -- //
import { BOTLER_BASE_URL } from '$app/env/private';
// -- MODULES -- //
import { callerCtx, fail, json } from '#lib/server/api/http.js';
import { getAuth } from '#lib/server/auth/index.js';
import { CALENDAR_SCOPE } from '#lib/server/calendar/google.js';
import { OpsError } from '#lib/server/ops/context.js';

// -- FUNCTIONS -- //

/**
 * Starts the Google consent for Calendar. Sign in asks for almost nothing; Calendar is requested here, only when the person turns sync on.
 * The answer is the Google address to open. After the person comes back, the app calls the calendar_enable operation.
 */
export const POST: RequestHandler = async ({ locals, request }) => {
	const c = await callerCtx(locals, request);
	if ('response' in c) return c.response;
	try {
		const auth = await getAuth();
		const result = await auth.api.linkSocialAccount({
			headers: request.headers,
			body: {
				provider: 'google',
				scopes: [CALENDAR_SCOPE],
				callbackURL: `${BOTLER_BASE_URL}/?calendar=connected`
			}
		});
		if (!result.url)
			throw new OpsError('UNAVAILABLE', 'Google did not give an address to continue.');
		return json({ url: result.url });
	} catch (e) {
		if (e instanceof OpsError) return fail(e);
		console.error(
			JSON.stringify({
				event: 'calendar_connect_failed',
				error: e instanceof Error ? e.name : 'Error'
			})
		);
		return fail(new OpsError('UNAVAILABLE', 'Could not start the Google connection. Try again.'));
	}
};
