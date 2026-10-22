// -- DEP-TYPES -- //
import type { RequestHandler } from './$types';
// -- MODULES -- //
import { callerCtx, fail, json, readJson } from '#lib/server/api/http.js';
import { listDevices, registerDevice, unregisterDevice } from '#lib/server/ops/devices.js';

// -- FUNCTIONS -- //

/** The caller's phones, without push tokens. */
export const GET: RequestHandler = async ({ locals, request }) => {
	const c = await callerCtx(locals, request);
	if ('response' in c) return c.response;
	try {
		return json({ devices: await listDevices(c.ctx) });
	} catch (e) {
		return fail(e);
	}
};

/** Registers the phone, or refreshes its push token. */
export const POST: RequestHandler = async ({ locals, request }) => {
	const c = await callerCtx(locals, request);
	if ('response' in c) return c.response;
	try {
		const input = (await readJson(request)) as Parameters<typeof registerDevice>[1];
		return json({ device: await registerDevice(c.ctx, input) }, 201);
	} catch (e) {
		return fail(e);
	}
};

/** Removes a phone: on sign out, or when push says the token is gone. */
export const DELETE: RequestHandler = async ({ locals, request, url }) => {
	const c = await callerCtx(locals, request);
	if ('response' in c) return c.response;
	try {
		await unregisterDevice(c.ctx, { deviceId: url.searchParams.get('id') ?? '' });
		return json({ ok: true });
	} catch (e) {
		return fail(e);
	}
};
