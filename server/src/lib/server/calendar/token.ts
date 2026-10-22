// THE PERSON'S GOOGLE ACCESS TOKEN FOR CALENDAR CALLS. Better Auth stores the Google tokens encrypted and refreshes the access token when it
// expires. This asks it for a fresh one and checks the Calendar scope was granted. If the refresh is refused (the person revoked access, or the
// grant expired because the OAuth app is in testing) the answer is invalid_grant: the sync marks itself as needing a reconnect. The token is
// returned to the caller that makes the request and is never stored here, logged or sent anywhere else.

// -- TYPES -- //
import type { Auth } from '../auth/auth';
import type { DbHandle } from '../db/client';
// -- DEP-MODULES -- //
import { and, eq } from 'drizzle-orm';
// -- MODULES -- //
import { authAccount } from '../db/schema';
import { CALENDAR_SCOPE, GoogleAuthError } from './google';

// -- FUNCTIONS -- //

export function googleTokenGetter(
	handle: DbHandle,
	auth: Pick<Auth, 'api'>,
	userId: string
): () => Promise<string> {
	return async () => {
		const [acc] = await handle.db
			.select({ id: authAccount.id, scope: authAccount.scope })
			.from(authAccount)
			.where(and(eq(authAccount.userId, userId), eq(authAccount.providerId, 'google')));
		if (!acc) throw new GoogleAuthError('no_account');
		if (!(acc.scope ?? '').split(/[ ,]+/).includes(CALENDAR_SCOPE))
			throw new GoogleAuthError('no_scope');
		try {
			const r = await auth.api.getAccessToken({ body: { accountId: acc.id, userId } });
			if (!r.accessToken) throw new GoogleAuthError('invalid_grant');
			return r.accessToken;
		} catch (e) {
			if (e instanceof GoogleAuthError) throw e;
			// A refused refresh looks like an error from the auth library. Its text is not kept: it can hold token details
			throw new GoogleAuthError('invalid_grant');
		}
	};
}
