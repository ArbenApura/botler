// ROLES, GRANTS AND FORCED ROW LEVEL SECURITY, GENERATED FROM THE TABLE REGISTRY
// No schema diff can express these, and generating them from the registry means no user table can be forgotten.

// -- MODULES -- //
// Importing the whole schema registers every table before the statements are generated
import { PLAIN_TABLES, USER_TABLES } from './schema';

// -- CONSTANTS -- //

export const RUNTIME_ROLE = 'app_runtime';

const USER = "nullif(current_setting('app.user_id', true), '')";

// -- FUNCTIONS -- //

const q = (name: string) => `"${name}"`;

/** Every statement, in order, safe to run again. */
export function securityStatements(): string[] {
	const out: string[] = [];
	out.push(
		`DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${RUNTIME_ROLE}') THEN CREATE ROLE ${RUNTIME_ROLE} NOLOGIN NOSUPERUSER NOBYPASSRLS; END IF; END $$`
	);
	out.push(`GRANT USAGE ON SCHEMA public TO ${RUNTIME_ROLE}`);
	for (const name of PLAIN_TABLES) {
		out.push(`GRANT SELECT, INSERT, UPDATE, DELETE ON ${q(name)} TO ${RUNTIME_ROLE}`);
	}
	for (const t of USER_TABLES) {
		const col = q(t.userColumn);
		out.push(`ALTER TABLE ${q(t.name)} ENABLE ROW LEVEL SECURITY`);
		out.push(`ALTER TABLE ${q(t.name)} FORCE ROW LEVEL SECURITY`);
		out.push(`DROP POLICY IF EXISTS user_isolation ON ${q(t.name)}`);
		// WITH CHECK stops a write that would move a row to another person
		out.push(
			`CREATE POLICY user_isolation ON ${q(t.name)} FOR ALL TO ${RUNTIME_ROLE} USING (${col} = ${USER}) WITH CHECK (${col} = ${USER})`
		);
		// An append-only table is also stripped of any wider grant it may have had before
		if (t.appendOnly)
			out.push(`REVOKE UPDATE, DELETE, TRUNCATE ON ${q(t.name)} FROM ${RUNTIME_ROLE}`);
		out.push(
			t.appendOnly
				? `GRANT SELECT, INSERT ON ${q(t.name)} TO ${RUNTIME_ROLE}`
				: `GRANT SELECT, INSERT, UPDATE, DELETE ON ${q(t.name)} TO ${RUNTIME_ROLE}`
		);
	}
	// The owner runs the erase function (data_reset). Forced row level security binds the owner too, so it gets narrow policies of its own:
	// it can read and delete only the rows of the person set in the session, and add the one tombstone row to the trail. Nothing else.
	for (const t of USER_TABLES) {
		const col = t.userColumn;
		const own = `${col} = nullif(current_setting(''app.user_id'', true), '''')`;
		for (const [name, command, clause] of [
			['owner_reset_read', 'SELECT', `USING (${own})`],
			['owner_reset_delete', 'DELETE', `USING (${own})`],
			...(t.name === 'audit_event' ? [['owner_reset_insert', 'INSERT', `WITH CHECK (${own})`]] : [])
		] as const)
			out.push(
				`DO $$ BEGIN EXECUTE 'DROP POLICY IF EXISTS ${name} ON ${q(t.name)}'; EXECUTE format('CREATE POLICY ${name} ON ${q(t.name)} FOR ${command} TO %I ${clause}', current_user); END $$`
			);
	}
	out.push(
		`DO $$ BEGIN IF to_regprocedure('data_reset(text, text)') IS NOT NULL THEN REVOKE ALL ON FUNCTION data_reset(text, text) FROM PUBLIC; GRANT EXECUTE ON FUNCTION data_reset(text, text) TO ${RUNTIME_ROLE}; END IF; END $$`
	);
	out.push(`GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ${RUNTIME_ROLE}`);
	return out;
}
