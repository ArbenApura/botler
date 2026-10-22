// SENDING A PUSH THROUGH FIREBASE CLOUD MESSAGING (HTTP v1). THE SERVICE ACCOUNT KEY LIVES ONLY IN THE SERVER ENVIRONMENT.
// A push is only a nudge: a short title (never an amount), or a silent "look again" that makes the phone sync. The phone's own alarms do the
// reminding, so a missed push loses nothing.

// -- DEP-MODULES -- //
import { createSign } from 'node:crypto';

// -- TYPES -- //

export type Push =
	| { token: string; kind: 'sync' }
	| { token: string; kind: 'notice'; title: string; body?: string; key?: string };

/** `unregistered`: the token is dead and must be forgotten. `failed`: try again later. */
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
				const text = await res.text();
				// A token that was uninstalled or rotated: UNREGISTERED, or INVALID_ARGUMENT on the token itself
				if (res.status === 404 || /UNREGISTERED|registration-token-not-registered/i.test(text))
					return 'unregistered';
				if (res.status === 400 && /registration token|INVALID_ARGUMENT/i.test(text))
					return 'unregistered';
				console.error(JSON.stringify({ event: 'push_failed', status: res.status }));
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
