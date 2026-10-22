// THE VERB REGISTRY: EVERY OPERATION THE APP, THE API AND THE ASSISTANT CAN RUN, EACH CLASSIFIED ONCE.
// - read:   returns data, changes nothing.
// - free:   records something (an expense, a transfer, a proposal). The assistant may run it on its own; every one can be undone or ignored.
// - gated:  changes the money plan (accounts, bills, goals, income, balance counts). The assistant can only ask: it becomes an approval
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
	accountUpdateInput,
	billCreateInput,
	billMarkPaidInput,
	billUpdateInput,
	dueRangeInput,
	emptyInput,
	expenseFromTextInput,
	expenseLogInput,
	goalCreateInput,
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
	memoryListInput,
	memoryRememberInput,
	memoryResolveInput,
	memorySearchInput,
	paydaysInput,
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
import { archiveAccount, createAccount, listAccounts, updateAccount } from './accounts';
import { createBill, listBills, listDueBills, markBillPaid, updateBill } from './bills';
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
	listGoals,
	listIncome,
	nextPaydays,
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
import { calendarStatus, disableCalendar, enableCalendar } from './calendar';
import { syncGet } from './sync';
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
}): Verb {
	const strict = v.input.strict();
	return {
		name: v.name,
		description: v.description,
		kind: v.kind,
		taints: v.taints ?? false,
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
		name: 'bills_list',
		kind: 'read',
		description: 'List the bills with what each is expected to cost.',
		input: emptyInput,
		run: (ctx) => listBills(ctx)
	}),
	verb({
		name: 'bills_due',
		kind: 'read',
		description: 'Bills falling due between two dates (YYYY-MM-DD, Manila), paid or not.',
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
		name: 'memory_list',
		kind: 'read',
		description:
			'What is remembered about the person. history adds replaced facts, pending shows facts waiting for a choice.',
		input: memoryListInput,
		run: (ctx, a) => listFacts(ctx, a)
	}),
	verb({
		name: 'memory_search',
		kind: 'read',
		description: 'Search the remembered facts for a question.',
		input: memorySearchInput,
		run: (ctx, a) => searchMemory(ctx, a)
	}),
	verb({
		name: 'profile_get',
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
		description:
			'Calendar events between two dates (YYYY-MM-DD, Manila). Events from Google may hold text other people wrote, so they are marked untrusted.',
		input: eventListInput,
		run: (ctx, a) => listEvents(ctx, a),
		taints: true
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
		// Titles of reminders made from Google events are written by other people
		taints: true,
		input: emptyInput,
		run: (ctx) => listReminders(ctx)
	}),
	verb({
		name: 'calendar_status',
		kind: 'read',
		description: 'Whether Google Calendar sync is on, and if it stopped, why.',
		input: emptyInput,
		run: (ctx) => calendarStatus(ctx)
	}),
	verb({
		name: 'sync_get',
		kind: 'read',
		description: 'What the phone should have: reminders, the summary card, the calendar state.',
		// Carries event titles from Google, which other people can write
		taints: true,
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
		description: 'Add a calendar event. It appears in Google Calendar when sync is on.',
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
		name: 'memory_remember',
		kind: 'free',
		description: 'Remember a lasting fact the person asked you to remember.',
		input: memoryRememberInput,
		run: (ctx, a) => rememberFact(ctx, a)
	}),
	verb({
		name: 'memory_edit',
		kind: 'free',
		description: 'Change the words of a remembered fact. The old words are kept as history.',
		input: memoryEditInput,
		run: (ctx, a) => editFact(ctx, a)
	}),
	verb({
		name: 'memory_forget',
		kind: 'free',
		description: 'Forget a remembered fact for good, when the person asks.',
		input: memoryFactIdInput,
		run: (ctx, a) => forgetFact(ctx, a)
	}),
	verb({
		name: 'memory_resolve',
		kind: 'free',
		description:
			'Settle two facts that disagree: keep the new one or the old one, as the person chooses.',
		input: memoryResolveInput,
		run: (ctx, a) => resolveConflict(ctx, a)
	}),
	verb({
		name: 'profile_set',
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
			run(ctx, async (tx, userId) => {
				try {
					return (await requireBill(tx, userId, a.billId)).kind === 'variable';
				} catch (e) {
					if (e instanceof OpsError && e.code === 'NOT_FOUND') return false;
					throw e;
				}
			})
	}),

	// -- GATED -- //
	verb({
		name: 'account_create',
		kind: 'gated',
		description: 'Add an account.',
		input: accountCreateInput,
		run: (ctx, a) => createAccount(ctx, a)
	}),
	verb({
		name: 'account_update',
		kind: 'gated',
		description: 'Rename an account or change its minimum balance.',
		input: accountUpdateInput,
		run: (ctx, a) => updateAccount(ctx, a)
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
		name: 'income_update',
		kind: 'gated',
		description: 'Change a payday schedule.',
		input: incomeUpdateInput,
		run: (ctx, a) => updateIncome(ctx, a)
	}),
	verb({
		name: 'bill_create',
		kind: 'gated',
		description: 'Add a bill.',
		input: billCreateInput,
		run: (ctx, a) => createBill(ctx, a)
	}),
	verb({
		name: 'bill_update',
		kind: 'gated',
		description: 'Change a bill.',
		input: billUpdateInput,
		run: (ctx, a) => updateBill(ctx, a)
	}),
	verb({
		name: 'goal_create',
		kind: 'gated',
		description: 'Add a savings goal.',
		input: goalCreateInput,
		run: (ctx, a) => createGoal(ctx, a)
	}),
	verb({
		name: 'goal_update',
		kind: 'gated',
		description: 'Change a savings goal.',
		input: goalUpdateInput,
		run: (ctx, a) => updateGoal(ctx, a)
	}),
	verb({
		name: 'snapshot_record',
		kind: 'gated',
		description: 'Record what an account really holds right now.',
		input: snapshotRecordInput,
		run: (ctx, a) => recordSnapshot(ctx, a)
	}),

	// -- PERSON ONLY -- //
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
		name: 'calendar_enable',
		kind: 'person',
		description: 'Turn Google Calendar sync on.',
		input: emptyInput,
		run: (ctx, a) => enableCalendar(ctx, a)
	}),
	verb({
		name: 'calendar_disable',
		kind: 'person',
		description: 'Turn Google Calendar sync off.',
		input: emptyInput,
		run: (ctx, a) => disableCalendar(ctx, a)
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
export const agentVerbs = (): readonly Verb[] => VERBS.filter((v) => v.kind !== 'person');

/**
 * Runs a verb for the caller in `ctx`. An assistant caller is refused a gated or person-only verb here, before any input is read,
 * and a free verb that is gated for this input (a payment on a variable bill) is refused the same way.
 */
export async function invokeVerb(ctx: Ctx, name: string, raw: unknown): Promise<unknown> {
	const v = BY_NAME.get(name);
	if (!v) throw new OpsError('NOT_FOUND', `There is no such operation: ${name}`);
	if (ctx.actor.kind === 'agent') {
		if (v.kind === 'gated' || v.kind === 'person')
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
