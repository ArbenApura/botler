// -- DEP-TYPES -- //
import type { RequestHandler } from './$types';

// -- FUNCTIONS -- //

/** Liveness for the Docker health check and the deploy script. Holds no data and no version of a secret. */
export const GET: RequestHandler = () =>
	new Response(JSON.stringify({ ok: true, service: 'botler' }), {
		headers: { 'content-type': 'application/json', 'cache-control': 'no-store' }
	});
