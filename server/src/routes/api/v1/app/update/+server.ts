// -- DEP-TYPES -- //
import type { RequestHandler } from './$types';
// -- ENVS -- //
import { BOTLER_RELEASES_DIR } from '$app/env/private';
// -- MODULES -- //
import { handleUpdateCheck } from '#lib/server/appUpdate/handlers.js';

// -- FUNCTIONS -- //

/** Is a newer build published? The phone sends the versionCode it runs. Signed in people only. */
export const GET: RequestHandler = ({ locals, url }) =>
	handleUpdateCheck({
		dir: BOTLER_RELEASES_DIR,
		signedIn: Boolean(locals.user),
		installed: url.searchParams.get('versionCode')
	});
