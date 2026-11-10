// QUEUES THE ONE-OFF NUTRIENT BACKFILL (BTL-20261110-1532) FOR EVERY PERSON, AS THE OWNER ROLE. THE ADDRESS COMES ONLY FROM DATABASE_OWNER_URL
// IN THE ENVIRONMENT, NEVER FROM THE COMMAND LINE, AND IS NEVER PRINTED.
// It only adds job rows: the worker then runs each one inside that person's own context and lock, and the job fills nothing but unknown
// values of old Filipino-list food entries. The key makes it once per person, so running this twice adds nothing.
// On the VPS this runs only on the owner's word. Usage: health-backfill

// -- DEP-MODULES -- //
import pg from 'pg';
// -- MODULES -- //
import { NUTRIENT_BACKFILL_SQL } from '../src/lib/server/jobs/backfillSql';

// -- FUNCTIONS -- //

const url = process.env.DATABASE_OWNER_URL;
if (!url) throw new Error('DATABASE_OWNER_URL is not set.');
const client = new pg.Client({ connectionString: url });
await client.connect();
try {
	const done = await client.query(NUTRIENT_BACKFILL_SQL.text, [...NUTRIENT_BACKFILL_SQL.values]);
	console.log(`${done.rowCount ?? 0} backfill jobs queued`);
} finally {
	await client.end();
}
