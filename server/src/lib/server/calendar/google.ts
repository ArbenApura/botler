// THE GOOGLE CALENDAR API, JUST THE FOUR CALLS SYNC NEEDS (list changes, insert, patch, delete) OVER PLAIN HTTPS WITH THE PERSON'S OWN ACCESS TOKEN.
// The token comes from the caller (src/lib/server/calendar/token.ts) and is never logged. Errors are sorted into the three that sync reacts to:
// the sync token is too old (410: start again), Google no longer lets us in (invalid_grant: the person must reconnect), and everything else (retry).

// -- TYPES -- //

export type GoogleEvent = {
	id?: string;
	status?: 'confirmed' | 'tentative' | 'cancelled';
	summary?: string;
	description?: string;
	location?: string;
	start?: { dateTime?: string; date?: string; timeZone?: string };
	end?: { dateTime?: string; date?: string; timeZone?: string };
	etag?: string;
	updated?: string;
	recurringEventId?: string;
	extendedProperties?: { private?: Record<string, string> };
};

export type ListParams = { syncToken?: string; timeMin?: string; pageToken?: string };
export type ListPage = { items: GoogleEvent[]; nextPageToken?: string; nextSyncToken?: string };

export type GoogleCalendarApi = {
	list(p: ListParams): Promise<ListPage>;
	insert(e: GoogleEvent): Promise<GoogleEvent>;
	patch(id: string, e: GoogleEvent): Promise<GoogleEvent>;
	remove(id: string): Promise<void>;
};

/** The sync token is too old or invalid: forget it and list everything again. */
export class GoogleGone extends Error {
	constructor() {
		super('GoogleGone');
		this.name = 'GoogleGone';
	}
}

/** Google refuses us: the grant was revoked or expired, or the scope is missing. Retrying will not help. */
export class GoogleAuthError extends Error {
	constructor(readonly code: 'invalid_grant' | 'no_scope' | 'no_account') {
		super(code);
		this.name = 'GoogleAuthError';
	}
}

// -- CONSTANTS -- //

export const CALENDAR_SCOPE = 'https://www.googleapis.com/auth/calendar.events';
const BASE = 'https://www.googleapis.com/calendar/v3';

// -- FUNCTIONS -- //

export function createGoogleApi(opts: {
	getToken: () => Promise<string>;
	calendarId?: string;
	fetch?: typeof fetch;
}): GoogleCalendarApi {
	const doFetch = opts.fetch ?? fetch;
	const cal = `${BASE}/calendars/${encodeURIComponent(opts.calendarId ?? 'primary')}/events`;

	async function call(method: string, url: string, body?: unknown): Promise<Response> {
		const res = await doFetch(url, {
			method,
			headers: {
				authorization: `Bearer ${await opts.getToken()}`,
				...(body ? { 'content-type': 'application/json' } : {})
			},
			...(body ? { body: JSON.stringify(body) } : {})
		});
		if (res.status === 410) throw new GoogleGone();
		if (res.status === 401) throw new GoogleAuthError('invalid_grant');
		if (res.status === 403) {
			const text = await res.clone().text();
			if (/insufficientPermissions|ACCESS_TOKEN_SCOPE_INSUFFICIENT|insufficient/i.test(text))
				throw new GoogleAuthError('no_scope');
		}
		return res;
	}

	const fail = (what: string, res: Response) => new Error(`google_${what}_${res.status}`);

	return {
		async list(p) {
			const q = new URLSearchParams({
				singleEvents: 'true',
				showDeleted: 'true',
				maxResults: '250'
			});
			if (p.syncToken) q.set('syncToken', p.syncToken);
			else if (p.timeMin) q.set('timeMin', p.timeMin);
			if (p.pageToken) q.set('pageToken', p.pageToken);
			const res = await call('GET', `${cal}?${q}`);
			if (!res.ok) throw fail('list', res);
			const body = (await res.json()) as ListPage;
			return {
				items: body.items ?? [],
				nextPageToken: body.nextPageToken,
				nextSyncToken: body.nextSyncToken
			};
		},
		async insert(e) {
			const res = await call('POST', cal, e);
			if (!res.ok) throw fail('insert', res);
			return (await res.json()) as GoogleEvent;
		},
		async patch(id, e) {
			const res = await call('PATCH', `${cal}/${encodeURIComponent(id)}`, e);
			if (res.status === 404) throw Object.assign(new Error('google_patch_404'), { missing: true });
			if (!res.ok) throw fail('patch', res);
			return (await res.json()) as GoogleEvent;
		},
		async remove(id) {
			let res: Response;
			try {
				res = await call('DELETE', `${cal}/${encodeURIComponent(id)}`);
			} catch (e) {
				// 410 on a delete means it is already gone
				if (e instanceof GoogleGone) return;
				throw e;
			}
			// Already gone is as good as deleted
			if (res.status === 404 || res.ok) return;
			throw fail('delete', res);
		}
	};
}
