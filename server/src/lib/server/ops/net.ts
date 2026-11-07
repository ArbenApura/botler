// NET BALANCE READS: THE BALANCES AND THE ASSETS WITH WHAT EACH WALLET HOLDS BACK FOR BILLS AND GOALS (BTL-20261030-0546)
// The pure rules are finance/net.ts. This file loads the plan once inside the caller's own transaction (ops/planData.ts, as the app_runtime role,
// so row level security keeps it to the caller's rows), reads the balances the same read already made, and adds the net next to the gross ones.
// The gross fields are never changed: an older app reads the same rows. The net is worked out in its own guarded block, so a stored schedule that
// cannot be read leaves the net out (null, with a notice) and the balances untouched. The server always works net out; whether it leads on screen
// is the person's setting (`showNetBalance`). sync.ts and computeAssets stay gross on purpose: they are polled and only the two verbs below show net.

// -- TYPES -- //
import type { Tx } from '../db/client';
import type { Ctx } from './context';
import type { NetHold, NetNote, NetResult, NetUnmatched } from '../../finance/net';
import type { AssetsView } from './assets';
// -- MODULES -- //
import { dayStart, toLocalDate } from '../../finance/dates';
import { computeNet } from '../../finance/net';
import { computeAssets, valueInMain } from './assets';
import { refreshInBackground } from '../fx/store';
import { run } from './context';
import { balancesIn } from './ledger';
import { loadPlan } from './planData';

// -- TYPES -- //

/** What one wallet holds back: all minor units of the wallet's own currency. */
export type NetFields = {
	netBalance: number | null;
	held: number | null;
	shortfall: number | null;
	holds: NetHold[];
	/** Set aside by rules here but no longer in the balance (spent); null when the net is unknown. */
	spentSetAside: number | null;
};

type Balances = Awaited<ReturnType<typeof balancesIn>>;

export type NetBalanceRow = Omit<Balances[number], 'wallets'> &
	NetFields & {
		wallets: (Balances[number]['wallets'][number] & NetFields)[];
		/** Bills due from this account that hold money in a currency it has no wallet in. */
		netUnmatched: NetUnmatched[];
		/** Bills due from this account with no amount yet: they hold nothing until the person sets one. */
		netMissing: { bill: string; dueDate: string }[];
		/** Bills before this date are held; null when the net could not be worked out. */
		netUntil: string | null;
		/** Plain words when the net could not be worked out; null otherwise. */
		netNotice: string | null;
	};

export type NetAssetWallet = AssetsView['wallets'][number] & {
	/** The net in the wallet's own currency, or null when it could not be worked out. */
	netBalance: number | null;
	shortfall: number | null;
	/** The net in the main currency, or null when the rate is missing or the net is unknown. */
	netValue: number | null;
};

export type NetAssetsView = Omit<AssetsView, 'wallets' | 'accounts'> & {
	wallets: NetAssetWallet[];
	accounts: (AssetsView['accounts'][number] & { netSubtotal: number | null })[];
	/** The sum of every wallet's net in the main currency, rates missing left out. A wallet's free money, not netted against another's shortfall. */
	netTotal: number | null;
	/** What bills due before the next payday still lack, in the main currency, rates missing left out. */
	shortfallTotal: number | null;
	netNotice: string | null;
};

// -- CONSTANTS -- //

const NOTICE =
	'The net balance could not be worked out because a stored schedule or amount could not be read. Balances are unchanged.';

// -- FUNCTIONS -- //

type Flat = { accountId: string; currency: string; balance: number };

/** The net of the wallets, or null when the plan could not be read or worked out. Never throws for bad stored data. */
async function netOf(
	tx: Tx,
	userId: string,
	now: Date,
	wallets: readonly Flat[]
): Promise<NetResult | null> {
	const today = toLocalDate(now);
	try {
		const { plan } = await loadPlan(tx, userId, { now, incomeSince: dayStart(today) });
		return computeNet(plan, wallets, today);
	} catch (e) {
		// A bad stored schedule is a RangeError from the pure rules; a failed query is not ours to hide
		if (e instanceof RangeError) return null;
		throw e;
	}
}

