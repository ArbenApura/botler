// THE PER REQUEST ALLOW-LIST DECISION AND THE HTTPS RULE FOR THE PUBLIC ADDRESS.

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { variables } from '../../src/env';
import { allowedUser, parseAllowList } from '../../src/lib/server/auth/allowlist';

type Standard = { '~standard': { validate(v: unknown): unknown } };

/** Runs one variable through its schema: returns the value, or throws the schema's message. */
function check(name: keyof typeof variables, value: string | undefined): unknown {
	const out = (variables[name].schema as unknown as Standard)['~standard'].validate(value) as {
		value?: unknown;
		issues?: { message: string }[];
	};
	if (out.issues?.length) throw new Error(out.issues.map((i) => i.message).join('; '));
	return out.value;
}

describe('per request allow-list', () => {
	it('ends access at once for a person taken off the list, even with a valid session', () => {
		const person = { id: 'u1', email: 'old@example.com' };
		expect(allowedUser(parseAllowList('old@example.com'), person)).toBe(person);
		expect(allowedUser(parseAllowList('new@example.com'), person)).toBeNull();
		expect(allowedUser(parseAllowList('new@example.com'), null)).toBeNull();
		expect(allowedUser(parseAllowList('new@example.com'), undefined)).toBeNull();
	});
});

describe('public address', () => {
	it('must be https except for localhost', () => {
		expect(check('BOTLER_BASE_URL', 'https://botler.arbenger.com/')).toBe(
			'https://botler.arbenger.com'
		);
		expect(check('BOTLER_BASE_URL', 'http://localhost:5280')).toBe('http://localhost:5280');
		expect(() => check('BOTLER_BASE_URL', 'http://botler.arbenger.com')).toThrow(/https/);
		expect(() => check('BOTLER_BASE_URL', 'not a url')).toThrow();
	});
});
