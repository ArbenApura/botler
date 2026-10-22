// TWO-WAY GOOGLE CALENDAR SYNC (P5.2, P5.7). One pass pulls what changed in Google, then sends what changed here.
// - Pull: events.list with the saved sync token (singleEvents on, so repeats arrive as their own instances and a changed or cancelled instance is
//   just another event). A 410 means the token is too old: list everything again and drop local copies Google no longer has.
// - Echo guard: after we write an event Google gives back its etag; we keep it. When the same etag comes back in a pull, it is our own write and
//   is not imported again. A write whose answer was lost is found again by the botlerId we put in the event's private properties.
// - Conflicts: both sides changed since the last sync -> the later change wins (Google's "updated" against ours).
// - Bills and paydays that need action become all-day events (without amounts) while sync is on, and go away when dealt with.
// - Google refusing us (invalid_grant, missing scope) stops sync and says why, so the app can show a banner. Nothing else is touched.
// - Text that came from Google is untrusted: those events are stored with source "google".

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { Schedule } from '../../finance/schedule';
import type { GoogleCalendarApi, GoogleEvent } from './google';
// -- DEP-MODULES -- //
import { and, eq, inArray, isNotNull, isNull, sql } from 'drizzle-orm';
// -- MODULES -- //
import { addDays, manilaStart, toManilaDate } from '../../finance/dates';
import { occurrencesBetween } from '../../finance/schedule';
import { calendarEvent, calendarSync, incomeSchedule, splitPlan } from '../db/schema';
import { dueBills } from '../ops/bills';
import { GoogleAuthError, GoogleGone } from './google';

// -- TYPES -- //

type EventRow = typeof calendarEvent.$inferSelect;

export type SyncReport = {
	status: 'ok' | 'error' | 'off';
	pulled: number;
	pushed: number;
	deleted: number;
	fullResync: boolean;
	errorCode?: string;
};

// -- CONSTANTS -- //

const PAST_DAYS = 30;
const DERIVED_DAYS = 45;

// -- FUNCTIONS -- //

const day = (d: Date) => toManilaDate(d);

/** A Google event as local columns, or null when it has no usable start. */
function fromGoogle(
	g: GoogleEvent
): Pick<EventRow, 'title' | 'startsAt' | 'endsAt' | 'allDay' | 'location' | 'notes'> | null {
	const title = (g.summary ?? '').trim().slice(0, 300) || '(no title)';
	const notes = (g.description ?? '').slice(0, 4000);
	const location = (g.location ?? '').slice(0, 300);
	if (g.start?.date) {
		const startsAt = manilaStart(g.start.date);
		const endsAt = g.end?.date
			? manilaStart(g.end.date)
			: new Date(startsAt.getTime() + 86_400_000);
		return {
			title,
			startsAt,
			endsAt: endsAt.getTime() < startsAt.getTime() ? startsAt : endsAt,
			allDay: true,
			location,
			notes
		};
	}
	if (g.start?.dateTime) {
		const startsAt = new Date(g.start.dateTime);
		const endsAt = g.end?.dateTime
			? new Date(g.end.dateTime)
			: new Date(startsAt.getTime() + 3_600_000);
		if (Number.isNaN(startsAt.getTime())) return null;
		return {
			title,
			startsAt,
			endsAt:
				Number.isNaN(endsAt.getTime()) || endsAt.getTime() < startsAt.getTime() ? startsAt : endsAt,
			allDay: false,
			location,
			notes
		};
	}
	return null;
}

/** A local event as a Google event. The botlerId marks it as ours. */
function toGoogle(e: EventRow): GoogleEvent {
	const base: GoogleEvent = {
		summary: e.title,
		description: e.notes || undefined,
		location: e.location || undefined,
		extendedProperties: { private: { botlerId: e.id } }
	};
	if (e.allDay) {
		const startDate = day(e.startsAt);
		const endDate =
			e.endsAt.getTime() > e.startsAt.getTime() ? day(e.endsAt) : addDays(startDate, 1);
		return {
			...base,
			start: { date: startDate },
			end: { date: endDate > startDate ? endDate : addDays(startDate, 1) }
		};
	}
	return {
		...base,
		start: { dateTime: e.startsAt.toISOString(), timeZone: 'Asia/Manila' },
		end: { dateTime: e.endsAt.toISOString(), timeZone: 'Asia/Manila' }
	};
}

