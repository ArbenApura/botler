// SENDING A PUSH THROUGH FIREBASE CLOUD MESSAGING (HTTP v1). THE SERVICE ACCOUNT KEY LIVES ONLY IN THE SERVER ENVIRONMENT.
// A push is only a nudge: a short title (never an amount), or a silent "look again" that makes the phone sync. The phone's own alarms do the
// reminding, so a missed push loses nothing.

// -- DEP-MODULES -- //
import { createSign } from 'node:crypto';

// -- TYPES -- //

export type Push =
	| { token: string; kind: 'sync' }
	| { token: string; kind: 'notice'; title: string; body?: string; key?: string };

/** `unregistered`: Firebase says the token is dead (UNREGISTERED or NOT_FOUND) and it must be forgotten. `failed`: anything else, the phone is kept. */
export type PushResult = 'sent' | 'unregistered' | 'failed';

export type Pusher = { send(p: Push): Promise<PushResult> };

export type FcmConfig = {
	projectId: string;
	clientEmail: string;
	privateKey: string;
	fetch?: typeof fetch;
	now?: () => number;
};

// -- CONSTANTS -- //

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

// -- FUNCTIONS -- //

const b64url = (s: string | Buffer) => Buffer.from(s).toString('base64url');

/** Firebase's own error code from an error body: the detail errorCode when there is one (UNREGISTERED), else the status (NOT_FOUND, INVALID_ARGUMENT). */
function errorCodeOf(body: string): string {
	try {
		const err = (JSON.parse(body) as { error?: { status?: unknown; details?: unknown } }).error;
		const details = Array.isArray(err?.details) ? err.details : [];
		for (const d of details) {
			const c = (d as { errorCode?: unknown } | null)?.errorCode;
			if (typeof c === 'string') return c;
		}
		return typeof err?.status === 'string' ? err.status : 'UNKNOWN';
	} catch {
		return 'UNKNOWN';
	}
}

/** Reads the service account JSON the server was given (base64 of the file). The private key is never logged or returned. */
export function parseServiceAccount(encoded: string): { clientEmail: string; privateKey: string } {
	let json: { client_email?: unknown; private_key?: unknown };
	try {
		json = JSON.parse(Buffer.from(encoded, 'base64').toString('utf8'));
	} catch {
		throw new Error('FCM_SERVICE_ACCOUNT must be the service account JSON file, encoded in base64');
	}
	if (typeof json.client_email !== 'string' || typeof json.private_key !== 'string')
		throw new Error('FCM_SERVICE_ACCOUNT is missing client_email or private_key');
	return { clientEmail: json.client_email, privateKey: json.private_key };
}

export function createFcmPusher(config: FcmConfig): Pusher {
	const doFetch = config.fetch ?? fetch;
	const now = config.now ?? Date.now;
	let cached: { token: string; expiresAt: number } | null = null;

	async function accessToken(): Promise<string> {
		if (cached && cached.expiresAt - 60_000 > now()) return cached.token;
		const iat = Math.floor(now() / 1000);
		const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
		const claims = b64url(
			JSON.stringify({
				iss: config.clientEmail,
				scope: SCOPE,
				aud: TOKEN_URL,
				iat,
				exp: iat + 3600
			})
		);
		const signature = createSign('RSA-SHA256')
			.update(`${header}.${claims}`)
			.sign(config.privateKey)
			.toString('base64url');
		const res = await doFetch(TOKEN_URL, {
			method: 'POST',
			headers: { 'content-type': 'application/x-www-form-urlencoded' },
			body: new URLSearchParams({
				grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
				assertion: `${header}.${claims}.${signature}`
			})
		});
		if (!res.ok) throw new Error(`fcm_auth_${res.status}`);
		const body = (await res.json()) as { access_token?: string; expires_in?: number };
		if (!body.access_token) throw new Error('fcm_auth_empty');
		cached = { token: body.access_token, expiresAt: now() + (body.expires_in ?? 3600) * 1000 };
		return cached.token;
	}

	return {
		async send(p) {
			try {
				const message =
					p.kind === 'sync'
						? { token: p.token, data: { type: 'sync' }, android: { priority: 'high' } }
						: {
								token: p.token,
								notification: { title: p.title, ...(p.body ? { body: p.body } : {}) },
								data: { type: 'notice', ...(p.key ? { key: p.key } : {}) },
								android: { priority: 'high' }
							};
				const res = await doFetch(
					`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(config.projectId)}/messages:send`,
					{
						method: 'POST',
						headers: {
							'content-type': 'application/json',
							authorization: `Bearer ${await accessToken()}`
						},
						body: JSON.stringify({ message })
					}
				);
				if (res.ok) return 'sent';
				const code = errorCodeOf(await res.text());
				// Only a token Firebase says is gone is forgotten: UNREGISTERED or NOT_FOUND. A 400 INVALID_ARGUMENT can be our own message that is
				// wrong, and forgetting the phone for that would silence it for good, so the phone is kept and the failure is only counted
				if (res.status === 404 || code === 'UNREGISTERED' || code === 'NOT_FOUND')
					return 'unregistered';
				// The status and Firebase's own error code only: never the body, which can hold the message text
				console.error(JSON.stringify({ event: 'push_failed', status: res.status, code }));
				return 'failed';
			} catch (e) {
				console.error(
					JSON.stringify({ event: 'push_error', error: e instanceof Error ? e.name : 'Error' })
				);
				return 'failed';
			}
		}
	};
}
