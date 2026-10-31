// THE VERB REGISTRY: EVERY OPERATION THE APP, THE API AND THE ASSISTANT CAN RUN, EACH CLASSIFIED ONCE.
// - read:   returns data, changes nothing.
// - free:   records something (an expense, a transfer, a proposal), edits what the person already set up (an account, a bill, a goal, a
//           payday: name, amount, linked account), or adds to and removes from the money plan (an account, bill, goal, payday, rule or
//           currency wallet; owner decision 2026-10-28). The assistant runs it on its own; the audit trail names the assistant as the actor.
//           After untrusted text in a turn, and after the third delete of a turn, a free write becomes a card instead (agent/turn.ts).
// - gated:  counts or resets a balance. The assistant can only ask: it becomes an approval card and runs, as the person, after they
//           approve. The ops verb itself also refuses an assistant caller.
// - person: approving or retiring. Never offered to the assistant at all.
// Inputs are strict objects: a key that is not in the schema (a forged user_id, say) is refused, and the caller is never read from input.

// -- TYPES -- //
import type { z } from 'zod';
import type { Ctx } from './context';
// -- MODULES -- //
import {
	accountCreateInput,
	accountDeleteInput,
	accountIdInput,
	calcInput,
	cashflowForecastInput,
	balanceSimulateInput,
	accountUpdateInput,
	fxConvertInput,
	walletAddInput,
	walletRemoveInput,
	billDeleteInput,
	incomeDeleteInput,
	ruleDeleteInput,
	billCreateInput,
	billMarkPaidInput,
	billOccurrenceResetInput,
	billOccurrenceUpdateInput,
	billUpdateInput,
	dueRangeInput,
	emptyInput,
	expenseFromTextInput,
	expenseLogInput,
	goalCreateInput,
	goalDeleteInput,
	goalUpdateInput,
	incomeCreateInput,
	incomeRecordInput,
	incomeUpdateInput,
	eventCreateInput,
	eventIdInput,
	eventListInput,
	eventUpdateInput,
	limitInput,
	reminderCreateInput,
	reminderIdInput,
	routineCreateInput,
	routineUpdateInput,
	syncInput,
	taskCreateInput,
	taskListInput,
	taskUpdateInput,
	timerCreateInput,
	memoryEditInput,
	memoryFactIdInput,
	notebookCreateInput,
	notebookEditInput,
	notebookListInput,
	notebookOutlineInput,
	notebookPinInput,
	notebookRestoreInput,
	notebookSaveInput,
	notebookSearchInput,
	notebookTargetInput,
	notebookUpdateInput,
	pageCreateInput,
	pageEditInput,
	pageIdInput,
	pageMergeInput,
	pageMoveInput,
	pagePinInput,
	pageRenameInput,
	pageRevisionInput,
	pageSaveInput,
	pageSeenInput,
	pageTargetInput,
	pageUndeleteInput,
	memoryListInput,
	memoryRememberInput,
	memoryResolveInput,
	memorySearchInput,
	paydaysInput,
	schedulePreviewInput,
	settingsSetInput,
	accountHistoryInput,
	auditExportInput,
	chatArchiveInput,
	chatForkInput,
	chatRewindInput,
	chatHistoryInput,
	chatIdInput,
	chatPinInput,
	chatRenameInput,
	calendarRangeInput,
	pictureGetInput,
	markFromPhotoInput,
	markFromWebInput,
	dataResetInput,
	dataResetPreviewInput,
	profileSetInput,
	rangeInput,
	ruleFromTextInput,
	ruleIdInput,
	ruleProposeInput,
	ruleUpdateInput,
	rulesListInput,
	snapshotRecordInput,
	splitApproveInput,
	splitDeleteInput,
	splitListInput,
	splitProposeInput,
	splitSentInput,
	transferRecordInput,
	txnListInput,
	undoInput,
	wipeInput
} from '../db/zod';
import { accountHistory, exportAudit, verifyAudit } from './audit';
import { chatHistory } from './chatHistory';
import {
	chatArchive,
	chatClear,
	chatFork,
	chatRewind,
	chatList,
	chatListPageInput,
	chatNew,
	chatOpen,
	chatPin,
	chatRename
} from './chats';
import { calendarRange } from './calendarRange';
import { getPicture } from './picture';
import { markFromPhoto } from './markPhoto';
import { markFromWeb } from './markWeb';
import { previewDataReset, resetData } from './dataReset';
import { runCalc } from './calc';
import { cashflowForecast } from './forecast';
import { balanceSimulate } from './simulate';
import { fxConvert, fxRates, fxRatesRefresh } from './fx';
import { getSettings, setSettings } from './settings';
import {
	addWallet,
	archiveAccount,
	createAccount,
	deleteAccount,
	listAccounts,
	removeWallet,
	updateAccount
} from './accounts';
import {
	createBill,
	deleteBill,
	listBills,
	listDueBills,
	markBillPaid,
	resetBillOccurrence,
	updateBill,
	updateBillOccurrence
} from './bills';
import { OpsError, run } from './context';
import { accountBalancesWithNet, assetsSummaryWithNet } from './net';
import {
	listTransactions,
	listUndoable,
	logExpense,
	logExpenseFromText,
	recordIncome,
	recordRefund,
	recordSnapshot,
	recordTransfer,
	spendingSummary,
	undo,
	weeklyCheckin
} from './ledger';
import {
	createGoal,
	createIncome,
	deleteGoal,
	deleteIncome,
	listGoals,
	listIncome,
	nextPaydays,
	schedulePreview,
	updateGoal,
	updateIncome
} from './planning';
import {
	editFact,
	exportAll,
	forgetFact,
	getProfile,
	listFacts,
	rememberFact,
	resolveConflict,
	searchMemory,
	setProfile,
	wipeMemory
} from './memory';
import {
	createAlarm,
	createEvent,
	createReminder,
	createRoutine,
	createTask,
	createTimer,
	closeReminder,
	deleteEvent,
	listEvents,
	listReminders,
	listRoutines,
	listTasks,
	updateEvent,
	updateRoutine,
	updateTask
} from './schedule';
import { syncGet } from './sync';
import {
	createNotebook,
	deleteNotebook,
	editNotebook,
	getNotebook,
	listNotebooks,
	listRevisions,
	restoreRevision,
	saveNotebook,
	undeleteNotebook,
	updateNotebook
} from './notebook';
import {
	createPage,
	deletePage,
	editPage,
	getPage,
	mergePages,
	movePage,
	notebookOutline,
	notebookSearch,
	pageActivity,
	pageBacklinks,
	pageRevisionGet,
	pageRevisions,
	pageSeen,
	pinNotebook,
	pinPage,
	renamePage,
	restorePage,
	savePage,
	undeletePage
} from './notebookPage';
import {
	approveRule,
	deleteRule,
	listRules,
	proposeRule,
	proposeRuleFromText,
	updateRule,
	retireRule
} from './rules';
import { parse, requireBill } from './shared';
import {
	approveSplit,
	deleteSplits,
	listSplits,
	markTransferSent,
	proposeSplitPlan,
	upcomingPaydays
} from './split';

// -- TYPES -- //

export type VerbKind = 'read' | 'free' | 'gated' | 'person';

