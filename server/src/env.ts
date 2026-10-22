// ENVIRONMENT VARIABLES, VALIDATED WHEN THE APP STARTS. A MISSING OR BAD VALUE FAILS LOUDLY, NEVER SILENTLY.
// More variables are added with the step that needs them (Calendar sync in P5, push in P6).

// -- DEP-MODULES -- //
import { defineEnvVars } from '@sveltejs/kit/env';

// -- CONSTANTS -- //

export const variables = defineEnvVars({
	DATABASE_URL: {
		description:
			'PostgreSQL connection for the app as the app_runtime role. The server refuses to start without it.',
		schema: optional
	},
	DATABASE_OWNER_URL: {
		description:
			'PostgreSQL connection as the migration owner, for migrations and BOTLER_AUTO_MIGRATE. Left out in production when migrations run as a separate step.',
		schema: optional
	},
	BOTLER_BASE_URL: {
		description:
			'The public address of this server, for example https://botler.arbenger.com. Used by sign in and its callbacks. Must be https unless it is localhost.',
		schema: (value) => {
			if (!value)
				throw new Error('BOTLER_BASE_URL is required, for example https://botler.arbenger.com');
			let url: URL;
			try {
				url = new URL(value);
			} catch {
				throw new Error(
					'BOTLER_BASE_URL must be a full address such as https://botler.arbenger.com'
				);
			}
			// Cookies lose their Secure flag over plain http, so only localhost may use it
			const local = url.hostname === 'localhost' || url.hostname === '127.0.0.1';
			if (url.protocol !== 'https:' && !local)
				throw new Error('BOTLER_BASE_URL must use https unless it is localhost');
			return value.replace(/\/$/, '');
		}
	},
	BETTER_AUTH_SECRET: {
		description:
			'A random secret of at least 32 characters that signs sessions and encrypts the stored Google tokens. Keep it private and stable.',
		schema: (value) => {
			if (!value || value.length < 32)
				throw new Error('BETTER_AUTH_SECRET is required and must be at least 32 characters');
			return value;
		}
	},
	GOOGLE_CLIENT_ID: {
		description:
			'The Google OAuth client id. For the phone, the web client id that verifies ID tokens.',
		schema: (value) => required(value, 'GOOGLE_CLIENT_ID')
	},
	GOOGLE_CLIENT_SECRET: {
		description: 'The Google OAuth client secret. Never returned or logged.',
		schema: (value) => required(value, 'GOOGLE_CLIENT_SECRET')
	},
	ALLOWED_EMAILS: {
		description:
			'Comma separated list of the Google emails that may sign in. Registration is closed to everyone else.',
		schema: (value) => required(value, 'ALLOWED_EMAILS')
	},
	FCM_PROJECT_ID: {
		description:
			'The Firebase project id for push notifications. Left out, push is off (the phone still syncs when opened and on a timer). Set together with FCM_SERVICE_ACCOUNT.',
		schema: (value) => (value && value.trim() ? value.trim() : '')
	},
	FCM_SERVICE_ACCOUNT: {
		description:
			'The Firebase service account JSON file, encoded in base64. Never returned or logged. Set together with FCM_PROJECT_ID.',
		schema: (value) => (value && value.trim() ? value.trim() : '')
	},
	BOTLER_AUTO_MIGRATE: {
		description: 'Set to 1 to run the migrations when the server starts (local development).',
		schema: (value) => (value === '1' ? '1' : '0')
	},
	DEEPSEEK_API_KEY: {
		description:
			'The DeepSeek API key. It lives only here, in the server environment, and is never returned, logged or put in the app.',
		schema: (value) => required(value, 'DEEPSEEK_API_KEY')
	},
	DEEPSEEK_BASE_URL: {
		description: 'The DeepSeek API address.',
		schema: (value) =>
			value && value.trim() ? value.trim().replace(/\/$/, '') : 'https://api.deepseek.com'
	},
	DEEPSEEK_MODEL: {
		description: 'The model name sent to DeepSeek (decided in P3.11).',
		schema: (value) => (value && value.trim() ? value.trim() : 'deepseek-flash')
	},
	BOTLER_CHAT_TOKEN_CAP: {
		description:
			'Tokens one person may use per month for chat. Default 8000000 (a turn is about 10000, mostly cached).',
		schema: (value) => positiveInt(value, 8_000_000, 'BOTLER_CHAT_TOKEN_CAP')
	},
	BOTLER_MEMORY_TOKEN_CAP: {
		description: 'Tokens one person may use per month for memory jobs. Default 2000000.',
		schema: (value) => positiveInt(value, 2_000_000, 'BOTLER_MEMORY_TOKEN_CAP')
	},
	BOTLER_GLOBAL_TOKEN_CAP: {
		description:
			'Tokens the whole service may use per month, both buckets together. Default 12000000.',
		schema: (value) => positiveInt(value, 12_000_000, 'BOTLER_GLOBAL_TOKEN_CAP')
	},
	BOTLER_RATE_PER_MINUTE: {
		description: 'Model calls one person may start per minute. Default 20.',
		schema: (value) => positiveInt(value, 20, 'BOTLER_RATE_PER_MINUTE')
	}
});

// -- FUNCTIONS -- //

// Plain function declarations, so the table above can use them before this line is reached

function optional(value: string | undefined) {
	return value && value.trim() !== '' ? value : undefined;
}

/** A value that must be present and not blank. */
function required(value: string | undefined, name: string): string {
	if (!value || !value.trim()) throw new Error(`${name} is required`);
	return value.trim();
}

/** A whole number above zero, or the default when the variable is empty. A bad value stops the server. */
function positiveInt(value: string | undefined, fallback: number, name: string): number {
	if (!value || !value.trim()) return fallback;
	const n = Number(value);
	if (!Number.isInteger(n) || n <= 0) throw new Error(`${name} must be a whole number above zero`);
	return n;
}
