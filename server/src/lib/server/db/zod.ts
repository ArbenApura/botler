// ZOD SCHEMAS GENERATED FROM THE DRIZZLE TABLES (drizzle-zod), SHARED BY THE API, THE AGENT TOOL INPUTS AND THE FORMS
// Refinements add the rules a column type cannot hold. user_id is never part of an input schema: the caller is injected server side.

// -- DEP-MODULES -- //
import { createInsertSchema } from 'drizzle-zod';
import { z } from 'zod';
// -- MODULES -- //
import { isDate } from '../../finance/dates';
import { validateRecurrence } from '../../schedule/recurrence';
import { MAX_CENTAVOS } from '../../finance/money';
import { validateSchedule } from '../../finance/schedule';
import {
	account,
	allocationRule,
	bill,
	device,
	FACT_KINDS,
	goal,
	incomeSchedule,
	ledgerTxn
} from './schema';

// -- CONSTANTS -- //

const PLATFORMS = ['android', 'ios', 'web'] as const;

// -- DEVICES -- //

/** Input of the device register verb. The id, the owner and the stamps are set by the server. */
export const deviceRegisterInput = createInsertSchema(device, {
	platform: z.enum(PLATFORMS),
	pushToken: z.string().min(10).max(4096),
	label: z.string().trim().min(1).max(80)
}).pick({ platform: true, pushToken: true, label: true });

/** Input of the device unregister verb. */
export const deviceUnregisterInput = z.object({ deviceId: z.uuid() });

export type DeviceRegisterInput = z.infer<typeof deviceRegisterInput>;
export type DeviceUnregisterInput = z.infer<typeof deviceUnregisterInput>;

// -- FINANCE FIELDS -- //

/** An amount above zero in centavos. */
const amountField = z.number().int().min(1).max(MAX_CENTAVOS);
const dayField = z.string().refine(isDate, 'Use a real date written YYYY-MM-DD');
const idField = z.uuid();
const nameField = z.string().trim().min(1).max(60);
const noteField = z.string().trim().max(200);
const versionField = z.number().int().min(1);
/** An instant as ISO text, for example 2026-10-21T04:00:00Z. */
const instantField = z.iso.datetime({ offset: true });

/** A repeat rule, checked the same way the engine checks it. */
export const scheduleInput = z
	.discriminatedUnion('kind', [
		z.object({
			kind: z.literal('semi_monthly'),
			days: z.tuple([z.number().int(), z.number().int()])
		}),
		z.object({ kind: z.literal('every_n_days'), anchor: z.string(), n: z.number().int() }),
		z.object({ kind: z.literal('monthly'), day: z.number().int() })
	])
	.superRefine((s, ctx) => {
		const problem = validateSchedule(s);
		if (problem) ctx.addIssue({ code: 'custom', message: problem });
	});

// -- ACCOUNTS -- //

export const accountCreateInput = createInsertSchema(account, {
	name: nameField,
	// Left out, the column's own default (zero) applies. A zod default here would reset the field on every update
	minBalance: z.number().int().min(0).max(MAX_CENTAVOS).optional()
}).pick({ name: true, kind: true, minBalance: true, sortOrder: true });

export const accountUpdateInput = accountCreateInput.partial().extend({
	accountId: idField,
	expectVersion: versionField.optional()
});

export const accountIdInput = z.object({ accountId: idField });

// -- INCOME -- //

export const incomeCreateInput = createInsertSchema(incomeSchedule, {
	label: nameField,
	accountId: idField,
	expectedAmount: amountField.nullable().optional(),
	schedule: scheduleInput
}).pick({
	label: true,
	accountId: true,
	expectedAmount: true,
	schedule: true,
	weekendRule: true
});

export const incomeUpdateInput = incomeCreateInput.partial().extend({
	incomeId: idField,
	active: z.boolean().optional(),
	expectVersion: versionField.optional()
});

// -- BILLS -- //

export const billCreateInput = createInsertSchema(bill, {
	name: nameField,
	category: z.string().trim().min(1).max(40),
	accountId: idField,
	amount: amountField.nullable().optional(),
	schedule: scheduleInput
}).pick({
	name: true,
	category: true,
	accountId: true,
	kind: true,
	amount: true,
	schedule: true,
	weekendRule: true,
	deferrable: true
});

export const billUpdateInput = billCreateInput.partial().extend({
	billId: idField,
	active: z.boolean().optional(),
	expectVersion: versionField.optional()
});

export const billMarkPaidInput = z.object({
	billId: idField,
	dueDate: dayField,
	/** What was really paid. Defaults to the bill's amount or its estimate. */
	amount: amountField.optional(),
	/** Pay from another account than the bill's own. */
	accountId: idField.optional()
});

export const billIdInput = z.object({ billId: idField });

// -- GOALS -- //

export const goalCreateInput = createInsertSchema(goal, {
	name: nameField,
	accountId: idField,
	targetAmount: amountField.nullable().optional(),
	perPayday: z.number().int().min(0).max(MAX_CENTAVOS).optional()
}).pick({ name: true, accountId: true, targetAmount: true, perPayday: true });

