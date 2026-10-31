// THE TEST DATABASE GUARD: TESTS RUN ONLY ON BOTLER'S OWN LOCAL POSTGRES (127.0.0.1 OR LOCALHOST, PORT 5434), NEVER AFB'S 5433 OR A REMOTE HOST.

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { assertLocalTestPg } from '../support/testDb';

describe('assertLocalTestPg', () => {
	it('accepts the local Botler Postgres', () => {
		expect(() => assertLocalTestPg('postgres://u:p@127.0.0.1:5434/postgres')).not.toThrow();
		expect(() => assertLocalTestPg('postgres://u:p@localhost:5434/postgres')).not.toThrow();
	});
	it('refuses AFB port 5433', () => {
		expect(() => assertLocalTestPg('postgres://u:p@127.0.0.1:5433/postgres')).toThrow(/5433/);
	});
	it('refuses a remote host', () => {
		expect(() => assertLocalTestPg('postgres://u:p@db.example.com:5434/postgres')).toThrow(
			/db\.example\.com/
		);
	});
	it('refuses a URL with no port or a bad URL', () => {
		expect(() => assertLocalTestPg('postgres://u:p@127.0.0.1/postgres')).toThrow(/5432/);
		expect(() => assertLocalTestPg('not a url')).toThrow();
	});
});
