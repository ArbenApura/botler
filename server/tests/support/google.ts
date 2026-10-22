// A STAND-IN FOR GOOGLE CALENDAR: AN IN-MEMORY CALENDAR THAT ANSWERS LIKE THE REAL ONE FOR THE THINGS SYNC RELIES ON
// (sync tokens that return only what changed, etags that change on every write, cancelled events, a 410 for an old token, private properties).

// -- TYPES -- //
import type {
	GoogleCalendarApi,
	GoogleEvent,
	ListPage,
	ListParams
} from '../../src/lib/server/calendar/google';
// -- MODULES -- //
import { GoogleAuthError, GoogleGone } from '../../src/lib/server/calendar/google';

// -- TYPES -- //

type Stored = GoogleEvent & { id: string; etag: string; updated: string; rev: number };

// -- FUNCTIONS -- //

export class FakeGoogle implements GoogleCalendarApi {
	events = new Map<string, Stored>();
	calls: string[] = [];
	/** The next list with a sync token answers 410. */
	goneOnce = false;
	/** Every call answers as if the grant was revoked. */
	revoked = false;
	/** The next insert saves the event but its answer is lost. */
	loseNextInsertAnswer = false;
	/** Added to the updated time of every write, to put a change in the past or future. */
	clock = () => new Date();
	private rev = 0;
	private seq = 0;

	private stamp(e: GoogleEvent & { id: string }): Stored {
		this.rev++;
		return { ...e, rev: this.rev, etag: `"etag-${this.rev}"`, updated: this.clock().toISOString() };
	}

	/** Something that happens in Google itself, not through us. */
	external(e: GoogleEvent & { id?: string }): Stored {
		const id = e.id ?? `g${++this.seq}`;
		const stored = this.stamp({ status: 'confirmed', ...e, id });
		this.events.set(id, stored);
		return stored;
	}

	externalCancel(id: string): void {
		const cur = this.events.get(id);
		if (cur) this.events.set(id, this.stamp({ ...cur, status: 'cancelled' }));
	}

	async list(p: ListParams): Promise<ListPage> {
		this.calls.push(p.syncToken ? 'list:token' : 'list:full');
		if (this.revoked) throw new GoogleAuthError('invalid_grant');
		if (p.syncToken && this.goneOnce) {
			this.goneOnce = false;
			throw new GoogleGone();
		}
		const since = p.syncToken ? Number(p.syncToken.replace('tok-', '')) : -1;
		const items = [...this.events.values()].filter(
			(e) => e.rev > since && (p.syncToken || e.status !== 'cancelled')
		);
		// A full listing returns two per page, to exercise paging
		if (!p.syncToken) {
			const start = Number(p.pageToken ?? 0);
			const page = items.slice(start, start + 2);
			const more = start + 2 < items.length;
			return more
				? { items: page, nextPageToken: String(start + 2) }
				: { items: page, nextSyncToken: `tok-${this.rev}` };
		}
		return { items, nextSyncToken: `tok-${this.rev}` };
	}

	async insert(e: GoogleEvent): Promise<GoogleEvent> {
		this.calls.push('insert');
		if (this.revoked) throw new GoogleAuthError('invalid_grant');
		const id = `g${++this.seq}`;
		const stored = this.stamp({ status: 'confirmed', ...e, id });
		this.events.set(id, stored);
		if (this.loseNextInsertAnswer) {
			this.loseNextInsertAnswer = false;
			throw new Error('network dropped');
		}
		return stored;
	}

	async patch(id: string, e: GoogleEvent): Promise<GoogleEvent> {
		this.calls.push('patch');
		if (this.revoked) throw new GoogleAuthError('invalid_grant');
		const cur = this.events.get(id);
		if (!cur || cur.status === 'cancelled')
			throw Object.assign(new Error('google_patch_404'), { missing: true });
		const stored = this.stamp({ ...cur, ...e, id });
		this.events.set(id, stored);
		return stored;
	}

	async remove(id: string): Promise<void> {
		this.calls.push('remove');
		if (this.revoked) throw new GoogleAuthError('invalid_grant');
		const cur = this.events.get(id);
		if (cur) this.events.set(id, this.stamp({ ...cur, status: 'cancelled' }));
	}

	live(): Stored[] {
		return [...this.events.values()].filter((e) => e.status !== 'cancelled');
	}
}