export const goalUpdateInput = goalCreateInput.partial().extend({
	goalId: idField,
	active: z.boolean().optional(),
	expectVersion: versionField.optional()
});

// -- ALLOCATION RULES -- //

export const ruleProposeInput = createInsertSchema(allocationRule, {
	amount: amountField.nullable(),
	basisPoints: z.number().int().min(1).max(10_000).nullable(),
	targetAccountId: idField.nullable(),
	targetGoalId: idField.nullable(),
	effectiveFrom: dayField,
	position: z.number().int().min(1).max(999)
})
	.pick({
		mode: true,
		amount: true,
		basisPoints: true,
		base: true,
		targetAccountId: true,
		targetGoalId: true,
		effectiveFrom: true,
		position: true
	})
	.partial({
		amount: true,
		basisPoints: true,
		base: true,
		targetAccountId: true,
		targetGoalId: true,
		effectiveFrom: true,
		position: true
	});

export const ruleFromTextInput = z.object({
	text: z.string().trim().min(3).max(200),
	effectiveFrom: dayField.optional(),
	position: z.number().int().min(1).max(999).optional()
});

export const ruleIdInput = z.object({ ruleId: idField });

// -- LEDGER -- //

const ledgerBase = createInsertSchema(ledgerTxn, {
	accountId: idField,
	amount: amountField,
	note: noteField,
	category: z.string().trim().min(1).max(40).nullable()
});

export const expenseLogInput = ledgerBase
	.pick({ accountId: true, amount: true, note: true, category: true, billId: true })
	.partial({ note: true, category: true, billId: true })
	.extend({
		source: z.enum(['manual', 'chat', 'ocr', 'screenshot']).optional(),
		occurredAt: instantField.optional(),
		/** The person saw the amount and said yes. Required when it was read from a picture. */
		confirmed: z.boolean().optional()
	});

export const expenseFromTextInput = z.object({
	text: z.string().trim().min(1).max(300),
	/** Used when the text names no account. */
	accountId: idField.optional(),
	confirmed: z.boolean().optional()
});

export const incomeRecordInput = z.object({
	accountId: idField,
	amount: amountField,
	note: noteField.optional(),
	occurredAt: instantField.optional()
});

export const refundRecordInput = incomeRecordInput;

export const transferRecordInput = z.object({
	fromAccountId: idField,
	toAccountId: idField,
	amount: amountField,
	fee: z.number().int().min(0).max(MAX_CENTAVOS).optional(),
	note: noteField.optional(),
	occurredAt: instantField.optional()
});

export const snapshotRecordInput = z.object({
	accountId: idField,
	/** What the account holds right now. A credit balance may be negative. */
	amount: z.number().int().min(-MAX_CENTAVOS).max(MAX_CENTAVOS),
	takenAt: instantField.optional(),
	source: z.enum(['manual', 'chat', 'ocr', 'screenshot']).optional(),
	confirmed: z.boolean().optional(),
	/** A second yes for a count that is ten times more or less than the last one. */
	acknowledgeLarge: z.boolean().optional()
});

export const undoInput = z.object({ journalId: idField });

/** Verbs that take nothing. */
export const emptyInput = z.object({});

export const dueRangeInput = z.object({ from: dayField, to: dayField });

export const paydaysInput = z.object({
	incomeId: idField,
	count: z.number().int().min(1).max(24).optional()
});

export const txnListInput = z.object({
	from: dayField.optional(),
	to: dayField.optional(),
	accountId: idField.optional(),
	limit: z.number().int().min(1).max(200).optional()
});

export const rulesListInput = z.object({
	status: z.enum(['proposed', 'active', 'retired']).optional()
});

export const limitInput = z.object({ limit: z.number().int().min(1).max(50).optional() });

export const rangeInput = z.object({ from: dayField, to: dayField });

// -- SCHEDULING -- //

/** A repeat with a clock time, checked the same way the engine checks it. */
export const recurrenceInput = z
	.discriminatedUnion('freq', [
		z.object({ freq: z.literal('daily'), time: z.string() }),
		z.object({
			freq: z.literal('weekly'),
			days: z.array(z.number().int()).min(1).max(7),
			time: z.string()
		}),
		z.object({ freq: z.literal('monthly'), day: z.number().int(), time: z.string() }),
		z.object({
			freq: z.literal('every_n_days'),
			anchor: z.string().refine(isDate, 'Use a real date'),
			n: z.number().int(),
			time: z.string()
		})
	])
	.superRefine((r, ctx) => {
		const problem = validateRecurrence(r);
		if (problem) ctx.addIssue({ code: 'custom', message: problem });
	});

const titleField = z.string().trim().min(1).max(200);
const longNote = z.string().trim().max(2000);

export const taskCreateInput = z.object({
	title: titleField,
	notes: longNote.optional(),
	dueAt: instantField.optional(),
	followUpAt: instantField.optional(),
	priority: z.number().int().min(1).max(3).optional()
});

