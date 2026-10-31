// -- DEP-TYPES -- //
import type { RequestHandler } from './$types';

// -- FUNCTIONS -- //

/** Liveness for the Docker health check and the deploy script. Holds no data and no version of a secret. The build id (set by the deploy script) lets the script tell a new container from the old one. */
export const GET: RequestHandler = () =>
	new Response(
		JSON.stringify({ ok: true, service: 'botler', build: process.env.BOTLER_BUILD ?? null }),
		{
			headers: { 'content-type': 'application/json', 'cache-control': 'no-store' }
		}
	);
