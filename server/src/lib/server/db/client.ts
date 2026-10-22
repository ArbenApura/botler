// THE DATABASE CLIENT: A POSTGRESQL CONNECTION POOL (pg) AND THE HANDLE THE APP, THE JOBS, THE SCRIPTS AND THE TESTS SHARE

// -- DEP-TYPES -- //
import type { PgDatabase, PgQueryResultHKT } from 'drizzle-orm/pg-core';
// -- DEP-MODULES -- //
import { drizzle as drizzlePg } from 'drizzle-orm/node-postgres';
import pg from 'pg';
// -- MODULES -- //
import * as schema from './schema';
import { pgExecutor, type SqlExecutor } from './executor';

// -- TYPES -- //

export type Db = PgDatabase<PgQueryResultHKT, typeof schema>;
export type Tx = Parameters<Parameters<Db['transaction']>[0]>[0];

/** One owner connection held for several statements, so BEGIN, the statements and COMMIT share a session. */
export type PinnedExecutor = SqlExecutor & { release(): void };

export type DbHandle = {
	db: Db;
	/** For migrations and setup, run as the owner. Each call may use a different pooled connection. */
	owner: SqlExecutor;
	/** The owner connection held for a sequence of statements (a migration, a lock). Release it when done. */
	pinOwner(): Promise<PinnedExecutor>;
	/**
	 * True when this connection is a superuser or the owner, so each transaction must switch to the runtime role.
	 * False when the connection already logs in as app_runtime.
	 */
	switchRole: boolean;
	close(): Promise<void>;
};

// -- FUNCTIONS -- //

/**
 * A real PostgreSQL connection pool. `runtimeUrl` logs in as app_runtime. `ownerUrl` is used only for migrations
 * and setup and may be omitted at runtime. Without a runtime URL the owner connection switches role per transaction.
 */
export function createPostgres(options: {
	runtimeUrl?: string;
	ownerUrl: string;
	/** Left out, the role is switched in each transaction when there is no runtime URL. Set false when the one URL already logs in as the runtime role. */
	switchRole?: boolean;
	/** Connections the pool may hold. */
	poolMax?: number;
}): DbHandle {
	const ownerPool = new pg.Pool({ connectionString: options.ownerUrl, max: options.poolMax ?? 2 });
	const runtimePool = options.runtimeUrl
		? new pg.Pool({ connectionString: options.runtimeUrl, max: options.poolMax ?? 10 })
		: ownerPool;
	// An idle connection that Postgres closes emits an error event. Without a listener it would crash the process
	for (const pool of new Set([ownerPool, runtimePool]))
		pool.on('error', (e) =>
			console.error(JSON.stringify({ event: 'pg_pool_error', error: e.name }))
		);
	return {
		db: drizzlePg(runtimePool, { schema }) as unknown as Db,
		owner: pgExecutor(ownerPool),
		pinOwner: async () => {
			const client = await ownerPool.connect();
			return { ...pgExecutor(client), release: () => client.release() };
		},
		switchRole: options.switchRole ?? !options.runtimeUrl,
		close: async () => {
			if (runtimePool !== ownerPool) await runtimePool.end();
			await ownerPool.end();
		}
	};
}
