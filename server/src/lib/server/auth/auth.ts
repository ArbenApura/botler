// BETTER AUTH SETUP: GOOGLE SIGN IN ONLY, CLOSED TO AN ALLOW-LIST. THE PHONE USES A GOOGLE ID TOKEN AND A BEARER SESSION TOKEN.

// -- TYPES -- //
import type { DbHandle } from '../db/client';
// -- DEP-MODULES -- //
import { betterAuth } from 'better-auth';
import { drizzleAdapter } from 'better-auth/adapters/drizzle';
import { APIError } from 'better-auth/api';
import { bearer } from 'better-auth/plugins';
// -- MODULES -- //
import { authAccount, authRateLimit, authSession, authVerification, user } from '../db/schema';
import { isAllowed } from './allowlist';

// -- TYPES -- //

export type AuthConfig = {
	secret: string;
	baseUrl: string;
	google: { clientId: string; clientSecret: string };
	/** The Google emails that may have an account. Everyone else is refused before a user row exists. */
	allow: ReadonlySet<string>;
	/** Extra plugins, for example the SvelteKit cookie bridge, supplied by the app and not needed in tests. */
	plugins?: NonNullable<Parameters<typeof betterAuth>[0]['plugins']>;
	/** Turns the request limits off. Only for tests that sign in many times. */
	disableRateLimit?: boolean;
};

// -- FUNCTIONS -- //

function refuse(): never {
	throw new APIError('FORBIDDEN', {
		message: 'This account is not allowed to use Botler.',
		code: 'NOT_ALLOWED'
	});
}

export function createAuth(deps: { handle: DbHandle; config: AuthConfig }) {
	const { handle, config } = deps;
	const secure = config.baseUrl.startsWith('https://');

	return betterAuth({
		appName: 'Botler',
		baseURL: config.baseUrl,
		secret: config.secret,
		database: drizzleAdapter(handle.db, {
			provider: 'pg',
			schema: {
				user,
				session: authSession,
				account: authAccount,
				verification: authVerification,
				rateLimit: authRateLimit
			}
		}),
		emailAndPassword: { enabled: false },
		// Google tokens (including the refresh token Calendar sync will use) are encrypted at rest and never returned by any API
		account: { encryptOAuthTokens: true },
		socialProviders: {
			google: {
				clientId: config.google.clientId,
				clientSecret: config.google.clientSecret,
				// Only verified Google addresses count, so an unverified claim of a listed address never signs in
				mapProfileToUser: (profile) => {
					if (!profile.email_verified) refuse();
					return {};
				}
			}
		},
		session: { expiresIn: 60 * 60 * 24 * 30, updateAge: 60 * 60 * 24 },
		rateLimit: {
			enabled: !config.disableRateLimit,
			storage: 'database',
			window: 60,
			max: 60,
			customRules: { '/sign-in/social': { window: 60, max: 10 } }
		},
		advanced: {
			cookiePrefix: 'botler',
			useSecureCookies: secure,
			// Behind Caddy the client address arrives in X-Forwarded-For, so rate limits count per client and not per path
			ipAddress: { ipAddressHeaders: ['x-forwarded-for'] }
		},
		plugins: [bearer(), ...(config.plugins ?? [])],
		databaseHooks: {
			user: {
				create: {
					// Closed registration: an address that is not listed never gets a row
					before: async (u) => {
						if (!isAllowed(config.allow, u.email)) refuse();
					}
				}
			},
			session: {
				create: {
					// A person removed from the list loses the ability to start a session, even with an old account row
					before: async (session) => {
						const rows = await handle.db.query.user.findFirst({
							where: (t, { eq }) => eq(t.id, session.userId),
							columns: { email: true }
						});
						if (!isAllowed(config.allow, rows?.email)) refuse();
					}
				}
			}
		}
	});
}

export type Auth = ReturnType<typeof createAuth>;