export type Verb = {
	/** Letters, digits and underscores, so it can be the name of a model tool. */
	name: string;
	description: string;
	kind: VerbKind;
	/** The strict input object. */
	input: z.ZodObject;
	/** Parses the input (strict) and runs the verb as the caller in `ctx`. */
	run(ctx: Ctx, raw: unknown): Promise<unknown>;
	/** For a free verb: true when, for this input, the assistant may not run it on its own. */
	gatedWhen?(ctx: Ctx, args: unknown): Promise<boolean>;
	/** What it returns can hold text someone else wrote (a calendar entry): reading it closes the turn to writes, like a web page. */
	taints: boolean;
	/**
	 * False for a verb that is for the app only: it is never offered to the assistant as a tool, and the assistant is refused if it names it.
	 * The app still calls it (the old memory screen, the notebook page). Left out, the assistant may use it unless it is person-only.
	 */
	agent: boolean;
	/** The input as the assistant is offered it, when some fields are for the app only. */
	agentInput?: z.ZodObject;
	/** True when the assistant is refused a field left out of `agentInput`, instead of the field being accepted (a notebook id on a card). */
	agentStrict: boolean;
};

// -- FUNCTIONS -- //

function verb<S extends z.ZodObject>(v: {
	name: string;
	description: string;
	kind: VerbKind;
	input: S;
	run: (ctx: Ctx, args: z.infer<S>) => Promise<unknown>;
	gatedWhen?: (ctx: Ctx, args: z.infer<S>) => Promise<boolean>;
	taints?: boolean;
	agent?: boolean;
	/** Fields the assistant never sees in its tool schema (they are for the app only, and are ignored if it sends them anyway). */
	agentOmit?: readonly (keyof z.infer<S> & string)[];
	/** The assistant is refused the omitted fields when it sends them, instead of the verb accepting them. */
	agentStrict?: boolean;
}): Verb {
	const strict = v.input.strict();
	const agentInput = v.agentOmit?.length
		? v.input.omit(Object.fromEntries(v.agentOmit.map((k) => [k, true])) as never).strict()
		: undefined;
	return {
		name: v.name,
		description: v.description,
		kind: v.kind,
		taints: v.taints ?? false,
		agent: v.agent ?? true,
		agentStrict: v.agentStrict ?? false,
		...(agentInput ? { agentInput } : {}),
		input: strict,
		// The assistant is held to the input it is offered: a field left out of its schema (an id) is refused, not ignored
		run: (ctx, raw) =>
			v.run(
				ctx,
				parse(
					ctx.actor.kind === 'agent' && agentInput && v.agentStrict
						? (agentInput ?? strict)
						: strict,
					raw
				) as z.infer<S>
			),
		...(v.gatedWhen
			? {
					gatedWhen: (ctx: Ctx, args: unknown) =>
						v.gatedWhen?.(ctx, args as z.infer<S>) ?? Promise.resolve(false)
				}
			: {})
	};
}