async function stateOf(tx: Tx, userId: string) {
	const [s] = await tx.select().from(calendarSync).where(eq(calendarSync.userId, userId));
	return s;
}

async function saveState(tx: Tx, userId: string, patch: Partial<typeof calendarSync.$inferInsert>) {
	await tx
		.insert(calendarSync)
		.values({ userId, ...patch })
		.onConflictDoUpdate({ target: calendarSync.userId, set: { ...patch, updatedAt: sql`now()` } });
}

/** Bills and paydays that need action, as all-day events; gone again when the bill is paid or the split approved. */
export async function syncDerivedEvents(tx: Tx, userId: string, now: Date): Promise<void> {
	const today = day(now);
	const end = addDays(today, DERIVED_DAYS);
	const wanted = new Map<string, { title: string; date: string }>();
	for (const b of (await dueBills(tx, userId, today, end)).filter((x) => !x.paid))
		wanted.set(`bill:${b.billId}:${b.dueDate}`, { title: `Bill due: ${b.name}`, date: b.dueDate });
	const approved = await tx
		.select({ p: splitPlan.payday, i: splitPlan.incomeScheduleId })
		.from(splitPlan)
		.where(and(eq(splitPlan.userId, userId), eq(splitPlan.status, 'approved')));
	const done = new Set(approved.map((a) => `${a.i}|${a.p}`));
	for (const inc of await tx
		.select()
		.from(incomeSchedule)
		.where(and(eq(incomeSchedule.userId, userId), eq(incomeSchedule.active, true))))
		for (const d of occurrencesBetween(inc.schedule as Schedule, today, end, {
			weekend: inc.weekendRule
		}))
			if (!done.has(`${inc.id}|${d}`))
				wanted.set(`payday:${inc.id}:${d}`, { title: `Payday: ${inc.label}`, date: d });

	const have = await tx
		.select()
		.from(calendarEvent)
		.where(
			and(
				eq(calendarEvent.userId, userId),
				inArray(calendarEvent.source, ['bill', 'payday']),
				isNull(calendarEvent.deletedAt)
			)
		);
	const haveByKey = new Map(have.map((h) => [h.refKey ?? '', h]));
	// One removed by hand but not yet removed at Google still holds its key: leave it, the push finishes the removal
	const removed = new Set(
		(
			await tx
				.select({ refKey: calendarEvent.refKey })
				.from(calendarEvent)
				.where(
					and(
						eq(calendarEvent.userId, userId),
						inArray(calendarEvent.source, ['bill', 'payday']),
						isNotNull(calendarEvent.deletedAt)
					)
				)
		).map((r) => r.refKey ?? '')
	);
	for (const [refKey, w] of wanted) {
		const startsAt = manilaStart(w.date);
		const ex = haveByKey.get(refKey);
		if (!ex && removed.has(refKey)) continue;
		if (!ex)
			await tx.insert(calendarEvent).values({
				userId,
				title: w.title,
				startsAt,
				endsAt: new Date(startsAt.getTime() + 86_400_000),
				allDay: true,
				source: refKey.startsWith('bill') ? 'bill' : 'payday',
				refKey
			});
		else if (ex.title !== w.title || ex.startsAt.getTime() !== startsAt.getTime())
			await tx
				.update(calendarEvent)
				.set({
					title: w.title,
					startsAt,
					endsAt: new Date(startsAt.getTime() + 86_400_000),
					version: sql`${calendarEvent.version} + 1`,
					updatedAt: sql`now()`
				})
				.where(eq(calendarEvent.id, ex.id));
	}
	// Dealt with: a synced one is marked deleted so the removal reaches Google; one Google never saw is simply removed
	for (const h of have)
		if (h.refKey && !wanted.has(h.refKey) && h.startsAt.getTime() >= manilaStart(today).getTime()) {
			if (h.googleEventId)
				await tx
					.update(calendarEvent)
					.set({
						deletedAt: sql`now()`,
						version: sql`${calendarEvent.version} + 1`,
						updatedAt: sql`now()`
					})
					.where(eq(calendarEvent.id, h.id));
			else await tx.delete(calendarEvent).where(eq(calendarEvent.id, h.id));
		}
}

