// A CHAT FOR A TEST PERSON: EVERY TURN BELONGS TO ONE, SO A TEST THAT WRITES A TURN BY HAND ASKS FOR THE PERSON'S NEWEST CHAT FIRST

// -- TYPES -- //
import type { Tx } from '../../src/lib/server/db/client';
// -- MODULES -- //
import { resolveChat } from '../../src/lib/server/ops/chats';

// -- FUNCTIONS -- //

/** The id of the person's newest chat, made when there is none. Run inside the person's own transaction. */
export async function chatOf(tx: Tx, userId: string): Promise<string> {
	return (await resolveChat(tx, userId, undefined)).id;
}