export const VERBS: readonly Verb[] = [
	// -- READ -- //
	verb({
		name: 'picture_get',
		kind: 'read',
		description:
			'One picture that marks an account or a bill, by its imageId: the kind and the image as base64 text. For the app only.',
		input: pictureGetInput,
		agent: false,
		run: (ctx, a) => getPicture(ctx, a)
	}),
	verb({
		name: 'accounts_list',
		kind: 'read',
		description: 'List the accounts (RCBC, GCash, Maya, cash ...).',
		input: emptyInput,
		run: (ctx) => listAccounts(ctx)
	}),
	verb({
		name: 'accounts_balances',
		kind: 'read',
		description:
			'The balance of every account right now, and its net: netBalance is what is left of the wallet after money already owed to bills due before the next payday (held, with holds naming each bill or linked rule with its date) and money kept for a goal. shortfall is what a bill due before the next payday still lacks. The minimum balance is separate (belowMinimum). Say that a figure is net and name what is held.',
		input: emptyInput,
		run: (ctx) => accountBalancesWithNet(ctx)
	}),
	verb({
		name: 'assets_summary',
		kind: 'read',
		description:
			'The total of everything the person owns, in their main currency: every currency wallet of every account with its balance, its value in the main currency, the rate used and the date of the rates. A currency with no known rate is listed as missing and left out of the total. netTotal is the same total after money held for bills due before the next payday and for goals (shortfallTotal is what those bills still lack). Use this for "how much do I have in total".',
		input: emptyInput,
		run: (ctx) => assetsSummaryWithNet(ctx)
	}),
	verb({
		name: 'fx_convert',
		kind: 'read',
		description:
			'Convert an amount between two currencies at the stored exchange rates. amount is in the smallest unit of "from" (cents for dollars, whole yen for yen); the answer is in the smallest unit of "to", with the rate and its date. For a question like "how much is 50 dollars in pesos"; it never changes anything.',
		input: fxConvertInput,
		run: (ctx, a) => fxConvert(ctx, a)
	}),
	verb({
		name: 'bills_list',
		kind: 'read',
		description: 'List the bills with what each is expected to cost.',
		input: emptyInput,
		run: (ctx) => listBills(ctx)
	}),
	verb({
		name: 'bills_due',
		kind: 'read',
		description:
			'Bills falling due between two dates (YYYY-MM-DD, Manila), paid or not. Each row has dueDate (the day it is due now), originalDueDate (the day the schedule gave it; different when that one date was moved), overridden, the amount and the accountId for that date. Use billId with dueDate to change one date.',
		input: dueRangeInput,
		run: (ctx, a) => listDueBills(ctx, a.from, a.to)
	}),
	verb({
		name: 'goals_list',
		kind: 'read',
		description: 'List the savings goals.',
		input: emptyInput,
		run: (ctx) => listGoals(ctx)
	}),
	verb({
		name: 'income_list',
		kind: 'read',
		description: 'List the income schedules (paydays).',
		input: emptyInput,
		run: (ctx) => listIncome(ctx)
	}),
	verb({
		name: 'income_paydays',
		kind: 'read',
		description: 'The next paydays of one income.',
		input: paydaysInput,
		run: (ctx, a) => nextPaydays(ctx, a.incomeId, a.count)
	}),
	verb({
		name: 'schedule_preview',
		kind: 'read',
		description:
			'Say what a repeat schedule means and when it falls next, before it is saved. Schedule kinds: monthly (day, or -1 for the last day), semi_monthly, every_n_days, weekly (days, and for every few weeks everyWeeks plus anchor, a YYYY-MM-DD date that falls on one of those weekdays), nth_weekday (n 1-5 or -1, weekday 0 Sunday to 6 Saturday), week_of_month (n, basis days or calendar, pick window or weekday), day_range (from, to), yearly, once (date, a YYYY-MM-DD, for a bill that happens one time only). Add everyMonths and anchorMonth (YYYY-MM) for every few months. Every field of the rule, anchor included, goes inside the "schedule" object, never beside it. Example every other Wednesday: {"schedule":{"kind":"weekly","days":[3],"everyWeeks":2,"anchor":"2026-10-28"}}. A payday rule can also carry startsOn and endsOn (YYYY-MM-DD, the first and last date that count) and skipDates (dates left out, up to 60), for example to skip one Monday: {"schedule":{"kind":"weekly","days":[1],"skipDates":["2026-11-02"]}}. Use this tool to try a schedule idea; the answer lists the dates and shows the limits in its sentence. Never change a live payday or bill just to see what a schedule does.',
		input: schedulePreviewInput,
		run: (ctx, a) => schedulePreview(ctx, a)
	}),
	verb({
		name: 'settings_get',
		kind: 'read',
		description: 'The currency, language and week start the person has chosen.',
		input: emptyInput,
		run: (ctx) => getSettings(ctx)
	}),
	verb({
		name: 'calendar_range',
		kind: 'read',
		description:
			'Everything dated between two days (at most 92): bills as payment windows, paydays, events, routines, tasks and reminders, with an estimate of what the accounts will hold.',
		input: calendarRangeInput,
		run: (ctx, a) => calendarRange(ctx, a)
	}),
	verb({
		name: 'audit_verify',
		kind: 'read',
		description:
			'Check that the trail of everything done to the money and plan is whole and unchanged.',
		input: emptyInput,
		run: (ctx) => verifyAudit(ctx)
	}),
	verb({
		name: 'account_history',
		kind: 'read',
		taints: true,
		description:
			'Everything that happened to one account, newest first: who did it (the person, the assistant, a job, sync), through which way in, the amount and the balance after each entry. Filter by actor, action, dates or a word. Answer from these fields only.',
		input: accountHistoryInput,
		run: (ctx, a) => accountHistory(ctx, a)
	}),
	verb({
		name: 'rules_list',
		kind: 'read',
		description: 'List the allocation rules, optionally by status.',
		input: rulesListInput,
		run: (ctx, a) => listRules(ctx, a.status)
	}),
	verb({
		name: 'ledger_list',
		kind: 'read',
		description: 'Recent entries, newest first. Dates are YYYY-MM-DD in Manila.',
		input: txnListInput,
		run: (ctx, a) => listTransactions(ctx, a)
	}),
	verb({
		name: 'ledger_spending',
		kind: 'read',
		description: 'What was spent between two dates, by category, plus the untracked part.',
		input: rangeInput,
		run: (ctx, a) => spendingSummary(ctx, a)
	}),
	verb({
		name: 'ledger_checkin',
		kind: 'read',
		description: 'Which accounts are due for a balance count, and last week untracked spending.',
		input: emptyInput,
		run: (ctx) => weeklyCheckin(ctx)
	}),
	verb({
		name: 'ledger_undoable',
		kind: 'read',
		description: 'Recent entries that can be undone.',
		input: limitInput,
		run: (ctx, a) => listUndoable(ctx, a.limit)
	}),
	verb({
		name: 'split_list',
		kind: 'read',
		description:
			'Recent payday splits, newest first, with their id, payday, pay and status. Splits replaced by a newer proposal are left out unless includeReplaced is true.',
		input: splitListInput,
		run: (ctx, a) => listSplits(ctx, a.limit, a.includeReplaced)
	}),
	verb({
		name: 'split_upcoming',
		kind: 'read',
		description: 'The next paydays across all incomes.',
		input: emptyInput,
		run: (ctx) => upcomingPaydays(ctx)
	}),

	verb({
		name: 'calc',
		kind: 'read',
		description:
			'A calculator that is exact (no rounding noise). Use it for every sum beyond one small addition: totals, percentages, splits, loans, how long until a goal, days between dates. Send the lines in order; a line may name its result (name) and later lines use the name, or line1, line2 and so on. Numbers are plain, no thousands commas. Operators + - * / ^ and brackets; 5% is 0.05, so 200 * 5% is 10. Functions: round(x, places) floor ceil abs min max sum avg sqrt pow ln exp, pmt(rate, periods, present) fv pv nper with the signs of a spreadsheet (money paid out is negative), and for dates between quotes: days(from, to), add_days(date, n), add_months(date, n). Pass currency (and unit minor when the number is already in centavos or cents) to get the line as written money. Quote the values it returns as they are.',
		input: calcInput,
		run: (ctx, a) => runCalc(ctx, a)
	}),
	verb({
		name: 'cashflow_forecast',
		kind: 'read',
		description:
			'What the accounts will hold from today to a date (at most 366 days), worked out by the server: the balance now of every wallet, the paydays, the unpaid bills by due date (with any date, amount or account changed for one date), and the payday moves of the approved rules (only what each account is missing: funding lists per payday the bills paid from money already in their account (covered), from a rule that saves for them (funded) and what is still needed; brokenLinks names rules that cannot save for their bill). Group by day (up to 62 days), week or month. Each period gives its start and end totals in the main currency, every payment in, out and moved with its date, the wallets that changed, and the end balance of each account; warnings say when a wallet goes below zero. Wallets of other currencies are converted at the stored rates and one with no rate is named and left out. Use this, never bills_due added by hand, for "how much will I have by ..." and for week by week tallies, and quote its numbers as they are. Read its notes before quoting a total.',
		input: cashflowForecastInput,
		run: (ctx, a) => cashflowForecast(ctx, a)
	}),

	verb({
		name: 'balance_simulate',
		kind: 'read',
		description:
			"The balance timeline on any dates from 5 years back to 5 years ahead, grouped by day (up to 62 days), week (up to 2 years), month or year. Every number says its source: recorded (the real ledger), replay (what today's plan would have done in a past period, from the recorded balance at its start; gap is recorded minus replay) or simulated (the future from today's balances, paydays, bills and payday rules). missed counts paydays and bills the plan expected but nobody recorded. view detail (at most 366 days) adds every entry. scenario is a what-if that is never saved: off (ids of paydays, bills, rules or goals to switch off), amounts (a payday or bill id with another amount), skipDates (paydays that do not come), lateDays (every bill paid that many days late), defer (deferrable bills wait for the next payday), extra (pretend money in or out in the main currency, at most 50). Use it for past balances (what did I have in March), dates more than a year ahead and what-ifs (what if I skip my next payday); for today to a date use cashflow_forecast. Always say that replay and simulated numbers are simulations, not real money, and read its notes before you answer.",
		input: balanceSimulateInput,
		agentOmit: ['offset', 'limit', 'groupKey'],
		run: (ctx, a) => balanceSimulate(ctx, a)
	}),
	verb({
		name: 'notebook_get',
		kind: 'read',
		description:
			'Read the main notebook (leave the title out; it is already in your prompt), or the page called Overview of another notebook, named by its title. For the other pages of a notebook use notebook_outline to see them and page_get to read them.',
		input: notebookTargetInput,
		agentOmit: ['notebookId'],
		agentStrict: true,
		run: (ctx, a) => getNotebook(ctx, a)
	}),
	verb({
		name: 'notebook_list',
		kind: 'read',
		description:
			'List your notebooks: the main one first, then the others with their title, one-line summary and size (their pages are in notebook_outline). With deleted true, the deleted ones that can still be restored.',
		input: notebookListInput,
		run: (ctx, a) => listNotebooks(ctx, a)
	}),
	verb({
		name: 'notebook_revisions',
		kind: 'read',
		agent: false,
		description: 'The changes made to a notebook, newest first.',
		input: notebookTargetInput,
		run: (ctx, a) => listRevisions(ctx, a)
	}),
	verb({
		name: 'notebook_outline',
		kind: 'read',
		description:
			'The outline of your notebook library: every notebook with its summary and its pages in order (a page, then its sub-pages), each with its size. Name one notebook by its title to see only that one. With deleted true, the deleted pages that can still be restored. Read it before you file, move, merge or tidy anything, so you use the pages that exist.',
		input: notebookOutlineInput,
		agentOmit: ['notebookId'],
		agentStrict: true,
		run: (ctx, a) => notebookOutline(ctx, a)
	}),
	verb({
		name: 'notebook_search',
		kind: 'read',
		description:
			'Search the titles and texts of your pages (not the main notebook, which is in your prompt). Returns the notebook, the page, and a snippet around the match. Use it to find where something is kept before you open it with page_get.',
		input: notebookSearchInput,
		agentOmit: ['notebookId'],
		agentStrict: true,
		run: (ctx, a) => notebookSearch(ctx, a)
	}),
	verb({
		name: 'page_get',
		kind: 'read',
		description:
			'Read a page: its text, version, who wrote it last and its sub-pages. Name it by its notebook title and its page title (and its parent page only when the same title is used under two parents; parent "top level" means the top-level one). Read a page before you answer from it or change it.',
		input: pageTargetInput,
		agentOmit: ['pageId'],
		agentStrict: true,
		run: (ctx, a) => getPage(ctx, a)
	}),
	verb({
		name: 'page_revisions',
		kind: 'read',
		agent: false,
		description: 'The changes made to a page, newest first.',
		input: pageIdInput,
		run: (ctx, a) => pageRevisions(ctx, a)
	}),
	verb({
		name: 'page_revision_get',
		kind: 'read',
		agent: false,
		description: 'The full text of one earlier version of a page.',
		input: pageRevisionInput,
		run: (ctx, a) => pageRevisionGet(ctx, a)
	}),
	verb({
		name: 'page_backlinks',
		kind: 'read',
		agent: false,
		description: 'The pages that point at this page with [[Page]] or [[Notebook/Page]].',
		input: pageIdInput,
		run: (ctx, a) => pageBacklinks(ctx, a)
	}),
	verb({
		name: 'page_activity',
		kind: 'read',
		agent: false,
		description: 'The pages the assistant changed in the last 14 days, newest first.',
		input: emptyInput,
		run: (ctx) => pageActivity(ctx)
	}),
	verb({
		name: 'memory_list',
		agent: false,
		kind: 'read',
		description:
			'What is remembered about the person. history adds replaced facts, pending shows facts waiting for a choice.',
		input: memoryListInput,
		run: (ctx, a) => listFacts(ctx, a)
	}),
	verb({
		name: 'memory_search',
		agent: false,
		kind: 'read',
		description: 'Search the remembered facts for a question.',
		input: memorySearchInput,
		run: (ctx, a) => searchMemory(ctx, a)
	}),
	verb({
		name: 'profile_get',
		agent: false,
		kind: 'read',
		description: 'The persona, the about lines and the private names the person set.',
		input: emptyInput,
		run: (ctx) => getProfile(ctx)
	}),

	verb({
		name: 'task_list',
		kind: 'read',
		description: 'The open tasks (status done or dropped for the others), soonest first.',
		input: taskListInput,
		run: (ctx, a) => listTasks(ctx, a)
	}),
	verb({
		name: 'event_list',
		kind: 'read',
		description: 'Calendar events between two dates (YYYY-MM-DD, Manila).',
		input: eventListInput,
		run: (ctx, a) => listEvents(ctx, a)
	}),
	verb({
		name: 'routine_list',
		kind: 'read',
		description: 'The routines (repeating things with a time).',
		input: emptyInput,
		run: (ctx) => listRoutines(ctx)
	}),
	verb({
		name: 'reminder_list',
		kind: 'read',
		description: 'The reminders that are scheduled.',
		input: emptyInput,
		run: (ctx) => listReminders(ctx)
	}),
	verb({
		name: 'sync_get',
		kind: 'read',
		description: 'What the phone should have: reminders, the summary card.',
		// For the phone only: it takes the person lock to settle reminders, and the assistant has no use for it
		agent: false,
		input: syncInput,
		run: (ctx, a) => syncGet(ctx, a)
	}),

	// -- FREE -- //
	verb({
		name: 'task_create',
		kind: 'free',
		description:
			'Add a task or follow-up. dueAt and followUpAt are instants like 2026-10-22T09:00:00+08:00.',
		input: taskCreateInput,
		run: (ctx, a) => createTask(ctx, a)
	}),
	verb({
		name: 'task_update',
		kind: 'free',
		description: 'Change a task, or set status done or dropped.',
		input: taskUpdateInput,
		run: (ctx, a) => updateTask(ctx, a)
	}),
	verb({
		name: 'event_create',
		kind: 'free',
		description: 'Add a calendar event.',
		input: eventCreateInput,
		run: (ctx, a) => createEvent(ctx, a)
	}),
	verb({
		name: 'event_update',
		kind: 'free',
		description: 'Change a calendar event.',
		input: eventUpdateInput,
		run: (ctx, a) => updateEvent(ctx, a)
	}),
	verb({
		name: 'event_delete',
		kind: 'free',
		description: 'Remove a calendar event.',
		input: eventIdInput,
		run: (ctx, a) => deleteEvent(ctx, a)
	}),
	verb({
		name: 'routine_create',
		kind: 'free',
		description:
			'Add a routine: a repeating thing with a time (daily, weekly on days 0 Sunday to 6 Saturday, monthly, every n days).',
		input: routineCreateInput,
		run: (ctx, a) => createRoutine(ctx, a)
	}),
	verb({
		name: 'routine_update',
		kind: 'free',
		description: 'Change a routine, or switch it off with active false.',
		input: routineUpdateInput,
		run: (ctx, a) => updateRoutine(ctx, a)
	}),
	verb({
		name: 'reminder_create',
		kind: 'free',
		description: 'Remind the person of something at a time (an instant).',
		input: reminderCreateInput,
		run: (ctx, a) => createReminder(ctx, a)
	}),
	verb({
		name: 'alarm_create',
		kind: 'free',
		description: 'Set an alarm on the phone clock at a time (an instant).',
		input: reminderCreateInput,
		run: (ctx, a) => createAlarm(ctx, a)
	}),
	verb({
		name: 'timer_create',
		kind: 'free',
		description: 'Start a timer for some minutes on the phone.',
		input: timerCreateInput,
		run: (ctx, a) => createTimer(ctx, a)
	}),
	verb({
		name: 'reminder_cancel',
		kind: 'free',
		description: 'Cancel a reminder, alarm or timer.',
		input: reminderIdInput,
		run: (ctx, a) => closeReminder(ctx, a)
	}),
	verb({
		name: 'notebook_edit',
		kind: 'free',
		description:
			'Change a notebook: your main notebook (the notes you keep about the person, read before every answer, for their main topics and essentials: how they like you to talk, lasting preferences and rules, the people in their life, ongoing plans) or another notebook, named by its title (for other information that does not belong in the main one). Leave the notebook out for the main one; on another notebook this reaches only its page called Overview, so use page_edit for its other pages. Write a lasting fact here as soon as the person says it or asks you to remember it. op add: heading and line (one short sentence; the heading is made if it is missing). op replace: find (exact text that appears once) and replacement. op remove: find. Never put a balance, an account number or anything one-off in it. A change to the main notebook applies from the next message.',
		input: notebookEditInput,
		agentOmit: ['notebookId'],
		agentStrict: true,
		run: (ctx, a) => editNotebook(ctx, a)
	}),
	verb({
		name: 'notebook_create',
		kind: 'free',
		description:
			'Make a new notebook for other information than the main topics and essentials (for example a trip, a project, recipes, a list of gift ideas). Do this only when the person asks for it or agrees to your suggestion; otherwise suggest it in a sentence and wait. Give a short unique title, one line saying what it holds and when to open it (it shows in the list under your main notebook), and optionally its first text in Markdown with # headings. Keep the main notebook for essentials: it should only say that the notebook exists, through the list. At most 40 notebooks.',
		input: notebookCreateInput,
		run: (ctx, a) => createNotebook(ctx, a)
	}),
	verb({
		name: 'notebook_update',
		kind: 'free',
		description:
			'Rename another notebook (newTitle) or change its one-line summary. Keep each summary true: it is how you find the notebook later. The main notebook has neither.',
		input: notebookUpdateInput,
		agentOmit: ['notebookId'],
		agentStrict: true,
		run: (ctx, a) => updateNotebook(ctx, a)
	}),
	verb({
		name: 'notebook_delete',
		kind: 'free',
		description:
			'Delete another notebook, named by its title, when the person asks or it is empty and no longer needed. It is hidden and can be restored for 30 days with notebook_undelete. The answer holds the removed notebook. The main notebook cannot be deleted.',
		input: notebookTargetInput,
		agentOmit: ['notebookId'],
		agentStrict: true,
		run: (ctx, a) => deleteNotebook(ctx, a)
	}),
	verb({
		name: 'notebook_undelete',
		kind: 'free',
		description:
			'Put a deleted notebook back, named by its title (see notebook_list with deleted true).',
		input: notebookTargetInput,
		agentOmit: ['notebookId'],
		agentStrict: true,
		run: (ctx, a) => undeleteNotebook(ctx, a)
	}),
	verb({
		name: 'page_create',
		kind: 'free',
		description:
			'Make a new page in one of your notebooks, named by its title (the notebook must exist: file into an existing notebook by default). Give a short unique title and the text in Markdown. Name a top-level page as parent to make a sub-page (one level only). Never put a balance, an account number or anything from the web, a photo or someone else calendar in it. At most 500 pages, and 20 sub-pages under one page.',
		input: pageCreateInput,
		agentOmit: ['notebookId', 'parentPageId'],
		agentStrict: true,
		run: (ctx, a) => createPage(ctx, a)
	}),
	verb({
		name: 'page_edit',
		kind: 'free',
		description:
			'Change a page by exact text, named by its notebook title and page title. op add: heading and line (the heading is made if it is missing). op replace: find (exact text that appears once) and replacement. op remove: find. Read the page with page_get first. To split a long page: page_create the new page with the moved text, then page_edit remove on the old one.',
		input: pageEditInput,
		agentOmit: ['pageId'],
		agentStrict: true,
		run: (ctx, a) => editPage(ctx, a)
	}),
	verb({
		name: 'page_rename',
		kind: 'free',
		description:
			'Give a page another title (newTitle). Titles are unique among the pages that share a parent, ignoring case. Links written as [[Old title]] in other pages are not changed: fix them with page_edit.',
		input: pageRenameInput,
		agentOmit: ['pageId'],
		agentStrict: true,
		run: (ctx, a) => renamePage(ctx, a)
	}),
	verb({
		name: 'page_move',
		kind: 'free',
		description:
			'Move a page: to another notebook (toNotebook), under a top-level page (toParent) or to a place (position, 0 is first). With no toParent the page goes to the top level of its notebook, so to reorder a sub-page name its parent again. A page with sub-pages cannot be put under another page. Nothing is lost.',
		input: pageMoveInput,
		agentOmit: ['pageId', 'toNotebookId', 'toParentPageId'],
		agentStrict: true,
		run: (ctx, a) => movePage(ctx, a)
	}),
	verb({
		name: 'page_merge',
		kind: 'free',
		description:
			'Merge pages into one: name the target page (notebook and page) and the pages to merge into it (sources: page titles, with notebook when it is another one). Each source text is added at the end of the target under a heading with its title, the target keeps its old text as a revision, and the sources are deleted (restorable for 30 days). A source with sub-pages is refused. It counts as one delete.',
		input: pageMergeInput,
		agentOmit: ['pageId', 'sourceIds'],
		agentStrict: true,
		run: (ctx, a) => mergePages(ctx, a)
	}),
	verb({
		name: 'page_delete',
		kind: 'free',
		description:
			'Delete a page with its sub-pages when the person asks, or when it is empty and no longer needed; never to make room. They are hidden and can be restored for 30 days with page_undelete. The answer holds the removed page.',
		input: pageTargetInput,
		agentOmit: ['pageId'],
		agentStrict: true,
		run: (ctx, a) => deletePage(ctx, a)
	}),
	verb({
		name: 'page_undelete',
		kind: 'free',
		description:
			'Put a deleted page back (with the sub-pages deleted with it), named by its notebook and page title (see notebook_outline with deleted true). It returns to its old parent, or to the top level.',
		input: pageUndeleteInput,
		agentOmit: ['pageId'],
		agentStrict: true,
		run: (ctx, a) => undeletePage(ctx, a)
	}),
	verb({
		name: 'memory_remember',
		agent: false,
		kind: 'free',
		description: 'Remember a lasting fact the person asked you to remember.',
		input: memoryRememberInput,
		run: (ctx, a) => rememberFact(ctx, a)
	}),
	verb({
		name: 'memory_edit',
		agent: false,
		kind: 'free',
		description: 'Change the words of a remembered fact. The old words are kept as history.',
		input: memoryEditInput,
		run: (ctx, a) => editFact(ctx, a)
	}),
	verb({
		name: 'memory_forget',
		agent: false,
		kind: 'free',
		description: 'Forget a remembered fact for good, when the person asks.',
		input: memoryFactIdInput,
		run: (ctx, a) => forgetFact(ctx, a)
	}),
	verb({
		name: 'memory_resolve',
		agent: false,
		kind: 'free',
		description:
			'Settle two facts that disagree: keep the new one or the old one, as the person chooses.',
		input: memoryResolveInput,
		run: (ctx, a) => resolveConflict(ctx, a)
	}),
	verb({
		name: 'profile_set',
		agent: false,
		kind: 'free',
		description: 'Set how you talk, the about lines, or the private names, when the person asks.',
		input: profileSetInput,
		run: (ctx, a) => setProfile(ctx, a)
	}),
	verb({
		name: 'expense_log',
		kind: 'free',
		description: 'Log an expense with an amount in centavos on an account.',
		input: expenseLogInput,
		run: (ctx, a) => logExpense(ctx, a)
	}),
	verb({
		name: 'expense_from_text',
		kind: 'free',
		description: 'Log an expense said in plain words, like "lunch 180 gcash".',
		input: expenseFromTextInput,
		run: (ctx, a) => logExpenseFromText(ctx, a)
	}),
	verb({
		name: 'income_record',
		kind: 'free',
		description: 'Record money that arrived in an account.',
		input: incomeRecordInput,
		run: (ctx, a) => recordIncome(ctx, a)
	}),
	verb({
		name: 'refund_record',
		kind: 'free',
		description: 'Record money that came back from a purchase.',
		input: incomeRecordInput,
		run: (ctx, a) => recordRefund(ctx, a)
	}),
	verb({
		name: 'transfer_record',
		kind: 'free',
		description: 'Record a move between two of the accounts. Never spending.',
		input: transferRecordInput,
		run: (ctx, a) => recordTransfer(ctx, a)
	}),
	verb({
		name: 'undo',
		kind: 'free',
		description: 'Undo a recent entry by its journal id.',
		input: undoInput,
		run: (ctx, a) => undo(ctx, a)
	}),
	verb({
		name: 'rule_propose',
		kind: 'free',
		description:
			'Propose an allocation rule. It applies only after the person approves it. fundsBillId links a fixed rule to the bill it saves for (the bill must be paid from the account the rule fills): the split then pays that bill from what the rule set aside instead of from the pay again.',
		input: ruleProposeInput,
		run: (ctx, a) => proposeRule(ctx, a)
	}),
	verb({
		name: 'rule_from_text',
		kind: 'free',
		description:
			'Propose a rule said in plain words, like "20% to savings". The person approves it.',
		input: ruleFromTextInput,
		run: (ctx, a) => proposeRuleFromText(ctx, a)
	}),
	verb({
		name: 'split_propose',
		kind: 'free',
		description: 'Propose the split for a payday. The person approves it.',
		input: splitProposeInput,
		run: (ctx, a) => proposeSplitPlan(ctx, a)
	}),
	verb({
		name: 'split_mark_sent',
		kind: 'free',
		description: 'Record that one transfer of an approved split was made.',
		input: splitSentInput,
		run: (ctx, a) => markTransferSent(ctx, a)
	}),
	verb({
		name: 'bill_mark_paid',
		kind: 'free',
		description:
			'Mark one due date of a bill paid. For a bill whose amount varies this moves its usual amount, so it needs approval.',
		input: billMarkPaidInput,
		run: (ctx, a) => markBillPaid(ctx, a),
		// A payment on a bill whose amount varies moves its usual amount, so it is a card; opening a wallet is not
		gatedWhen: (ctx, a) =>
			run(ctx, async (tx, userId) => {
				try {
					return (await requireBill(tx, userId, a.billId)).kind === 'variable';
				} catch (e) {
					if (e instanceof OpsError && e.code === 'NOT_FOUND') return false;
					throw e;
				}
			})
	}),
	verb({
		name: 'account_update',
		kind: 'free',
		description:
			'Change an account: its name, kind, minimum balance, order or purpose label (what it is for, up to 24 characters, for example Emergency, Savings, Daily spending, Bills, Travel; send purpose null to clear it). Mark it with icon (a built-in key: bank, wallet, cash, card, piggy, savings, home, rent, bolt, water, wifi, phone, cart, food, fuel, car, bus, health, school, family, gift, travel, shopping, subscription, tv, game, insurance, tax, loan, invest, crypto, work, pet, baby, tools, gym, coffee, heart, star, flag); icon null clears it and clearImage true removes the picture the person added. A picture can only be added by the person in the app. An icon replaces a picture. Done at once, no card. Never changes what the account holds: for that use snapshot_record.',
		input: accountUpdateInput,
		agentOmit: ['imageData'],
		agentStrict: true,
		run: (ctx, a) => updateAccount(ctx, a)
	}),
	verb({
		name: 'income_update',
		kind: 'free',
		description:
			'Change a payday schedule: label, expected amount, the account it lands in, the repeat rule, the weekend rule, or switch it off with active false. Done at once, no card. The repeat rule is replaced whole: read it with income_list first and send all of it. To skip one payday add its date to skipDates inside the schedule (for example one Monday that the pay already arrived early); to start later or stop use startsOn and endsOn; resend the ones you want to keep and leave out the ones to clear. Only paydays take these fields, not bills or reminders. Try an idea with schedule_preview first, never on the live payday.',
		input: incomeUpdateInput,
		run: (ctx, a) => updateIncome(ctx, a)
	}),
	verb({
		name: 'bill_update',
		kind: 'free',
		description:
			'Change a bill for ALL its dates: name, category, amount, the account it is paid from (accountId), the repeat rule, the weekend rule, or switch it off with active false. Only send the fields that change. Done at once, no card. The schedule is a whole rule, see schedule_preview for its fields. A new schedule, weekend rule, amount or account also drops the changes made to single dates from today on (clearedOverrides says how many). To change just ONE date, use bill_occurrence_update. Mark the bill with icon (a built-in key: bank, wallet, cash, card, piggy, savings, home, rent, bolt, water, wifi, phone, cart, food, fuel, car, bus, health, school, family, gift, travel, shopping, subscription, tv, game, insurance, tax, loan, invest, crypto, work, pet, baby, tools, gym, coffee, heart, star, flag); icon null clears it and clearImage true removes the picture the person added. A picture can only be added by the person in the app. An icon replaces a picture.',
		input: billUpdateInput,
		agentOmit: ['imageData'],
		agentStrict: true,
		run: (ctx, a) => updateBill(ctx, a)
	}),
	verb({
		name: 'bill_occurrence_update',
		kind: 'free',
		description:
			'Change just ONE due date of a bill and leave its other dates alone: move it to another day (newDueDate, up to 31 days either way), give it another amount or paying account (accountId), or skip it (skipped true). dueDate is the date it has now, taken from bills_due. Only send the fields that change; null clears one. Not for a date already paid. A custom amount on a bill whose amount varies needs a card; the rest is done at once.',
		input: billOccurrenceUpdateInput,
		run: (ctx, a) => updateBillOccurrence(ctx, a),
		gatedWhen: async (ctx, a) =>
			a.amount == null
				? false
				: run(ctx, async (tx, userId) => {
						try {
							return (await requireBill(tx, userId, a.billId)).kind === 'variable';
						} catch (e) {
							if (e instanceof OpsError && e.code === 'NOT_FOUND') return false;
							throw e;
						}
					})
	}),
	verb({
		name: 'bill_occurrence_reset',
		kind: 'free',
		description:
			'Put one due date of a bill back to what its schedule says (undo a move, a custom amount, another account or a skip). dueDate is the date it has now or the one the schedule gave. Done at once, no card.',
		input: billOccurrenceResetInput,
		run: (ctx, a) => resetBillOccurrence(ctx, a)
	}),
	verb({
		name: 'goal_update',
		kind: 'free',
		description:
			'Change a savings goal: name, the account it sits in, the target, the amount set aside each payday, or switch it off with active false. Done at once, no card.',
		input: goalUpdateInput,
		run: (ctx, a) => updateGoal(ctx, a)
	}),

	// -- THE MONEY PLAN: ADD, HIDE AND REMOVE (FREE FOR THE ASSISTANT SINCE 2026-10-28) -- //
	verb({
		name: 'account_create',
		kind: 'free',
		description:
			'Add an account. It may carry a purpose label (what it is for, up to 24 characters, for example Emergency, Savings, Daily spending, Bills, Travel). It may carry an icon (a built-in key, see account_update); a picture can only be added by the person in the app.',
		input: accountCreateInput,
		agentOmit: ['imageData'],
		agentStrict: true,
		run: (ctx, a) => createAccount(ctx, a)
	}),
	verb({
		name: 'account_wallet_add',
		kind: 'free',
		description:
			'Add a currency to an account, for example a USD wallet on a Wise or PayPal account that holds several. The account keeps its other currencies.',
		input: walletAddInput,
		run: (ctx, a) => addWallet(ctx, a)
	}),
	verb({
		name: 'account_archive',
		kind: 'free',
		description:
			'Hide an account from lists and new entries. Its history stays. Done at once, no card.',
		input: accountIdInput,
		run: (ctx, a) => archiveAccount(ctx, a)
	}),
	verb({
		name: 'income_create',
		kind: 'free',
		description:
			'Set up a payday schedule. The schedule may carry startsOn, endsOn and skipDates (YYYY-MM-DD) inside it.',
		input: incomeCreateInput,
		run: (ctx, a) => createIncome(ctx, a)
	}),
	verb({
		name: 'bill_create',
		kind: 'free',
		description:
			'Add a bill. A bill that happens one time only uses schedule kind once with its date. A new bill counts from today; set startsOn (YYYY-MM-DD) only when it began earlier and the earlier dates are really unpaid. It may carry an icon (a built-in key, see bill_update); a picture can only be added by the person in the app.',
		input: billCreateInput,
		agentOmit: ['imageData'],
		agentStrict: true,
		run: (ctx, a) => createBill(ctx, a)
	}),
	verb({
		name: 'goal_create',
		kind: 'free',
		description: 'Add a savings goal.',
		input: goalCreateInput,
		run: (ctx, a) => createGoal(ctx, a)
	}),
	verb({
		name: 'goal_delete',
		kind: 'free',
		description:
			'Remove a savings goal for good, with the payday rules that point at it. Done at once, no card. The money saved for it stays where it is. The answer holds the removed goal, so it can be added again. To stop saving for a goal without deleting it, use goal_update with active false. Never forget a memory or change the notebook instead of deleting a goal.',
		input: goalDeleteInput,
		run: (ctx, a) => deleteGoal(ctx, a)
	}),
	verb({
		name: 'bill_delete',
		kind: 'free',
		description:
			'Remove a bill. Done at once, no card. A bill that was ever paid keeps its history and is switched off instead (the answer says switchedOff). The answer holds the removed bill, so it can be added again. Name what you removed.',
		input: billDeleteInput,
		run: (ctx, a) => deleteBill(ctx, a)
	}),
	verb({
		name: 'income_delete',
		kind: 'free',
		description:
			'Remove a payday schedule. Done at once, no card. One that a payday split was made for keeps that history and is switched off instead, unless withSplits is true, which removes its splits (split_delete) and then the payday. The answer holds the removed schedule. Name what you removed.',
		input: incomeDeleteInput,
		run: (ctx, a) => deleteIncome(ctx, a)
	}),
	verb({
		name: 'rule_update',
		kind: 'free',
		description:
			'Give a payday rule a short label saying what it is for (like "Emergency fund"), or link it to the bill it saves for with fundsBillId (a fixed rule into the account the bill is paid from; the split then pays the bill from what the rule set aside). A field left out stays as it is; null clears it. Amounts and targets need a new rule. Answers with the changed rule.',
		input: ruleUpdateInput,
		run: (ctx, a) => updateRule(ctx, a)
	}),
	verb({
		name: 'split_delete',
		kind: 'free',
		description:
			'Remove recorded payday splits for good, whatever their status: one with splitId (read split_list with includeReplaced true first and name it back to the person), or every split with all true (only when the person clearly asked to clear them all; it uses up the delete allowance of the message). Done at once when nothing untrusted was read. The money that really moved stays in the ledger as plain entries; removeEntries true takes the pay and transfers of those splits out of the balances too, changes what the person sees in every account, and always waits for their approval as a card. Bills, rules and paydays are not touched. The answer holds the removed split (the whole row for one) and cannot be undone. Name what you removed.',
		input: splitDeleteInput,
		run: (ctx, a) => deleteSplits(ctx, a)
	}),
	verb({
		name: 'rule_delete',
		kind: 'free',
		description:
			'Remove a payday rule for good, whatever its status. Done at once, no card. The answer holds the removed rule. Name what you removed.',
		input: ruleDeleteInput,
		run: (ctx, a) => deleteRule(ctx, a)
	}),
	verb({
		name: 'account_delete',
		kind: 'free',
		description:
			'Remove an account. Done at once, no card. An account with entries or balance counts keeps everything and is hidden instead (the answer says archived and why). One that a bill, payday, goal or rule still uses is refused with what uses it: move or remove those first. Name what you removed.',
		input: accountDeleteInput,
		run: (ctx, a) => deleteAccount(ctx, a)
	}),
	verb({
		name: 'account_wallet_remove',
		kind: 'free',
		description:
			'Take a currency off an account. Done at once, no card. Only an empty wallet that is not the account own currency; otherwise it is refused with the reason.',
		input: walletRemoveInput,
		run: (ctx, a) => removeWallet(ctx, a)
	}),

	// -- GATED -- //
	verb({
		name: 'snapshot_record',
		kind: 'gated',
		description:
			'Record what an account really holds right now. To reset an account (for example to 0) use mode reset with a short reason: it makes a card for the person to approve and keeps the history. Amounts are in the smallest unit of the currency.',
		input: snapshotRecordInput,
		run: (ctx, a) => recordSnapshot(ctx, a)
	}),
	verb({
		name: 'mark_from_photo',
		kind: 'gated',
		description:
			'Make the picture of an account or a bill from a photo the person sent in THIS message, when they ask to use a photo as its icon or picture. It always becomes a card the person approves in the app: the phone cuts the photo, shows the result and the person can zoom or move it before approving; you never get the picture. Look at the photo first (photo 1 is the first attached picture, and so on; if no picture reaches you, photo n is the n-th photo text; if you cannot see them, use the whole photo: x 0, y 0, width 1, height 1, fit cover, and say you could not see it). Choose the box with x, y, width and height as fractions of the photo (0 to 1, x + width and y + height at most 1): crop tightly on the logo or subject and leave out background, edges and other things; a little breathing room is better than cutting the subject. fit cover (the default) fills the round or square badge from the middle of your box, best for a logo on a plain background, a face or a card; fit contain keeps the whole box inside the badge, best for a wide logo or text that must not be cut. name is the exact name of the account or bill. If the person asks to zoom in, zoom out or shift it, call this again with a new box. Say in one short line what you cropped and why. Only works on a photo from this message; for a built-in icon use account_update or bill_update.',
		input: markFromPhotoInput,
		agentOmit: ['imageData'],
		agentStrict: true,
		run: (ctx, a) => markFromPhoto(ctx, a)
	}),
	verb({
		name: 'mark_from_web',
		kind: 'gated',
		description:
			'Make the picture of an account or a bill from a logo found on the web, when the person asks you to find an icon or logo for it (for example "find an icon for my RCBC account"). It always becomes a card the person approves in the app: their phone downloads the candidates itself, trims and fits them, shows them, and the person picks one and can zoom or move it before approving; you never get the picture. name is the exact name of the account or bill. domain is the site of the organisation, without https:// (rcbc.com): the phone looks for its icon in fixed places, so a correct domain is usually enough. If you are not sure of the domain, use web_search first. urls (at most 4) are optional plain https addresses of logo pictures you found, with no query string. fit contain (the default) keeps the whole logo, cover fills the badge. If the person asks for another logo, call this again with a different domain or addresses. Say in one short line what you looked for. Do not say it is done until they approve.',
		input: markFromWebInput,
		agentOmit: ['imageData'],
		agentStrict: true,
		run: (ctx, a) => markFromWeb(ctx, a)
	}),

	// -- PERSON ONLY -- //
	verb({
		name: 'fx_rates',
		kind: 'person',
		description:
			'The stored exchange rates (units of each currency per US dollar), the date they were fetched, and whether they are stale. For the screens: the assistant converts with fx_convert instead.',
		input: emptyInput,
		run: (ctx) => fxRates(ctx)
	}),
	verb({
		name: 'fx_rates_refresh',
		kind: 'person',
		description:
			'Fetch fresh exchange rates now. Does nothing if rates were fetched in the last ten minutes. A source that fails keeps the stored rates.',
		input: emptyInput,
		run: (ctx) => fxRatesRefresh(ctx)
	}),
	verb({
		name: 'data_reset_preview',
		kind: 'person',
		description: 'Count what a reset would erase and get a confirmation that works once.',
		input: dataResetPreviewInput,
		run: (ctx, a) => previewDataReset(ctx, a)
	}),
	verb({
		name: 'data_reset',
		kind: 'person',
		description: 'Erase a scope of the person own data, after the confirmation and the typed word.',
		input: dataResetInput,
		run: (ctx, a) => resetData(ctx, a)
	}),
	verb({
		name: 'chat_history',
		kind: 'person',
		description:
			'The recent conversation shown when the app opens. Never handed to the assistant, which has its own short bounded history.',
		input: chatHistoryInput,
		run: (ctx, a) => chatHistory(ctx, a)
	}),
	verb({
		name: 'chat_clear',
		kind: 'person',
		description:
			'Old name of chat_new: start a new chat. The earlier conversation stays in the list. Only the person can do this.',
		input: emptyInput,
		run: (ctx) => chatClear(ctx)
	}),
	verb({
		name: 'chat_list',
		kind: 'person',
		description:
			'The list of conversations, newest first, with a search over titles and messages. Never handed to the assistant.',
		input: chatListPageInput,
		run: (ctx, a) => chatList(ctx, a)
	}),
	verb({
		name: 'chat_new',
		kind: 'person',
		description: 'Start a new conversation (an empty newest one is used again).',
		input: emptyInput,
		run: (ctx) => chatNew(ctx)
	}),
	verb({
		name: 'chat_open',
		kind: 'person',
		description:
			'Open a conversation: it becomes the one that opens next, and returns from the archive.',
		input: chatIdInput,
		run: (ctx, a) => chatOpen(ctx, a)
	}),
	verb({
		name: 'chat_rename',
		kind: 'person',
		description: 'Give a conversation a name of the person own choosing.',
		input: chatRenameInput,
		run: (ctx, a) => chatRename(ctx, a)
	}),
	verb({
		name: 'chat_pin',
		kind: 'person',
		description: 'Pin or unpin a conversation.',
		input: chatPinInput,
		run: (ctx, a) => chatPin(ctx, a)
	}),
	verb({
		name: 'chat_archive',
		kind: 'person',
		description: 'Archive or restore a conversation. Nothing is deleted.',
		input: chatArchiveInput,
		run: (ctx, a) => chatArchive(ctx, a)
	}),
	verb({
		name: 'chat_fork',
		kind: 'person',
		description:
			'Branch a conversation from a message into a new one. The original stays as it was.',
		input: chatForkInput,
		run: (ctx, a) => chatFork(ctx, a)
	}),
	verb({
		name: 'chat_rewind',
		kind: 'person',
		description:
			'Edit and resend: remove a message and everything after it from the same conversation, so the new words can be sent in its place.',
		input: chatRewindInput,
		run: (ctx, a) => chatRewind(ctx, a)
	}),
	verb({
		name: 'audit_export',
		kind: 'person',
		description:
			'Export the trail as a CSV or JSON text. A bulk export is never handed to the assistant.',
		input: auditExportInput,
		run: (ctx, a) => exportAudit(ctx, a)
	}),
	verb({
		name: 'settings_set',
		kind: 'person',
		description: 'Change the currency, the languages or the first day of the week.',
		input: settingsSetInput,
		run: (ctx, a) => setSettings(ctx, a)
	}),
	verb({
		name: 'rule_approve',
		kind: 'person',
		description: 'Put a proposed rule in force.',
		input: ruleIdInput,
		run: (ctx, a) => approveRule(ctx, a)
	}),
	verb({
		name: 'rule_retire',
		kind: 'person',
		description: 'Take a rule out of force.',
		input: ruleIdInput,
		run: (ctx, a) => retireRule(ctx, a)
	}),
	verb({
		name: 'notebook_save',
		kind: 'person',
		description: 'Save the whole text of the notebook, from the version that was opened.',
		input: notebookSaveInput,
		run: (ctx, a) => saveNotebook(ctx, a)
	}),
	verb({
		name: 'notebook_restore',
		kind: 'person',
		description: 'Put an earlier text of the notebook back.',
		input: notebookRestoreInput,
		run: (ctx, a) => restoreRevision(ctx, a)
	}),
	verb({
		name: 'page_save',
		kind: 'person',
		description: 'Save the whole text of a page, from the version that was opened.',
		input: pageSaveInput,
		run: (ctx, a) => savePage(ctx, a)
	}),
	verb({
		name: 'page_restore',
		kind: 'person',
		description: 'Put an earlier text of a page back.',
		input: pageRevisionInput,
		run: (ctx, a) => restorePage(ctx, a)
	}),
	verb({
		name: 'page_pin',
		kind: 'person',
		description: 'Pin a page to the top of its notebook, or unpin it.',
		input: pagePinInput,
		run: (ctx, a) => pinPage(ctx, a)
	}),
	verb({
		name: 'notebook_pin',
		kind: 'person',
		description: 'Pin a notebook to the top of the library, or unpin it.',
		input: notebookPinInput,
		run: (ctx, a) => pinNotebook(ctx, a)
	}),
	verb({
		name: 'page_seen',
		kind: 'person',
		description: 'Mark a page as looked at up to a version. Only the seen mark moves.',
		input: pageSeenInput,
		run: (ctx, a) => pageSeen(ctx, a)
	}),
	verb({
		name: 'memory_wipe',
		kind: 'person',
		description: 'Wipe all memory and conversations.',
		input: wipeInput,
		run: (ctx, a) => wipeMemory(ctx, a)
	}),
	verb({
		name: 'memory_export',
		kind: 'person',
		description: 'Export all memory and finance data.',
		input: emptyInput,
		run: (ctx) => exportAll(ctx)
	}),
	verb({
		name: 'split_approve',
		kind: 'person',
		description: 'Approve a proposed payday split.',
		input: splitApproveInput,
		run: (ctx, a) => approveSplit(ctx, a)
	})
];

