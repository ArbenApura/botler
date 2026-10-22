// CLOSED REGISTRATION: ONLY GOOGLE EMAILS ON THE ALLOW-LIST FROM THE SERVER ENVIRONMENT MAY HAVE AN ACCOUNT

// -- FUNCTIONS -- //

/** Lower-cases and trims an address so a comparison never depends on case or stray spaces. */
export function normaliseEmail(email: string): string {
	return email.trim().toLowerCase();
}

/**
 * Reads the comma separated list from ALLOWED_EMAILS. An empty list is a configuration error, never "everyone":
 * the server stops at start instead of opening registration by accident.
 */
export function parseAllowList(raw: string | undefined): Set<string> {
	const list = (raw ?? '')
		.split(',')
		.map(normaliseEmail)
		.filter((e) => e.length > 0);
	if (list.length === 0)
		throw new Error(
			'ALLOWED_EMAILS is required: a comma separated list of the Google emails that may sign in.'
		);
	for (const e of list) {
		if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e))
			throw new Error(`ALLOWED_EMAILS has a bad address: ${e}`);
	}
	return new Set(list);
}

/** Whether this address may sign in. */
export function isAllowed(allow: ReadonlySet<string>, email: string | null | undefined): boolean {
	return !!email && allow.has(normaliseEmail(email));
}

/**
 * The person a request may act as: the session's user when their address is on the list, otherwise null.
 * Checked on every request, so taking an address off the list ends access at once, even for a session that is still valid.
 */
export function allowedUser<T extends { email: string }>(
	allow: ReadonlySet<string>,
	person: T | null | undefined
): T | null {
	return person && isAllowed(allow, person.email) ? person : null;
}