/** One sync pass for one person. Safe to run again at any time. */
export async function syncCalendar(
	tx: Tx,
	userId: string,
	api: GoogleCalendarApi,
	now: Date = new Date()
): Promise<SyncReport> {
	const state = await stateOf(tx, userId);
	if (!state || state.status === 'off')
		return { status: 'off', pulled: 0, pushed: 0, deleted: 0, fullResync: false };
	const report: SyncReport = { status: 'ok', pulled: 0, pushed: 0, deleted: 0, fullResync: false };
	try {
		await pull(tx, userId, api, state.syncToken, now, report);
		await syncDerivedEvents(tx, userId, now);
		await push(tx, userId, api, report);
		await saveState(tx, userId, { status: 'ok', errorCode: null, lastSyncAt: now });
	} catch (e) {
		if (e instanceof GoogleAuthError) {
			// Retrying cannot help: say why, and let the person reconnect. Local data is untouched
			await saveState(tx, userId, { status: 'error', errorCode: e.code, lastSyncAt: now });
			return { ...report, status: 'error', errorCode: e.code };
		}
		throw e;
	}
	return report;
}

async function pull(
	tx: Tx,
	userId: string,
	api: GoogleCalendarApi,
	token: string | null,
	now: Date,
	report: SyncReport
) {
	const seen = new Set<string>();
	let full = !token;
	let syncToken: string | undefined = token ?? undefined;
	const timeMin = new Date(now.getTime() - PAST_DAYS * 86_400_000).toISOString();
	for (let attempt = 0; attempt < 2; attempt++) {
		try {
			let page: string | undefined;
			let next: string | undefined;
			do {
				const res = await api.list(
					syncToken ? { syncToken, pageToken: page } : { timeMin, pageToken: page }
				);
				for (const g of res.items) {
					if (g.id) seen.add(g.id);
					await applyRemote(tx, userId, g, report);
				}
				page = res.nextPageToken;
				next = res.nextSyncToken ?? next;
			} while (page);
			if (full) await dropVanished(tx, userId, seen, timeMin, report);
			await saveState(tx, userId, {
				syncToken: next ?? null,
				...(full ? { lastFullSyncAt: now } : {})
			});
			report.fullResync = full;
			return;
		} catch (e) {
			// Too old a token: forget it and list everything again (once)
			if (e instanceof GoogleGone && attempt === 0) {
				await saveState(tx, userId, { syncToken: null });
				syncToken = undefined;
				full = true;
				continue;
			}
			throw e;
		}
	}
}

