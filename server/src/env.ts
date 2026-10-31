// ENVIRONMENT VARIABLES, VALIDATED WHEN THE APP STARTS. A MISSING OR BAD VALUE FAILS LOUDLY, NEVER SILENTLY.
// More variables are added with the step that needs them (push in P6).

// -- DEP-MODULES -- //
import { defineEnvVars } from '@sveltejs/kit/env';
// -- MODULES -- //
import { fxUrlFromEnv } from './lib/server/fx/config';
import { DEFAULT_HISTORY_TOKENS } from './lib/server/agent/compact';
import {
	DEFAULT_CHAT_MAX_TOKENS,
	DEFAULT_TURN_TOKEN_BUDGET,
	parseChatEffort,
	positiveInt
} from './lib/server/proxy/chatEnv';

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
	FX_RATES_URL: {
		description:
			'The https address of the exchange rate feed: JSON with result "success", base_code "USD" and a rates table of units per dollar, for example https://open.er-api.com/v6/latest/USD. Required in production (the server stops at start without it); in development a missing value means no feed. It holds no key and no person data is ever sent to it. A value that is not https stops the server.',
		schema: (value) => fxUrlFromEnv(value, process.env.NODE_ENV === 'production')
	},
	DB_POOL_MAX: {
		description:
			'The most database connections the app holds. Default 10. A request that finds the pool full fails after 10 seconds instead of waiting for ever. A bad value stops the server.',
		schema: (value) => positiveInt(value, 10, 'DB_POOL_MAX')
	},
	BOTLER_AUTO_MIGRATE: {
		description: 'Set to 1 to run the migrations when the server starts (local development).',
		schema: (value) => (value === '1' ? '1' : '0')
	},
	MODEL_PROVIDER: {
		description:
			'Which model provider the agent runs on. Only deepseek exists today; empty means deepseek. Anything else stops the server.',
		schema: (value) => {
			if (!value || !value.trim()) return 'deepseek';
			const v = value.trim().toLowerCase();
			if (v !== 'deepseek') throw new Error('MODEL_PROVIDER must be deepseek');
			return v;
		}
	},
	DEEPSEEK_API_KEY: {
		description:
			'The DeepSeek API key, required only when MODEL_PROVIDER is deepseek. It lives only here, in the server environment, and is never returned, logged or put in the app.',
		schema: (value) => (value && value.trim() ? value.trim() : '')
	},
	DEEPSEEK_BASE_URL: {
		description:
			'The DeepSeek API address, https and without /v1. The assistant web search and page reading use it too, with the same key.',
		schema: (value) =>
			value && value.trim() ? value.trim().replace(/\/$/, '') : 'https://api.deepseek.com'
	},
	DEEPSEEK_MODEL: {
		description: 'The model name sent to DeepSeek (decided in P3.11).',
		schema: (value) => (value && value.trim() ? value.trim() : 'deepseek-flash')
	},
	DEEPSEEK_THINKING: {
		description:
			'1 or true: chat answers think first and the app shows the thinking (costs more tokens and some time). 0 or false: no thinking. Empty means on. Anything else stops the server.',
		schema: (value) => flag(value, true, 'DEEPSEEK_THINKING')
	},
	CHAT_MAX_TOKENS: {
		description:
			'The most tokens one chat model call may write, thinking and answer together. Default 64000. The monthly caps and TURN_TOKEN_BUDGET still apply. A bad value stops the server.',
		schema: (value) => positiveInt(value, DEFAULT_CHAT_MAX_TOKENS, 'CHAT_MAX_TOKENS')
	},
	CHAT_EFFORT: {
		description:
			'How hard the chat model thinks: low, medium, high or max. Empty means high. DeepSeek maps low and medium to high. Anything else stops the server.',
		schema: (value) => parseChatEffort(value)
	},
	TURN_TOKEN_BUDGET: {
		description:
			'The most charged tokens (cache reads and writes weighted, as the monthly cap counts them) one chat message may use over all its model calls. Default 300000. When it runs out the model is told to answer from what it has. A bad value stops the server.',
		schema: (value) => positiveInt(value, DEFAULT_TURN_TOKEN_BUDGET, 'TURN_TOKEN_BUDGET')
	},
	HISTORY_TOKENS: {
		description:
			'The most tokens of earlier messages (with their tool results) sent with a chat message. Past it the oldest messages drop, and a background job folds the earlier part of a long chat into a summary. Default 40000. A bad value stops the server.',
		schema: (value) => positiveInt(value, DEFAULT_HISTORY_TOKENS, 'HISTORY_TOKENS')
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
	BOTLER_RELEASES_DIR: {
		description:
			'The folder that holds the published Android builds (botler-<version>+<code>.apk) and latest.json. Mounted read-only. A missing folder only turns the update check into none.',
		schema: (value) => (value && value.trim() ? value.trim() : '/releases')
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

/** On or off: 1, true, 0 or false. Empty gives the default. A typo stops the server instead of silently choosing. */
function flag(value: string | undefined, fallback: boolean, name: string): boolean {
	if (!value || !value.trim()) return fallback;
	const v = value.trim().toLowerCase();
	if (v === '1' || v === 'true') return true;
	if (v === '0' || v === 'false') return false;
	throw new Error(`${name} must be 1, 0, true or false`);
}
