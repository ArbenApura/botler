// -- DEP-TYPES -- //
import type { RequestHandler } from './$types';
// -- ENVS -- //
import { BOTLER_RELEASES_DIR } from '$app/env/private';
// -- MODULES -- //
import { handleApkDownload } from '#lib/server/appUpdate/handlers.js';

// -- FUNCTIONS -- //

/** The APK of one published build, streamed with byte ranges. Signed in people only. */
export const GET: RequestHandler = ({ locals, params, request }) =>
	handleApkDownload({
		dir: BOTLER_RELEASES_DIR,
		signedIn: Boolean(locals.user),
		code: params.versionCode,
		request
	});