async function applyRemote(tx: Tx, userId: string, g: GoogleEvent, report: SyncReport) {
	if (!g.id) return;
	const [local] = await tx
		.select()
		.from(calendarEvent)
		.where(and(eq(calendarEvent.userId, userId), eq(calendarEvent.googleEventId, g.id)));
	if (g.status === 'cancelled') {
		if (local) {
			await tx.delete(calendarEvent).where(eq(calendarEvent.id, local.id));
			report.deleted++;
		}
		return;
	}
	// Echo guard: our own write coming back with the etag we stored is not a change
	if (local && g.etag && local.googleEtag === g.etag) return;
	const botlerId = g.extendedProperties?.private?.botlerId;
	if (!local && botlerId) {
		// A write whose answer we never saw: link it instead of importing a second copy
		const [mine] = await tx
			.select()
			.from(calendarEvent)
			.where(
				and(
					eq(calendarEvent.userId, userId),
					eq(calendarEvent.id, botlerId),
					isNull(calendarEvent.googleEventId)
				)
			);
		if (mine) {
			await tx
				.update(calendarEvent)
				.set({
					googleEventId: g.id,
					googleEtag: g.etag ?? null,
					googleUpdatedAt: g.updated ? new Date(g.updated) : null
				})
				.where(eq(calendarEvent.id, mine.id));
			return;
		}
	}
	const mapped = fromGoogle(g);
	if (!mapped) return;
	const gUpdated = g.updated ? new Date(g.updated) : null;
	if (local) {
		const dirty = local.version > local.syncedVersion;
		// Both changed: the later change wins. If ours is later it stays and is sent in the push step
		if (dirty && gUpdated && local.updatedAt.getTime() > gUpdated.getTime()) {
			await tx
				.update(calendarEvent)
				.set({ googleEtag: g.etag ?? null, googleUpdatedAt: gUpdated })
				.where(eq(calendarEvent.id, local.id));
			return;
		}
		await tx
			.update(calendarEvent)
			.set({
				...mapped,
				googleEtag: g.etag ?? null,
				googleUpdatedAt: gUpdated,
				version: local.version + 1,
				syncedVersion: local.version + 1,
				recurringEventId: g.recurringEventId ?? null,
				updatedAt: sql`now()`
			})
			.where(eq(calendarEvent.id, local.id));
	} else {
		await tx.insert(calendarEvent).values({
			userId,
			...mapped,
			source: 'google',
			googleEventId: g.id,
			googleEtag: g.etag ?? null,
			googleUpdatedAt: gUpdated,
			recurringEventId: g.recurringEventId ?? null,
			version: 1,
			syncedVersion: 1
		});
	}
	report.pulled++;
}

/** After a full listing: a local copy Google does not have any more, inside the listed window and with nothing unsent, is gone. */
async function dropVanished(
	tx: Tx,
	userId: string,
	seen: Set<string>,
	timeMin: string,
	report: SyncReport
) {
	const linked = await tx
		.select()
		.from(calendarEvent)
		.where(
			and(
				eq(calendarEvent.userId, userId),
				isNotNull(calendarEvent.googleEventId),
				sql`${calendarEvent.startsAt} >= ${new Date(timeMin)}`
			)
		);
	for (const l of linked)
		if (l.googleEventId && !seen.has(l.googleEventId) && l.version <= l.syncedVersion) {
			await tx.delete(calendarEvent).where(eq(calendarEvent.id, l.id));
			report.deleted++;
		}
}

async function push(tx: Tx, userId: string, api: GoogleCalendarApi, report: SyncReport) {
	// Removals first
	const removed = await tx
		.select()
		.from(calendarEvent)
		.where(and(eq(calendarEvent.userId, userId), isNotNull(calendarEvent.deletedAt)));
	for (const r of removed) {
		if (r.googleEventId) await api.remove(r.googleEventId);
		await tx.delete(calendarEvent).where(eq(calendarEvent.id, r.id));
		report.deleted++;
	}
	const dirty = (
		await tx
			.select()
			.from(calendarEvent)
			.where(and(eq(calendarEvent.userId, userId), isNull(calendarEvent.deletedAt)))
	).filter((e) => e.version > e.syncedVersion);
	for (const e of dirty) {
		let result: GoogleEvent;
		if (e.googleEventId) {
			try {
				result = await api.patch(e.googleEventId, toGoogle(e));
			} catch (err) {
				if ((err as { missing?: boolean }).missing) {
					// Someone deleted it in Google: delete it here too instead of recreating it
					await tx.delete(calendarEvent).where(eq(calendarEvent.id, e.id));
					report.deleted++;
					continue;
				}
				throw err;
			}
		} else result = await api.insert(toGoogle(e));
		await tx
			.update(calendarEvent)
			.set({
				googleEventId: result.id ?? e.googleEventId,
				googleEtag: result.etag ?? null,
				googleUpdatedAt: result.updated ? new Date(result.updated) : null,
				syncedVersion: e.version
			})
			.where(eq(calendarEvent.id, e.id));
		report.pushed++;
	}
}
