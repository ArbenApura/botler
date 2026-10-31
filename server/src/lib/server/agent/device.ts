// THE PHONE AS A TOOL (BTL-20261031-1334): A TOOL THE SERVER ASKS THE PERSON'S PHONE TO RUN, AND THE ANSWER THE PHONE POSTS BACK.
// The agent loop stays on the server. When the model calls a device tool (a script, the toolbox), the turn registers a waiter under a call id made
// here, sends the call to the phone inside the chat stream (tool_start with the arguments), and waits. The phone runs it in its sandbox and posts the
// answer to the device-result route, which resolves the waiter. A waiter belongs to one person: another person's answer finds nothing. Nothing is stored.
// The answer is data from the phone: it is shaped (depth, length, count) before the model sees it, and it is never an instruction.

// -- DEP-MODULES -- //
import { randomUUID } from 'node:crypto';

// -- TYPES -- //

/** How a wait ended: the phone answered, the time ran out (the app is closed or slow), or the message was cancelled. */
export type DeviceOutcome =
	{ kind: 'answer'; ok: boolean; result: unknown } | { kind: 'timeout' } | { kind: 'cancelled' };

type Waiter = {
	userId: string;
	settle: (o: DeviceOutcome) => void;
};

// -- CONSTANTS -- //

/** The longest one string in a phone answer may be before the model sees it. */
export const DEVICE_STRING_MAX = 20_000;
const DEVICE_LIST_MAX = 60;
const DEVICE_DEPTH_MAX = 4;

const waiters = new Map<string, Waiter>();

// -- FUNCTIONS -- //

/** A fresh call id. Not the model's: the model cannot name or guess one. */
export const newCallId = (): string => `dc_${randomUUID()}`;

/**
 * Registers the wait for one call and returns the promise of its end. It never rejects. Call it BEFORE the call is sent to the phone, so an
 * answer that arrives at once finds its waiter.
 */
export function expectDevice(
	userId: string,
	callId: string,
	ms: number,
	signal?: AbortSignal
): Promise<DeviceOutcome> {
	return new Promise<DeviceOutcome>((resolve) => {
		// The timer is a one element list so the settle function can clear it before it exists
		const timer: { id?: ReturnType<typeof setTimeout> } = {};
		const onAbort = () => settle({ kind: 'cancelled' });
		const settle = (o: DeviceOutcome) => {
			if (!waiters.delete(callId)) return;
			clearTimeout(timer.id);
			signal?.removeEventListener('abort', onAbort);
			resolve(o);
		};
		waiters.set(callId, { userId, settle });
		timer.id = setTimeout(() => settle({ kind: 'timeout' }), ms);
		if (signal?.aborted) onAbort();
		else signal?.addEventListener('abort', onAbort, { once: true });
	});
}

/** The phone's answer to a call. False when no one waits for it (late, repeated, or another person's call). */
export function answerDevice(
	userId: string,
	callId: string,
	ok: boolean,
	result: unknown
): boolean {
	const w = waiters.get(callId);
	if (!w || w.userId !== userId) return false;
	w.settle({ kind: 'answer', ok, result });
	return true;
}

/** How many calls wait right now (tests, and a check that none are left behind). */
export const pendingDeviceCalls = (): number => waiters.size;

/** Keeps a phone answer to a small plain shape: limited depth, list length and string length; only text, numbers, booleans, null, lists, objects. */
export function shapeDeviceResult(value: unknown, depth = 0): unknown {
	if (value === null || typeof value === 'boolean') return value;
	if (typeof value === 'number') return Number.isFinite(value) ? value : null;
	if (typeof value === 'string')
		return value.length > DEVICE_STRING_MAX ? `${value.slice(0, DEVICE_STRING_MAX)}…` : value;
	if (depth >= DEVICE_DEPTH_MAX) return null;
	if (Array.isArray(value))
		return value.slice(0, DEVICE_LIST_MAX).map((v) => shapeDeviceResult(v, depth + 1));
	if (typeof value === 'object') {
		const out: Record<string, unknown> = {};
		for (const [k, v] of Object.entries(value as Record<string, unknown>).slice(0, DEVICE_LIST_MAX))
			out[k.slice(0, 80)] = shapeDeviceResult(v, depth + 1);
		return out;
	}
	return null;
}