const BY_NAME = new Map(VERBS.map((v) => [v.name, v]));

export const verbByName = (name: string): Verb | undefined => BY_NAME.get(name);

/** What the assistant may be offered: everything except the person-only verbs. */
export const agentVerbs = (): readonly Verb[] =>
	VERBS.filter((v) => v.kind !== 'person' && v.agent);

/**
 * Runs a verb for the caller in `ctx`. An assistant caller is refused a gated or person-only verb here, before any input is read,
 * and a free verb that is gated for this input (a payment on a variable bill) is refused the same way.
 */
export async function invokeVerb(ctx: Ctx, name: string, raw: unknown): Promise<unknown> {
	const v = BY_NAME.get(name);
	if (!v) throw new OpsError('NOT_FOUND', `There is no such operation: ${name}`);
	if (ctx.actor.kind === 'agent') {
		// A verb that is for the app only is refused here as well, not only left out of the tool list
		if (v.kind === 'gated' || v.kind === 'person' || !v.agent)
			throw new OpsError(
				'FORBIDDEN',
				'The assistant cannot do that on its own. It needs your approval.'
			);
		if (v.gatedWhen && (await v.gatedWhen(ctx, parse(v.input, raw))))
			throw new OpsError(
				'FORBIDDEN',
				'The assistant cannot do that on its own. It needs your approval.'
			);
	}
	return v.run(ctx, raw);
}