export const taskUpdateInput = z.object({
	taskId: idField,
	title: titleField.optional(),
	notes: longNote.optional(),
	dueAt: instantField.nullable().optional(),
	followUpAt: instantField.nullable().optional(),
	priority: z.number().int().min(1).max(3).optional(),
	status: z.enum(['open', 'done', 'dropped']).optional(),
	expectVersion: versionField.optional()
});

export const taskIdInput = z.object({ taskId: idField });

export const taskListInput = z.object({
	status: z.enum(['open', 'done', 'dropped']).optional(),
	limit: z.number().int().min(1).max(200).optional()
});

export const eventCreateInput = z.object({
	title: z.string().trim().min(1).max(300),
	startsAt: instantField,
	/** Defaults to an hour after the start, or the end of the day for an all-day event. */
	endsAt: instantField.optional(),
	allDay: z.boolean().optional(),
	location: z.string().trim().max(300).optional(),
	notes: z.string().trim().max(4000).optional()
});

export const eventUpdateInput = eventCreateInput
	.partial()
	.extend({ eventId: idField, expectVersion: versionField.optional() });

export const eventIdInput = z.object({ eventId: idField });

export const eventListInput = z.object({ from: dayField, to: dayField });

export const routineCreateInput = z.object({
	title: titleField,
	recurrence: recurrenceInput,
	leadMinutes: z.number().int().min(0).max(1440).optional()
});

export const routineUpdateInput = routineCreateInput.partial().extend({
	routineId: idField,
	active: z.boolean().optional(),
	expectVersion: versionField.optional()
});

export const routineIdInput = z.object({ routineId: idField });

export const reminderCreateInput = z.object({ title: titleField, at: instantField });

export const timerCreateInput = z.object({
	minutes: z.number().int().min(1).max(1440),
	title: titleField.optional()
});

export const reminderIdInput = z.object({ reminderId: idField });

export const syncInput = z.object({ cursor: z.string().max(80).optional() });

// -- MEMORY -- //

export const memoryRememberInput = z.object({
	text: z.string().trim().min(1).max(400),
	kind: z.enum(FACT_KINDS).optional(),
	importance: z.number().int().min(1).max(5).optional(),
	/** What the fact is about in a few words. A newer fact on the same subject ends this one. */
	subject: z.string().trim().max(60).optional()
});

export const memoryEditInput = z.object({
	factId: idField,
	text: z.string().trim().min(1).max(400)
});

export const memoryFactIdInput = z.object({ factId: idField });

export const memoryResolveInput = z.object({ factId: idField, keep: z.enum(['new', 'old']) });

export const memoryListInput = z.object({
	limit: z.number().int().min(1).max(200).optional(),
	/** Include facts that were replaced, as history. */
	history: z.boolean().optional(),
	/** Only the facts waiting for the person to choose. */
	pending: z.boolean().optional()
});

export const memorySearchInput = z.object({
	query: z.string().trim().min(1).max(200),
	limit: z.number().int().min(1).max(50).optional()
});

export const profileSetInput = z.object({
	persona: z.string().trim().max(2000).optional(),
	about: z.string().trim().max(2000).optional(),
	/** Names of family and contacts to keep out of what the model sees. */
	people: z.array(z.string().trim().min(1).max(60)).max(50).optional()
});

export const wipeInput = z.object({ confirm: z.literal(true) });

// -- SPLITS -- //

export const splitProposeInput = z.object({
	incomeScheduleId: idField,
	/** The payday to plan for. Defaults to the next one. */
	payday: dayField.optional(),
	/** The pay on the day, when it differs from what is usual. */
	pay: amountField.optional()
});

export const splitIdInput = z.object({ splitId: idField });

export const splitApproveInput = z.object({
	splitId: idField,
	/** Write the pay into the ledger too. Defaults to yes once the payday has come, and to no before it. */
	recordIncome: z.boolean().optional()
});

export const splitSentInput = z.object({
	splitId: idField,
	index: z.number().int().min(0).max(50)
});

export type AccountCreateInput = z.infer<typeof accountCreateInput>;
export type AccountUpdateInput = z.infer<typeof accountUpdateInput>;
export type IncomeCreateInput = z.infer<typeof incomeCreateInput>;
export type IncomeUpdateInput = z.infer<typeof incomeUpdateInput>;
export type BillCreateInput = z.infer<typeof billCreateInput>;
export type BillUpdateInput = z.infer<typeof billUpdateInput>;
export type BillMarkPaidInput = z.infer<typeof billMarkPaidInput>;
export type GoalCreateInput = z.infer<typeof goalCreateInput>;
export type GoalUpdateInput = z.infer<typeof goalUpdateInput>;
export type RuleProposeInput = z.infer<typeof ruleProposeInput>;
export type RuleFromTextInput = z.infer<typeof ruleFromTextInput>;
export type ExpenseLogInput = z.infer<typeof expenseLogInput>;
export type ExpenseFromTextInput = z.infer<typeof expenseFromTextInput>;
export type IncomeRecordInput = z.infer<typeof incomeRecordInput>;
export type TransferRecordInput = z.infer<typeof transferRecordInput>;
export type SnapshotRecordInput = z.infer<typeof snapshotRecordInput>;
export type SplitProposeInput = z.infer<typeof splitProposeInput>;
