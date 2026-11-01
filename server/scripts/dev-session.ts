// MAKES A SESSION FOR THE LOCAL DEV DATABASE SO A DEBUG BUILD ON THE EMULATOR CAN SIGN IN WITHOUT GOOGLE (yarn dev:session).
// It refuses any database but Botler's local Postgres (127.0.0.1:5434), so it can never touch the VPS or AFB. It reads server/.env without printing it,
// signs the token the way Better Auth's bearer plugin expects, and writes it to a JSON file for `flutter run --dart-define-from-file`.
// The file holds a session token, so it lives in the git-ignored app/.dev folder and is never passed on a command line.

// -- DEP-MODULES -- //
import { createHmac, randomBytes } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import pg from 'pg';

// -- CONSTANTS -- //

const DEV_USER = 'user_dev_preview';
const OUT = resolve(import.meta.dirname, '../../app/.dev/dev-session.json');

// -- FUNCTIONS -- //

function loadEnv(): Record<string, string> {
	const out: Record<string, string> = {};
	for (const line of readFileSync(new URL('../.env', import.meta.url), 'utf8').split(/\r?\n/)) {
		const m = /^([A-Z][A-Z0-9_]*)=(.*)$/.exec(line);
		if (m) out[m[1] as string] = (m[2] as string).trim().replace(/^"|"$/g, '');
	}
	return out;
}

function mustBeLocal(url: string | undefined, name: string): string {
	if (!url) throw new Error(`${name} is missing in server/.env`);
	const u = new URL(url);
	if (!['localhost', '127.0.0.1'].includes(u.hostname) || u.port !== '5434')
		throw new Error(
			`${name} must point at Botler's local Postgres (127.0.0.1:5434). Nothing else is allowed here.`
		);
	return url;
}

async function main(): Promise<void> {
	const env = loadEnv();
	const ownerUrl = mustBeLocal(env.DATABASE_OWNER_URL, 'DATABASE_OWNER_URL');
	const secret = env.BETTER_AUTH_SECRET;
	if (!secret) throw new Error('BETTER_AUTH_SECRET is missing in server/.env');
	// The request check lets only a listed address act, so the preview person is the first one on the list
	const email = (env.ALLOWED_EMAILS ?? '')
		.split(',')
		.map((e) => e.trim().toLowerCase())
		.find(Boolean);
	if (!email) throw new Error('ALLOWED_EMAILS in server/.env is empty');
	const client = new pg.Client({ connectionString: ownerUrl });
	await client.connect();
	try {
		// Reuses the person if the local database already has them (a real sign in earlier), else makes a local-only row
		const found = await client.query<{ id: string; name: string }>(
			'select id, name from "user" where lower(email) = $1',
			[email]
		);
		let userId = found.rows[0]?.id;
		const name = found.rows[0]?.name ?? 'Dev preview';
		if (!userId) {
			userId = DEV_USER;
			await client.query(
				'insert into "user" (id, name, email, email_verified) values ($1, $2, $3, true) on conflict (id) do nothing',
				[userId, name, email]
			);
		}
		const token = randomBytes(24).toString('base64url');
		await client.query(
			`insert into auth_session (id, user_id, token, expires_at, user_agent)
			 values ($1, $2, $3, now() + interval '30 days', 'botler dev preview')`,
			[randomBytes(12).toString('hex'), userId, token]
		);
		const signature = createHmac('sha256', secret).update(token).digest('base64');
		const bearer = encodeURIComponent(`${token}.${signature}`);
		mkdirSync(dirname(OUT), { recursive: true });
		writeFileSync(
			OUT,
			JSON.stringify(
				{
					BOTLER_API: 'http://10.0.2.2:5280',
					DEV_SESSION_TOKEN: bearer,
					DEV_SESSION_EMAIL: email,
					DEV_SESSION_NAME: name
				},
				null,
				2
			)
		);
		console.log(
			`Dev session written to app/.dev/dev-session.json for the local database (user ${userId}).`
		);
	} finally {
		await client.end();
	}
}

main().catch((e) => {
	console.error(e instanceof Error ? e.message : String(e));
	process.exit(1);
});
