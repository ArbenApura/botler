// -- DEP-TYPES -- //
import type { RequestHandler } from './$types';
// -- MODULES -- //
import { callerCtx, fail, json, readJson } from '#lib/server/api/http.js';
import { chatStatus, handleChat } from '#lib/server/agent/chat.js';
import { OpsError } from '#lib/server/ops/context.js';
import { getModelClient } from '#lib/server/proxy/index.js';

// -- FUNCTIONS -- //

/**
 * One chat message, answered as a stream of server-sent events (delta, tool, card, fallback, done). The app chooses clientMessageId, and
 * sending the same id again replays the stored answer instead of running the message twice. Problems with the message itself (bad
 * input, an id still being answered) are normal error responses, sent before the stream starts.
 */
export const POST: RequestHandler = async ({ locals, request }) => {
	const c = await callerCtx(locals, request);
	if ('response' in c) return c.response;
	let events: AsyncGenerator<unknown>;
	let first: IteratorResult<unknown>;
	try {
		const body = await readJson(request);
		events = handleChat(c.ctx, body, { model: getModelClient(), signal: request.signal });
		first = await events.next();
	} catch (e) {
		return fail(e);
	}
	const enc = new TextEncoder();
	const line = (e: unknown) => enc.encode(`data: ${JSON.stringify(e)}\n\n`);
	const stream = new ReadableStream<Uint8Array>({
		async start(controller) {
			try {
				if (!first.done) controller.enqueue(line(first.value));
				for await (const e of events) controller.enqueue(line(e));
			} catch (e) {
				// The stream has begun, so a failure is an event, not a status code. It says nothing about the cause
				const code = e instanceof OpsError ? e.code : 'INTERNAL';
				controller.enqueue(line({ type: 'error', code }));
			} finally {
				controller.close();
			}
		},
		cancel() {
			void events.return(undefined);
		}
	});
	return new Response(stream, {
		headers: {
			'content-type': 'text/event-stream',
			'cache-control': 'no-store',
			'x-accel-buffering': 'no'
		}
	});
};

/** How a message ended, for an app that lost the connection: ?id=<clientMessageId>. */
export const GET: RequestHandler = async ({ locals, request, url }) => {
	const c = await callerCtx(locals, request);
	if ('response' in c) return c.response;
	try {
		return json(await chatStatus(c.ctx, url.searchParams.get('id') ?? ''));
	} catch (e) {
		return fail(e);
	}
};
