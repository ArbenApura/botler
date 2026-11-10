// THE ONE STATEMENT THAT QUEUES THE NUTRIENT BACKFILL (BTL-20261110-1532) FOR EVERY PERSON. NO DATABASE CODE HERE, SO THE SCRIPT THAT RUNS IT
// STAYS SMALL AND A TEST CAN RUN THE SAME TEXT.

// -- CONSTANTS -- //

/** The kind and key of the job. jobs/handlers.ts registers the handler under the same kind (a test checks they agree). */
export const NUTRIENT_BACKFILL_JOB = {
	kind: 'health.backfill_nutrients',
	key: 'filipino-2026-11'
} as const;

/** One job per person; a person who already has it gets nothing new. */
export const NUTRIENT_BACKFILL_SQL = {
	text: `insert into job (user_id, kind, key) select id, $1, $2 from "user" on conflict do nothing`,
	values: [NUTRIENT_BACKFILL_JOB.kind, NUTRIENT_BACKFILL_JOB.key]
} as const;
