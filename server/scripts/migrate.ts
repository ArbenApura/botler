// APPLIES THE MIGRATIONS AND THE SECURITY STATEMENTS TO THE DATABASE IN DATABASE_OWNER_URL. RUN WITH: yarn db:migrate
// Local dev: DATABASE_OWNER_URL=postgres://postgres:localpostgrespassword@127.0.0.1:5434/botler
// On the VPS the same code runs from the built image (node cli/migrate.mjs). When BOTLER_RUNTIME_PASSWORD is set, the app_runtime
// role gets its login and password here, so the app connects as a role that owns nothing and cannot bypass row level security.

// -- DEP-MODULES -- //
import pg from 'pg';
// -- MODULES -- //
import { createPostgres } from '../src/lib/server/db/client';
import { migrateLocked } from '../src/lib/server/db/migrate';
import { RUNTIME_ROLE } from '../src/lib/server/db/security';

// -- FUNCTIONS -- //

async function main(): Promise<void> {
	const ownerUrl = process.env.DATABASE_OWNER_URL;
	if (!ownerUrl) throw new Error('DATABASE_OWNER_URL is required to run migrations.');
	const handle = createPostgres({ ownerUrl });
	try {
		const applied = await migrateLocked(handle);
		console.log(applied.length ? `Applied: ${applied.join(', ')}` : 'Nothing to apply.');
		const password = process.env.BOTLER_RUNTIME_PASSWORD;
		if (password) {
			// The password goes into DDL text, which cannot take a parameter, so it is escaped as a literal
			await handle.owner.exec(
				`ALTER ROLE ${RUNTIME_ROLE} LOGIN PASSWORD ${pg.escapeLiteral(password)}`
			);
			console.log('The runtime role login is set.');
		}
	} finally {
		await handle.close();
	}
}

main().catch((e) => {
	console.error(e instanceof Error ? e.message : e);
	process.exit(1);
});
