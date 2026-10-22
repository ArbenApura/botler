// -- DEP-TYPES -- //
import type { Handle, ServerInit } from '@sveltejs/kit/hooks';
// -- ENVS -- //
import { building } from '$app/env';
import { BOTLER_BASE_URL } from '$app/env/private';
// -- DEP-MODULES -- //
import { svelteKitHandler } from 'better-auth/svelte-kit';
// -- MODULES -- //
import { allowedUser } from '#lib/server/auth/allowlist.js';
import { getAllowList, getAuth } from '#lib/server/auth/index.js';
import { getDb } from '#lib/server/db/index.js';
import { jobHandlers } from '#lib/server/jobs/handlers.js';
import { createMemoryHandlers } from '#lib/server/jobs/memory.js';
import { createPushHandlers } from '#lib/server/jobs/push.js';
import { getPusher } from '#lib/server/push/index.js';
import { activeEmbedder, getEmbedder, setActiveEmbedder } from '#lib/server/memory/embed.js';
import { getModelClient } from '#lib/server/proxy/index.js';
import { startWorker } from '#lib/server/jobs/queue.js';

// -- FUNCTIONS -- //

/** Runs once when the server starts: opens the database (and checks its role) and starts the background job worker. Not during the build. */
export const init: ServerInit = async () => {
	if (building) return;
	// Parsed at start, so a missing or malformed ALLOWED_EMAILS stops the server instead of opening registration
	getAllowList();
	// The embedding model loads on first use (about 15 s), not at start
	setActiveEmbedder(getEmbedder());
	const memoryHandlers = createMemoryHandlers({
		model: () => getModelClient(),
		embedder: () => activeEmbedder()
	});
	const handle = await getDb();
	// A half set up push stops the start here; no push at all is allowed (the phone syncs on open and on a timer)
	if (!getPusher()) console.warn(JSON.stringify({ event: 'push_not_configured' }));
	const pushHandlers = createPushHandlers({ pusher: () => getPusher() });
	startWorker(handle, { ...jobHandlers, ...memoryHandlers, ...pushHandlers });
};

/** Reads the session once per request (cookie or bearer token) and serves /api/auth/* through Better Auth. */
export const handle: Handle = async ({ event, resolve }) => {
	// Health checks never touch the database
	if (event.url.pathname === '/healthz') {
		event.locals.user = null;
		return resolve(event);
	}
	const auth = await getAuth();
	const session = await auth.api.getSession({ headers: event.request.headers });
	// The allow-list is checked on every request, not only when a session starts: taking an address off the list ends its access
	// at once, even for a session that is still valid
	const person = allowedUser(getAllowList(), session?.user);
	event.locals.user = person ? { id: person.id, name: person.name, email: person.email } : null;
	// Better Auth only answers when the request origin is the public address. Behind a reverse proxy the server sees http and
	// another host, so the auth routes are handed over under the public address (the Google callback would be a 404 otherwise)
	if (event.url.pathname.startsWith('/api/auth/') && !building) {
		const target = new URL(event.url.pathname + event.url.search, BOTLER_BASE_URL);
		return auth.handler(new Request(target, event.request));
	}
	return svelteKitHandler({ auth, event, resolve, building });
};
