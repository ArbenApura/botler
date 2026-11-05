// WHAT THE SERVER WORKS OUT FOR A PERSON TO ACCEPT (BTL-20261105-0015): ONE OPEN PROPOSAL OF EACH KIND, AND A NEW ONE TAKES THE PLACE OF THE OLD.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { ProposalKind } from '../db/schema';
// -- DEP-MODULES -- //
import { and, eq } from 'drizzle-orm';
// -- MODULES -- //
import { healthProposal } from '../db/schema';

// -- CONSTANTS -- //

const PROPOSAL_DAYS = 14;

// -- FUNCTIONS -- //

/** A new proposal replaces the open one of its kind, in the same transaction. */
export async function supersedeAndPropose(
	tx: Tx,
	userId: string,
	p: { kind: ProposalKind; weekKey: string; payload: unknown; basisHash: string; expiresAt?: Date }
) {
	await tx
		.update(healthProposal)
		.set({ status: 'superseded', updatedAt: new Date() })
		.where(
			and(
				eq(healthProposal.userId, userId),
				eq(healthProposal.kind, p.kind),
				eq(healthProposal.status, 'open')
			)
		);
	const [row] = await tx
		.insert(healthProposal)
		.values({
			userId,
			kind: p.kind,
			weekKey: p.weekKey,
			payload: p.payload,
			basisHash: p.basisHash,
			expiresAt: p.expiresAt ?? new Date(Date.now() + PROPOSAL_DAYS * 86_400_000)
		})
		.returning();
	return row;
}
