// THE VERB REGISTRY: EVERY OPERATION THE APP, THE API AND THE ASSISTANT CAN RUN, EACH CLASSIFIED ONCE.
// - read:   returns data, changes nothing.
// - free:   records something (an expense, a transfer, a proposal) or edits what the person already set up (an account, a bill, a goal, a
//           payday: name, amount, linked account). The assistant runs it on its own; the audit trail names the assistant as the actor.
// - gated:  adds to or removes from the money plan (a new account, bill, goal or payday, hiding an account) or counts a balance. The assistant can only ask: it becomes an approval
//           card and runs, as the person, after they approve. The ops verb itself also refuses an assistant caller.
// - person: approving or retiring. Never offered to the assistant at all.
// Inputs are strict objects: a key that is not in the schema (a forged user_id, say) is refused, and the caller is never read from input.

// -- TYPES -- //
import type { z } from 'zod';
import type { Ctx } from './context';
// -- MODULES -- //
import {
	accountCreateInput,
	accountIdInput,
	calcInput,
	cashflowForecastInput,
	accountUpdateInput,
	fxConvertInput,
	walletAddInput,
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
	notebookEditInput,
	notebookRestoreInput,
	notebookSaveInput,
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
	chatHistoryInput,
	chatIdInput,
	chatListInput,
	chatPinInput,
	chatRenameInput,
	calendarRangeInput,
	dataResetInput,
	dataResetPreviewInput,
	profileSetInput,
	rangeInput,
	ruleFromTextInput,
	ruleIdInput,
	ruleProposeInput,
	rulesListInput,
	snapshotRecordInput,
	splitApproveInput,
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
	chatList,
	chatNew,
	chatOpen,
	chatPin,
	chatRename
} from './chats';
import { calendarRange } from './calendarRange';
import { previewDataReset, resetData } from './dataReset';
import { assetsSummary } from './assets';
import { runCalc } from './calc';
import { cashflowForecast } from './forecast';
import { billPayOpensWallet, opensWallet, textOpensWallet } from './gates';
import { fxConvert, fxRates, fxRatesRefresh } from './fx';
import { getSettings, setSettings } from './settings';
import { addWallet, archiveAccount, createAccount, listAccounts, updateAccount } from './accounts';
import {
	createBill,
	listBills,
	listDueBills,
	markBillPaid,
	resetBillOccurrence,
	updateBill,
	updateBillOccurrence
} from './bills';
import { OpsError, run } from './context';
import {
	accountBalances,
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
	editNotebook,
	getNotebook,
	listRevisions,
	restoreRevision,
	saveNotebook
} from './notebook';
import { approveRule, listRules, proposeRule, proposeRuleFromText, retireRule } from './rules';
import { parse, requireBill } from './shared';
import {
	approveSplit,
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
}): Verb {
	const strict = v.input.strict();
	return {
		name: v.name,
		description: v.description,
		kind: v.kind,
		taints: v.taints ?? false,
		agent: v.agent ?? true,
		input: strict,
		run: (ctx, raw) => v.run(ctx, parse(strict, raw) as z.infer<S>),
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
		name: 'accounts_list',
		kind: 'read',
		description: 'List the accounts (RCBC, GCash, Maya, cash ...).',
		input: emptyInput,
		run: (ctx) => listAccounts(ctx)
	}),
	verb({
		name: 'accounts_balances',
		kind: 'read',
		description: 'The balance of every account right now.',
		input: emptyInput,
		run: (ctx) => accountBalances(ctx)
	}),
	verb({
		name: 'assets_summary',
		kind: 'read',
		description:
			'The total of everything the person owns, in their main currency: every currency wallet of every account with its balance, its value in the main currency, the rate used and the date of the rates. A currency with no known rate is listed as missing and left out of the total. Use this for "how much do I have in total".',
		input: emptyInput,
		run: (ctx) => assetsSummary(ctx)
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
			'Say what a repeat schedule means and when it falls next, before it is saved. Schedule kinds: monthly (day, or -1 for the last day), semi_monthly, every_n_days, weekly (days, and for every few weeks everyWeeks plus anchor, a YYYY-MM-DD date that falls on one of those weekdays), nth_weekday (n 1-5 or -1, weekday 0 Sunday to 6 Saturday), week_of_month (n, basis days or calendar, pick window or weekday), day_range (from, to), yearly, once (date, a YYYY-MM-DD, for a bill that happens one time only). Add everyMonths and anchorMonth (YYYY-MM) for every few months. Every field of the rule, anchor included, goes inside the "schedule" object, never beside it. Example every other Wednesday: {"schedule":{"kind":"weekly","days":[3],"everyWeeks":2,"anchor":"2026-10-28"}}.',
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
		description: 'Recent payday splits.',
		input: limitInput,
		run: (ctx, a) => listSplits(ctx, a.limit)
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
			'What the accounts will hold from today to a date (at most 366 days), worked out by the server: the balance now of every wallet, the paydays, the unpaid bills by due date (with any date, amount or account changed for one date), and the payday moves of the approved rules. Group by day (up to 62 days), week or month. Each period gives its start and end totals in the main currency, every payment in, out and moved with its date, the wallets that changed, and the end balance of each account; warnings say when a wallet goes below zero. Wallets of other currencies are converted at the stored rates and one with no rate is named and left out. Use this, never bills_due added by hand, for "how much will I have by ..." and for week by week tallies, and quote its numbers as they are. Read its notes before quoting a total.',
		input: cashflowForecastInput,
		run: (ctx, a) => cashflowForecast(ctx, a)
	}),
	verb({
		name: 'notebook_get',
		kind: 'read',
		agent: false,
		description: 'The notebook: the text, its version and who wrote it last.',
		input: emptyInput,
		run: (ctx) => getNotebook(ctx)
	}),
	verb({
		name: 'notebook_revisions',
		kind: 'read',
		agent: false,
		description: 'The changes made to the notebook, newest first.',
		input: emptyInput,
		run: (ctx) => listRevisions(ctx)
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
			'Change your notebook, the notes you keep about the person that you read before every answer. Write a lasting preference, a rule, a person or an ongoing plan here as soon as the person says it or asks you to remember it. op add: heading and line (one short sentence; the heading is made if it is missing). op replace: find (exact text that appears once) and replacement. op remove: find. Never put a balance, an account number or anything one-off in it. It applies from the next message.',
		input: notebookEditInput,
		run: (ctx, a) => editNotebook(ctx, a)
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
		run: (ctx, a) => logExpense(ctx, a),
		// An entry in a currency the account does not hold yet would open a wallet: a card the person approves
		gatedWhen: (ctx, a) => opensWallet(ctx, a.accountId, a.currency)
	}),
	verb({
		name: 'expense_from_text',
		kind: 'free',
		description: 'Log an expense said in plain words, like "lunch 180 gcash".',
		input: expenseFromTextInput,
		run: (ctx, a) => logExpenseFromText(ctx, a),
		gatedWhen: (ctx, a) => textOpensWallet(ctx, a.text, a.accountId)
	}),
	verb({
		name: 'income_record',
		kind: 'free',
		description: 'Record money that arrived in an account.',
		input: incomeRecordInput,
		run: (ctx, a) => recordIncome(ctx, a),
		gatedWhen: (ctx, a) => opensWallet(ctx, a.accountId, a.currency)
	}),
	verb({
		name: 'refund_record',
		kind: 'free',
		description: 'Record money that came back from a purchase.',
		input: incomeRecordInput,
		run: (ctx, a) => recordRefund(ctx, a),
		gatedWhen: (ctx, a) => opensWallet(ctx, a.accountId, a.currency)
	}),
	verb({
		name: 'transfer_record',
		kind: 'free',
		description: 'Record a move between two of the accounts. Never spending.',
		input: transferRecordInput,
		run: (ctx, a) => recordTransfer(ctx, a),
		// Either side landing in a currency its account does not hold yet opens a wallet
		gatedWhen: async (ctx, a) =>
			(await opensWallet(ctx, a.fromAccountId, a.currency)) ||
			(await opensWallet(ctx, a.toAccountId, a.toCurrency))
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
		description: 'Propose an allocation rule. It applies only after the person approves it.',
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
		gatedWhen: async (ctx, a) =>
			(await run(ctx, async (tx, userId) => {
				try {
					return (await requireBill(tx, userId, a.billId)).kind === 'variable';
				} catch (e) {
					if (e instanceof OpsError && e.code === 'NOT_FOUND') return false;
					throw e;
				}
			})) || (await billPayOpensWallet(ctx, a.billId, a.accountId, a.paidCurrency))
	}),
	verb({
		name: 'account_update',
		kind: 'free',
		description:
			'Change an account: its name, kind, minimum balance, order or purpose label (what it is for, up to 24 characters, for example Emergency, Savings, Daily spending, Bills, Travel; send purpose null to clear it). Done at once, no card. Never changes what the account holds: for that use snapshot_record.',
		input: accountUpdateInput,
		run: (ctx, a) => updateAccount(ctx, a),
		// The currency an account is in is part of the money plan: changing it is a card
		gatedWhen: async (_ctx, a) => a.currency !== undefined
	}),
	verb({
		name: 'income_update',
		kind: 'free',
		description:
			'Change a payday schedule: label, expected amount, the account it lands in, the repeat rule, the weekend rule, or switch it off with active false. Done at once, no card.',
		input: incomeUpdateInput,
		run: (ctx, a) => updateIncome(ctx, a)
	}),
	verb({
		name: 'bill_update',
		kind: 'free',
		description:
			'Change a bill for ALL its dates: name, category, amount, the account it is paid from (accountId), the repeat rule, the weekend rule, or switch it off with active false. Only send the fields that change. Done at once, no card. The schedule is a whole rule, see schedule_preview for its fields. A new schedule, weekend rule, amount or account also drops the changes made to single dates from today on (clearedOverrides says how many). To change just ONE date, use bill_occurrence_update.',
		input: billUpdateInput,
		run: (ctx, a) => updateBill(ctx, a),
		// The currency of a bill changes what the split reserves, so it is a card
		gatedWhen: async (_ctx, a) => a.currency !== undefined
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

	// -- GATED -- //
	verb({
		name: 'account_create',
		kind: 'gated',
		description:
			'Add an account. It may carry a purpose label (what it is for, up to 24 characters, for example Emergency, Savings, Daily spending, Bills, Travel).',
		input: accountCreateInput,
		run: (ctx, a) => createAccount(ctx, a)
	}),
	verb({
		name: 'account_wallet_add',
		kind: 'gated',
		description:
			'Add a currency to an account, for example a USD wallet on a Wise or PayPal account that holds several. The account keeps its other currencies.',
		input: walletAddInput,
		run: (ctx, a) => addWallet(ctx, a)
	}),
	verb({
		name: 'account_archive',
		kind: 'gated',
		description: 'Hide an account.',
		input: accountIdInput,
		run: (ctx, a) => archiveAccount(ctx, a)
	}),
	verb({
		name: 'income_create',
		kind: 'gated',
		description: 'Set up a payday schedule.',
		input: incomeCreateInput,
		run: (ctx, a) => createIncome(ctx, a)
	}),
	verb({
		name: 'bill_create',
		kind: 'gated',
		description:
			'Add a bill. A bill that happens one time only uses schedule kind once with its date. A new bill counts from today; set startsOn (YYYY-MM-DD) only when it began earlier and the earlier dates are really unpaid.',
		input: billCreateInput,
		run: (ctx, a) => createBill(ctx, a)
	}),
	verb({
		name: 'goal_create',
		kind: 'gated',
		description: 'Add a savings goal.',
		input: goalCreateInput,
		run: (ctx, a) => createGoal(ctx, a)
	}),
	verb({
		name: 'goal_delete',
		kind: 'gated',
		description:
			'Remove a savings goal for good, with the payday rules that point at it. It makes a card the person approves. The money saved for it stays where it is. To stop saving for a goal without deleting it, use goal_update with active false. Never forget a memory or change the notebook instead of deleting a goal.',
		input: goalDeleteInput,
		run: (ctx, a) => deleteGoal(ctx, a)
	}),
	verb({
		name: 'snapshot_record',
		kind: 'gated',
		description:
			'Record what an account really holds right now. To reset an account (for example to 0) use mode reset with a short reason: it makes a card for the person to approve and keeps the history. Amounts are in the smallest unit of the currency.',
		input: snapshotRecordInput,
		run: (ctx, a) => recordSnapshot(ctx, a)
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
		input: chatListInput,
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
