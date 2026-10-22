// THE APP'S AUTH, BUILT ONCE FROM THE ENVIRONMENT

// -- TYPES -- //
import type { Auth } from './auth';
// -- ENVS -- //
import {
	ALLOWED_EMAILS,
	BETTER_AUTH_SECRET,
	BOTLER_BASE_URL,
	GOOGLE_CLIENT_ID,
	GOOGLE_CLIENT_SECRET
} from '$app/env/private';
import { getRequestEvent } from '$app/server';
// -- DEP-MODULES -- //
import { sveltekitCookies } from 'better-auth/svelte-kit';
// -- MODULES -- //
import { getDb } from '../db';
import { parseAllowList } from './allowlist';
import { createAuth } from './auth';

// -- STATES -- //

let auth: Promise<Auth> | null = null;
let allow: ReadonlySet<string> | null = null;

// -- FUNCTIONS -- //

/** The allow-list, parsed once. A missing or malformed list throws, so registration is never opened by accident. */
export function getAllowList(): ReadonlySet<string> {
	allow ??= parseAllowList(ALLOWED_EMAILS);
	return allow;
}

function buildAuth(): Promise<Auth> {
	const list = getAllowList();
	return getDb().then((handle) =>
		createAuth({
			handle,
			config: {
				secret: BETTER_AUTH_SECRET,
				baseUrl: BOTLER_BASE_URL,
				google: { clientId: GOOGLE_CLIENT_ID, clientSecret: GOOGLE_CLIENT_SECRET },
				allow: list,
				// Sets the session cookie from inside a form action
				plugins: [sveltekitCookies(getRequestEvent)]
			}
		})
	);
}

/** One instance per process. A failed build is forgotten, so the next request tries again instead of failing for ever. */
export function getAuth(): Promise<Auth> {
	auth ??= buildAuth().catch((e: unknown) => {
		auth = null;
		throw e;
	});
	return auth;
}