const empty: NetFields = {
	netBalance: null,
	held: null,
	shortfall: null,
	holds: [],
	spentSetAside: null
};

/** The balances of every active account with the net of each wallet and account. */
export async function accountBalancesWithNet(ctx: Ctx, now: Date = new Date()) {
	return run(ctx, async (tx, userId): Promise<NetBalanceRow[]> => {
		const rows = await balancesIn(tx, userId);
		const flat: Flat[] = rows.flatMap((a) =>
			a.wallets.map((w) => ({ accountId: a.id, currency: w.currency, balance: w.balance }))
		);
		const net = await netOf(tx, userId, now, flat);
		return rows.map((a) => {
			const wallets = a.wallets.map((w) => {
				const n = net?.wallets.find((x) => x.accountId === a.id && x.currency === w.currency);
				const fields: NetFields = n
					? {
							netBalance: n.net,
							held: n.held,
							shortfall: n.shortfall,
							holds: n.holds,
							spentSetAside: n.spentSetAside
						}
					: empty;
				return { ...w, ...fields };
			});
			const own = wallets[0] ?? { ...empty };
			const notes: NetNote[] = net?.notes ?? [];
			return {
				...a,
				wallets,
				netBalance: own.netBalance,
				held: own.held,
				shortfall: own.shortfall,
				holds: own.holds,
				spentSetAside: own.spentSetAside,
				netUnmatched: (net?.unmatched ?? []).filter((u) => u.accountId === a.id),
				netMissing: notes.flatMap((x) =>
					x.kind === 'missing_amount' && x.accountId === a.id
						? [{ bill: x.bill, dueDate: x.dueDate }]
						: []
				),
				netUntil: net?.until ?? null,
				netNotice: net ? null : NOTICE
			};
		});
	});
}

/** The assets (gross, as ever) with each wallet's net, converted at the stored rates, and the total net. */
export async function assetsSummaryWithNet(
	ctx: Ctx,
	now: Date = new Date()
): Promise<NetAssetsView> {
	const { view, status } = await run(ctx, async (tx, userId) => {
		const { view, status } = await computeAssets(tx, userId, now);
		const flat: Flat[] = view.wallets.map((w) => ({
			accountId: w.accountId,
			currency: w.currency,
			balance: w.balance
		}));
		const net = await netOf(tx, userId, now, flat);
		let netTotal = 0;
		let shortfallTotal = 0;
		const bySubtotal = new Map<string, number>();
		const wallets: NetAssetWallet[] = view.wallets.map((w) => {
			const n = net?.wallets.find((x) => x.accountId === w.accountId && x.currency === w.currency);
			if (!n) return { ...w, netBalance: null, shortfall: null, netValue: null };
			const netValue = valueInMain(n.net, w.currency, view.currency, status.rates);
			const shortValue = valueInMain(n.shortfall, w.currency, view.currency, status.rates);
			if (netValue !== null) {
				netTotal += netValue;
				bySubtotal.set(w.accountId, (bySubtotal.get(w.accountId) ?? 0) + netValue);
			}
			if (shortValue !== null) shortfallTotal += shortValue;
			return { ...w, netBalance: n.net, shortfall: n.shortfall, netValue };
		});
		const out: NetAssetsView = {
			...view,
			wallets,
			accounts: view.accounts.map((a) => ({
				...a,
				netSubtotal: net ? (bySubtotal.get(a.accountId) ?? 0) : null
			})),
			netTotal: net ? netTotal : null,
			shortfallTotal: net ? shortfallTotal : null,
			netNotice: net ? null : NOTICE
		};
		return { view: out, status };
	});
	refreshInBackground(ctx.handle, status);
	return view;
}
