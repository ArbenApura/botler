// ZOD SCHEMAS GENERATED FROM THE DRIZZLE TABLES (drizzle-zod), SHARED BY THE API, THE AGENT TOOL INPUTS AND THE FORMS
// Refinements add the rules a column type cannot hold. user_id is never part of an input schema: the caller is injected server side.

// -- DEP-MODULES -- //
import { createInsertSchema } from 'drizzle-zod';
import { z } from 'zod';
// -- MODULES -- //
import { CURRENCY_CODES, isCurrencyCode } from '../../finance/currency';
import { isDate } from '../../finance/dates';
import { validateRecurrence } from '../../schedule/recurrence';
import { MAX_CENTAVOS } from '../../finance/money';
import { MAX_SKIP_DATES, validateSchedule, type Schedule } from '../../finance/schedule';
import { ICON_KEYS, PICTURE_MAX_BASE64 } from '../../finance/visual';
import {
	account,
	allocationRule,
	bill,
	billOverride,
	device,
	FACT_KINDS,
	goal,
	incomeSchedule,
	ledgerTxn,
	notebookPage,
	NOTEBOOK_MAX_CHARS,
	NOTEBOOK_PAGE_MAX_CHARS,
	NOTEBOOK_PAGE_TITLE_MAX,
	NOTEBOOK_SUMMARY_MAX,
	NOTEBOOK_TITLE_MAX,
	userSetting
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
/** An ISO 4217 code of the catalogue; an unknown one is refused with a plain message instead of failing deeper in. */
export const currencyField = z
	.string()
	.refine(isCurrencyCode, 'Use a currency code such as PHP or USD');
const dayField = z.string().refine(isDate, 'Use a real date written YYYY-MM-DD');
const idField = z.uuid();
const nameField = z.string().trim().min(1).max(60);
const noteField = z.string().trim().max(200);
const versionField = z.number().int().min(1);
/** An instant as ISO text, for example 2026-10-21T04:00:00Z. */
const instantField = z.iso.datetime({ offset: true });

/** Start, end and skipped dates: only paydays and the schedule preview take them (a bill has its own first date and per-date changes). */
const limitFields = {
	startsOn: dayField.optional(),
	endsOn: dayField.optional(),
	skipDates: z
		.array(dayField)
		.max(
			MAX_SKIP_DATES,
			`Leave out at most ${MAX_SKIP_DATES} dates: remove the old ones from skipDates first.`
		)
		.optional()
};

/** One shape of every repeat kind; `extra` adds the limits to each, since a field added after the union would be stripped. */
function scheduleShapes<E extends z.ZodRawShape>(extra: E) {
	return [
		z.object({
			...extra,
			kind: z.literal('semi_monthly'),
			days: z.tuple([z.number().int(), z.number().int()])
		}),
		z.object({
			...extra,
			kind: z.literal('every_n_days'),
			anchor: z.string(),
			n: z.number().int()
		}),
		z.object({
			...extra,
			kind: z.literal('monthly'),
			day: z.number().int(),
			everyMonths: z.number().int().optional(),
			anchorMonth: z.string().optional()
		}),
		z.object({
			...extra,
			kind: z.literal('weekly'),
			days: z.array(z.number().int()).max(7),
			everyWeeks: z.number().int().optional(),
			anchor: z.string().optional()
		}),
		z.object({
			...extra,
			kind: z.literal('nth_weekday'),
			n: z.number().int(),
			weekday: z.number().int(),
			everyMonths: z.number().int().optional(),
			anchorMonth: z.string().optional()
		}),
		z.object({
			...extra,
			kind: z.literal('week_of_month'),
			n: z.number().int(),
			basis: z.enum(['days', 'calendar']),
			weekStartsOn: z.number().int().optional(),
			pick: z.enum(['window', 'weekday']),
			weekday: z.number().int().optional(),
			everyMonths: z.number().int().optional(),
			anchorMonth: z.string().optional()
		}),
		z.object({
			...extra,
			kind: z.literal('day_range'),
			from: z.number().int(),
			to: z.number().int(),
			everyMonths: z.number().int().optional(),
			anchorMonth: z.string().optional()
		}),
		z.object({
			...extra,
			kind: z.literal('yearly'),
			month: z.number().int(),
			day: z.number().int()
		}),
		z.object({ ...extra, kind: z.literal('once'), date: z.string() })
	] as const;
}

function scheduleWith<E extends z.ZodRawShape>(extra: E) {
	return z.discriminatedUnion('kind', scheduleShapes(extra)).superRefine((s, ctx) => {
		const problem = validateSchedule(s as Schedule);
		if (problem) ctx.addIssue({ code: 'custom', message: problem });
	});
}

/** A repeat rule, checked the same way the engine checks it. */
export const scheduleInput = scheduleWith({});

/** A repeat rule with start, end and skipped dates. */
export const scheduleLimitedInput = scheduleWith(limitFields);

/** A payday is one day: a range of days or a week window would leave the date of the split unknown. */
export const paydayScheduleInput = scheduleLimitedInput.superRefine((s, ctx) => {
	if (s.kind === 'day_range' || (s.kind === 'week_of_month' && s.pick === 'window'))
		ctx.addIssue({
			code: 'custom',
			message: 'A payday is one day. Pick a day or a weekday, not a range of days or a whole week.'
		});
	if (s.kind === 'once')
		ctx.addIssue({ code: 'custom', message: 'A payday repeats. Pick a repeating schedule.' });
});

// -- MARKS -- //

/**
 * How an account or a bill is marked: a built-in icon key or the person's own picture. Left out, the mark stays; icon null or clearImage
 * removes it. imageId is never an input (a picture is owned by its row and made from imageData), and imageData is the person's alone
 * (the assistant's schemas leave it out and the verb refuses it again).
 */
const markFields = {
	icon: z.enum(ICON_KEYS).nullable().optional(),
	/** A JPEG, PNG or WebP of at most 24 KB, as base64 text. */
	imageData: z.string().max(PICTURE_MAX_BASE64).optional()
};

/** The picture of an account or a bill, fetched once per id by the app. */
export const pictureGetInput = z.strictObject({ imageId: z.uuid() });

// -- ACCOUNTS -- //

/** What an account is dedicated to. Short, no run of four or more digits (an account or phone number must not be kept in a label). Null clears it, absent leaves it alone. */
export const PURPOSE_MAX = 24;
const purposeField = z
	.string()
	.trim()
	.min(1)
	.max(PURPOSE_MAX)
	.refine(
		(v) => !/\d{4}/.test(v.normalize('NFKC').replace(/[\s\-./]/g, '')),
		'A label cannot hold a long number'
	)
	.nullable()
	.optional();

export const accountCreateInput = createInsertSchema(account, {
	name: nameField,
	// Left out, the column's own default (zero) applies. A zod default here would reset the field on every update
	minBalance: z.number().int().min(0).max(MAX_CENTAVOS).optional(),
	purpose: purposeField,
	// Left out, a new account is in the person's main currency
	currency: currencyField.optional()
})
	.pick({
		name: true,
		kind: true,
		minBalance: true,
		purpose: true,
		sortOrder: true,
		currency: true
	})
	.extend(markFields);

/** Adds a currency to an account (a Wise or PayPal account holds several). */
export const walletAddInput = z.object({ accountId: idField, currency: currencyField });

export const accountUpdateInput = accountCreateInput.partial().extend({
	accountId: idField,
	clearImage: z.boolean().optional(),
	expectVersion: versionField.optional()
});

export const accountIdInput = z.object({ accountId: idField });

/** An amount in the smallest unit of one currency, converted to another with the stored rates. Zero is allowed. */
export const fxConvertInput = z.object({
	amount: z.number().int().min(0).max(MAX_CENTAVOS),
	from: currencyField,
	to: currencyField
});

// -- INCOME -- //

export const incomeCreateInput = createInsertSchema(incomeSchedule, {
	label: nameField,
	accountId: idField,
	expectedAmount: amountField.nullable().optional(),
	schedule: paydayScheduleInput
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

// -- CHAT HISTORY -- //

/** The recent conversation: how many turns to return. The default (20) is applied by the operation, not here. */
export const chatHistoryInput = z.strictObject({
	limit: z.number().int().min(1).max(30).optional(),
	/** Which chat. Left out, the newest one that is not archived. */
	chatId: idField.optional()
});

// -- CHATS -- //

/** The list of chats: a search needs two characters, and the archive is listed on its own. */
export const chatListInput = z.strictObject({
	limit: z.number().int().min(1).max(100).optional(),
	search: z.string().trim().min(2).max(80).optional(),
	archived: z.boolean().optional()
});

export const chatIdInput = z.strictObject({ chatId: idField });

export const chatRenameInput = chatIdInput.extend({ title: z.string().trim().min(1).max(80) });

export const chatPinInput = chatIdInput.extend({ pinned: z.boolean() });

export const chatArchiveInput = chatIdInput.extend({ archived: z.boolean() });

/** A branch: up to a message (included, unless includeTurn is false), or the whole chat when no message is named. */
export const chatForkInput = chatIdInput.extend({
	upToTurnId: idField.optional(),
	includeTurn: z.boolean().optional()
});

// -- AUDIT -- //

/** The history of one account: filters are all optional, and the page is cut by the sequence number of the last row seen. */
export const accountHistoryInput = z.object({
	accountId: idField,
	/** Which wallet's history and running balance. Left out, the account's own currency. */
	currency: currencyField.optional(),
	from: dayField.optional(),
	to: dayField.optional(),
	/** Who did it: the person, the assistant, a job or sync. */
	by: z.enum(['person', 'agent', 'job', 'system']).optional(),
	action: z
		.enum([
			'create',
			'update',
			'delete',
			'undo',
			'count',
			'reset',
			'approve',
			'reject',
			'expire',
			'data_reset'
		])
		.optional(),
	search: z.string().trim().max(60).optional(),
	/** The sequence number of the last row of the previous page: the next page is older. */
	cursor: z.number().int().min(1).optional(),
	limit: z.number().int().min(1).max(100).optional()
});

export const auditExportInput = z.object({
	accountId: idField.optional(),
	from: dayField.optional(),
	to: dayField.optional(),
	format: z.enum(['csv', 'json'])
});

// -- CALENDAR -- //

/** Everything dated between two days (at most 92), and the forecast of the balances. */
export const calendarRangeInput = z.object({
	from: dayField,
	to: dayField,
	layers: z
		.array(z.enum(['bills', 'paydays', 'events', 'routines', 'tasks', 'reminders']))
		.max(6)
		.optional()
});

// -- DATA RESET -- //

const resetScope = z.enum(['money', 'schedule', 'memory_and_chat', 'audit', 'everything']);

/** Counts what a scope would erase and mints a confirmation that works once, for five minutes. Changes nothing. */
export const dataResetPreviewInput = z.object({ scope: resetScope });

/** The erase itself: the confirmation from the preview and the word the person typed. */
export const dataResetInput = z.object({
	scope: resetScope,
	token: z.string().regex(/^[0-9a-f]{32}$/, 'The confirmation is not valid'),
	typed: z.string()
});

// -- SETTINGS -- //

/** The settings a person can change. Left out, a field keeps its value; defaults live on the database columns. */
export const settingsSetInput = createInsertSchema(userSetting, {
	currency: z.enum(CURRENCY_CODES as [string, ...string[]]),
	weekStartsOn: z.number().int().min(0).max(1)
})
	.pick({
		currency: true,
		language: true,
		replyLanguage: true,
		weekStartsOn: true,
		// Null puts the person back on the server default; whether the key exists is checked in the ops layer
		modelProvider: true,
		showNetBalance: true,
		photoMode: true
	})
	.partial();

// -- BILLS -- //

export const billCreateInput = createInsertSchema(bill, {
	name: nameField,
	category: z.string().trim().min(1).max(40),
	accountId: idField,
	amount: amountField.nullable().optional(),
	schedule: scheduleInput,
	// Left out on create it is today; null on an edit makes every earlier date count
	startsOn: dayField.nullable().optional(),
	// Left out, a new bill is in the person's main currency
	currency: currencyField.optional()
})
	.pick({
		name: true,
		category: true,
		accountId: true,
		kind: true,
		amount: true,
		schedule: true,
		weekendRule: true,
		deferrable: true,
		startsOn: true,
		currency: true
	})
	.extend(markFields);

export const billUpdateInput = billCreateInput.partial().extend({
	billId: idField,
	active: z.boolean().optional(),
	clearImage: z.boolean().optional(),
	expectVersion: versionField.optional()
});

export const billMarkPaidInput = z.object({
	billId: idField,
	dueDate: dayField,
	/** What the bill was this time, in the bill's own currency. Defaults to the bill's amount or its estimate. */
	amount: amountField.optional(),
	/** Pay from another account than the bill's own. */
	accountId: idField.optional(),
	/** The currency of the wallet it was paid from, when that is not the bill's own (a dollar bill paid in pesos). */
	paidCurrency: currencyField.optional(),
	/** What was really charged in that currency. Required when paidCurrency is not the bill's currency. */
	paidAmount: amountField.optional()
});

export const billIdInput = z.object({ billId: idField });

/**
 * One due date of a bill changed on its own: moved, a different amount, another account, or skipped. `dueDate` is the date the
 * occurrence has now (the schedule's date or the one it was moved to). A field left out keeps what it has, a null clears it.
 */
export const billOccurrenceUpdateInput = createInsertSchema(billOverride, {
	newDueDate: dayField.nullable().optional(),
	amount: amountField.nullable().optional(),
	accountId: idField.nullable().optional()
})
	.pick({ newDueDate: true, amount: true, accountId: true, skipped: true })
	.partial()
	.extend({ billId: idField, dueDate: dayField, expectVersion: versionField.optional() });

/** Puts one due date of a bill back to what the schedule says. */
export const billOccurrenceResetInput = z.object({ billId: idField, dueDate: dayField });

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

const ruleLabelField = z.string().trim().min(1).max(60);

export const ruleProposeInput = createInsertSchema(allocationRule, {
	label: ruleLabelField.nullable(),
	amount: amountField.nullable(),
	basisPoints: z.number().int().min(1).max(10_000).nullable(),
	targetAccountId: idField.nullable(),
	targetGoalId: idField.nullable(),
	fundsBillId: idField.nullable(),
	effectiveFrom: dayField,
	position: z.number().int().min(1).max(999)
})
	.pick({
		label: true,
		mode: true,
		amount: true,
		basisPoints: true,
		base: true,
		targetAccountId: true,
		targetGoalId: true,
		fundsBillId: true,
		effectiveFrom: true,
		position: true
	})
	.partial({
		label: true,
		amount: true,
		basisPoints: true,
		base: true,
		targetAccountId: true,
		targetGoalId: true,
		fundsBillId: true,
		effectiveFrom: true,
		position: true
	});

export const ruleFromTextInput = z.object({
	text: z.string().trim().min(3).max(200),
	label: ruleLabelField.nullable().optional(),
	effectiveFrom: dayField.optional(),
	position: z.number().int().min(1).max(999).optional()
});

export const ruleIdInput = z.object({ ruleId: idField });

/**
 * Renames a rule, or links it to the bill it saves for (BTL-20261029-0119). A field left out stays as it is; null clears it. The money and
 * the target stay as approved. No defaults here: a default would clear the other field on every update.
 */
export const ruleUpdateInput = z.object({
	ruleId: idField,
	label: ruleLabelField.nullable().optional(),
	fundsBillId: idField.nullable().optional()
});
export type RuleUpdateInput = z.infer<typeof ruleUpdateInput>;

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
		/** The wallet it is spent from. Left out, the account's own currency. */
		currency: currencyField.optional(),
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
	/** The wallet it arrives in. Left out, the account's own currency. */
	currency: currencyField.optional(),
	note: noteField.optional(),
	occurredAt: instantField.optional()
});

export const refundRecordInput = incomeRecordInput;

export const transferRecordInput = z.object({
	fromAccountId: idField,
	toAccountId: idField,
	amount: amountField,
	/** The wallet it leaves from, and the one it lands in. Left out, the currency of each account. */
	currency: currencyField.optional(),
	toCurrency: currencyField.optional(),
	/** What really arrived, when the two wallets are in different currencies (the rate is then the person's own). */
	toAmount: amountField.optional(),
	fee: z.number().int().min(0).max(MAX_CENTAVOS).optional(),
	note: noteField.optional(),
	occurredAt: instantField.optional()
});

export const snapshotRecordInput = z.object({
	accountId: idField,
	/** What the account holds right now. A credit balance may be negative. */
	amount: z.number().int().min(-MAX_CENTAVOS).max(MAX_CENTAVOS),
	/** Which wallet is counted. Left out, the account's own currency. */
	currency: currencyField.optional(),
	takenAt: instantField.optional(),
	source: z.enum(['manual', 'chat', 'ocr', 'screenshot']).optional(),
	confirmed: z.boolean().optional(),
	/** A second yes for a count that is ten times more or less than the last one. */
	acknowledgeLarge: z.boolean().optional(),
	/** 'reset' sets the account to this amount on purpose: the difference is a reset, not spending, and it needs a reason. */
	mode: z.enum(['count', 'reset']).optional(),
	reason: z.string().trim().min(1).max(120).optional()
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

/** A schedule to preview: the sentence that says what it means and the next windows it would produce. */
export const schedulePreviewInput = z.object({
	schedule: scheduleLimitedInput,
	weekend: z.enum(['none', 'before', 'after']).optional(),
	/** The date to look from. Left out, today in Manila. */
	from: dayField.optional(),
	count: z.number().int().min(1).max(12).optional()
});

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
		}),
		z.object({ freq: z.literal('schedule'), schedule: scheduleInput, time: z.string() })
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

// -- GOAL DELETE -- //

/** A goal removed for good, with the payday rules that point at it. */
export const goalDeleteInput = z.object({ goalId: idField });

// -- PLAN DELETES -- //

/** A bill removed. A bill that has payments or ledger entries is switched off instead, so its history stays. */
export const billDeleteInput = z.object({ billId: idField });

/** A payday schedule removed. One that a payday split was made for is switched off instead. */
/** withSplits also removes the payday splits made for it, so the payday itself can go instead of being switched off. */
export const incomeDeleteInput = z.object({
	incomeId: idField,
	withSplits: z.boolean().optional()
});

/** A payday rule removed for good, whatever its status. */
export const ruleDeleteInput = z.object({ ruleId: idField });

/** An account removed. One with entries, counts or things that point at it is hidden instead. */
export const accountDeleteInput = z.object({ accountId: idField });

/** A currency taken off an account. Only an empty wallet that is not the account's own currency. */
export const walletRemoveInput = z.object({ accountId: idField, currency: currencyField });

// -- FORECAST -- //

/** The cash-flow forecast from today to a date, by day (up to 62 days), by week (the person's week start) or by month. */
export const cashflowForecastInput = z.object({
	to: dayField,
	group: z.enum(['day', 'week', 'month']).optional()
});

// -- SIMULATION (BTL-20261029-0117) -- //

/** A what-if amount: whole minor units, 1 to 10^12, so 50 of them over 5 years stay safe integers. */
const whatIfAmount = z.number().int().min(1).max(1_000_000_000_000);

/**
 * A what-if: changes to the money plan that are never saved (finance/scenario.ts). Kept small, as it is part of the assistant's tool
 * schema on every turn: one list of ids to switch off (any payday, bill, rule or goal), one list of amounts (a payday or a bill, by id),
 * dates whose paydays do not come, and pretend entries in the main currency. Every list is bounded and every id is a uuid.
 */
export const scenarioInput = z.strictObject({
	off: z.array(idField).max(200).optional(),
	amounts: z
		.array(z.strictObject({ id: idField, amount: whatIfAmount }))
		.max(100)
		.optional(),
	skipDates: z.array(dayField).max(100).optional(),
	lateDays: z.number().int().min(0).max(60).optional(),
	defer: z.boolean().optional(),
	extra: z
		.array(
			z.strictObject({
				date: dayField,
				kind: z.enum(['in', 'out']),
				accountId: idField,
				amount: whatIfAmount,
				label: z
					.string()
					.trim()
					.max(40)
					.refine((t) => t.length > 0, 'Give the entry a name')
			})
		)
		.max(50)
		.optional()
});

export type ScenarioInput = z.infer<typeof scenarioInput>;

/** The balance timeline from one day to another, by day, week, month or year; detail adds every entry of a range of at most a year. */
export const balanceSimulateInput = z.object({
	from: dayField,
	to: dayField,
	group: z.enum(['day', 'week', 'month', 'year']).optional(),
	view: z.enum(['overview', 'detail']).optional(),
	scenario: scenarioInput.optional(),
	/** detail only, the app: a page of the entries (limit 1 to 100, 50 when only an offset or a group is sent) and optionally of one group. */
	offset: z.number().int().min(0).max(100_000).optional(),
	limit: z.number().int().min(1).max(100).optional(),
	groupKey: z.string().min(1).max(200).optional()
});

export type BalanceSimulateInput = z.infer<typeof balanceSimulateInput>;

// -- CALCULATOR -- //

/** Lines for the calculator. A line may name its result, and may ask for it as money in a currency (in that currency's own unit, or `minor`). */
export const calcInput = z.object({
	lines: z
		.array(
			z.strictObject({
				name: z.string().trim().max(40).optional(),
				expr: z.string().max(500),
				currency: currencyField.optional(),
				unit: z.enum(['major', 'minor']).optional()
			})
		)
		.min(1)
		.max(60)
});

// -- NOTEBOOK -- //

/**
 * Which notebook a verb is about. Left out it is the main notebook. The app names one by id; the assistant names an extra one by its
 * title (unique among a person's live notebooks, ignoring case). Naming both is refused by the verb.
 */
const notebookTarget = {
	notebookId: idField.optional(),
	notebook: z.string().trim().min(1).max(NOTEBOOK_TITLE_MAX).optional()
};

export const notebookTargetInput = z.object(notebookTarget);

/** The whole text of a notebook, from the version the editor was opened on (0 when there was no notebook yet). */
export const notebookSaveInput = z.object({
	...notebookTarget,
	text: z.string().max(NOTEBOOK_MAX_CHARS),
	expectVersion: z.number().int().min(0)
});

/** One change to a notebook that the assistant makes: add a line under a heading, or replace or remove exact text. */
export const notebookEditInput = z.object({
	/** The extra notebook to change, by title. Left out it is the main notebook. */
	notebook: notebookTarget.notebook,
	notebookId: notebookTarget.notebookId,
	op: z.enum(['add', 'replace', 'remove'], {
		error:
			'op must be "add" (with heading and line), "replace" (with find and replacement) or "remove" (with find).'
	}),
	/** For add: the heading to add the line under. It is made when it is not there yet. */
	heading: z.string().trim().min(1).max(80).optional(),
	/** For add: the line, one short sentence. */
	line: z.string().trim().min(1).max(400).optional(),
	/** For replace and remove: the exact text to change. It must appear once in the notebook. */
	find: z.string().min(1).max(2000).optional(),
	/** For replace: the text that takes its place. */
	replacement: z.string().max(2000).optional()
});

export const notebookRestoreInput = z.object({ revisionId: idField });

/** A new extra notebook: its title, one line saying what it holds, and optionally its first text. */
export const notebookCreateInput = z.object({
	title: z.string().trim().min(1).max(NOTEBOOK_TITLE_MAX),
	summary: z.string().trim().max(NOTEBOOK_SUMMARY_MAX).optional(),
	text: z.string().max(NOTEBOOK_MAX_CHARS).optional()
});

/** Rename an extra notebook or change its one-line summary. */
export const notebookUpdateInput = z.object({
	...notebookTarget,
	newTitle: z.string().trim().min(1).max(NOTEBOOK_TITLE_MAX).optional(),
	summary: z.string().trim().max(NOTEBOOK_SUMMARY_MAX).optional()
});

/** The notebook list: with deleted true, the deleted ones that can still be restored. */
export const notebookListInput = z.object({ deleted: z.boolean().optional() });

// -- NOTEBOOK PAGES -- //

/** A page title: one line, at most 80 characters. */
const pageTitleField = z.string().trim().min(1).max(NOTEBOOK_PAGE_TITLE_MAX);

/**
 * A parent page named by its title. An empty text, or "top level", means no parent: the top-level page of that title (so a top-level page and a
 * sub-page that share a title can always be told apart).
 */
const parentField = z.string().trim().max(NOTEBOOK_PAGE_TITLE_MAX);

/**
 * Which page a verb is about. The app names it by id. The assistant names it by the title of its notebook and its own title, and by the
 * title of its parent page only when the same title is used under two parents of one notebook (parent "top level" picks the top-level one).
 * Naming both ways is refused by the verb.
 */
const pageTarget = {
	pageId: idField.optional(),
	notebook: z.string().trim().min(1).max(NOTEBOOK_TITLE_MAX).optional(),
	page: pageTitleField.optional(),
	parent: parentField.optional()
};

export const pageTargetInput = z.object(pageTarget);

/** A new page, generated from the page table: its title and first text. The notebook and the parent are named by title (the assistant) or by id (the app). */
export const pageCreateInput = createInsertSchema(notebookPage, {
	title: pageTitleField,
	text: z.string().max(NOTEBOOK_PAGE_MAX_CHARS).optional()
})
	.pick({ title: true, text: true })
	.extend({
		notebookId: idField.optional(),
		notebook: pageTarget.notebook,
		parentPageId: idField.optional(),
		parent: pageTarget.parent,
		position: z.number().int().min(0).max(1000).optional()
	});

/** One change to a page by exact text, like notebook_edit: add a line under a heading, or replace or remove text that appears once. */
export const pageEditInput = z.object({
	...pageTarget,
	op: z.enum(['add', 'replace', 'remove'], {
		error:
			'op must be "add" (with heading and line), "replace" (with find and replacement) or "remove" (with find).'
	}),
	/** For add: the heading to add the line under. It is made when it is not there yet. */
	heading: z.string().trim().min(1).max(80).optional(),
	/** For add: the line or lines to add. */
	line: z.string().trim().min(1).max(NOTEBOOK_PAGE_MAX_CHARS).optional(),
	/** For replace and remove: the exact text to change. It must appear once in the page. */
	find: z.string().min(1).max(NOTEBOOK_PAGE_MAX_CHARS).optional(),
	/** For replace: the text that takes its place. */
	replacement: z.string().max(NOTEBOOK_PAGE_MAX_CHARS).optional()
});

/** The person saves the whole text of a page, from the version they opened. A stale version is refused. */
export const pageSaveInput = z.object({
	pageId: idField,
	text: z.string().max(NOTEBOOK_PAGE_MAX_CHARS),
	expectVersion: z.number().int().min(1)
});

export const pageRenameInput = z.object({ ...pageTarget, newTitle: pageTitleField });

/**
 * Move a page. The destination names a notebook and, for a sub-page, its top-level parent; with neither the page goes to the top level of its own
 * notebook. `position` is the place among the pages there (0 is first); left out it goes last. To reorder a sub-page, name its parent again.
 */
export const pageMoveInput = z.object({
	...pageTarget,
	toNotebookId: idField.optional(),
	toNotebook: pageTarget.notebook,
	toParentPageId: idField.optional(),
	toParent: pageTarget.parent,
	position: z.number().int().min(0).max(1000).optional()
});

const pageSource = z.object({
	notebook: pageTarget.notebook,
	page: pageTitleField,
	parent: pageTarget.parent
});

/** Merge pages into one: the text of each source is added under its own heading at the end of the target, and the sources are deleted (restorable). */
export const pageMergeInput = z.object({
	...pageTarget,
	sources: z.array(pageSource).min(1).max(10).optional(),
	sourceIds: z.array(idField).min(1).max(10).optional()
});

export const pageUndeleteInput = pageTargetInput;

/** The person pins or unpins a page. */
export const pagePinInput = z.object({ pageId: idField, pinned: z.boolean() });

/** The person pins or unpins a notebook. */
export const notebookPinInput = z.object({ notebookId: idField, pinned: z.boolean() });

/** The person has looked at a page up to this version. Only the seen mark moves. */
export const pageSeenInput = z.object({
	pageId: idField,
	version: z.number().int().min(1).max(2147483647)
});

export const pageIdInput = z.object({ pageId: idField });

export const pageRevisionInput = z.object({ revisionId: idField });

/** The outline: every live notebook with its pages, or one notebook. With deleted true, the deleted pages that can still be restored. */
export const notebookOutlineInput = z.object({
	notebookId: idField.optional(),
	notebook: pageTarget.notebook,
	deleted: z.boolean().optional()
});

/** Search the titles and texts of the pages (the main notebook is in the prompt already). */
export const notebookSearchInput = z.object({
	query: z.string().trim().min(2).max(100),
	notebook: pageTarget.notebook,
	notebookId: idField.optional(),
	limit: z.number().int().min(1).max(50).optional()
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

export const splitListInput = z.object({
	limit: z.number().int().min(1).max(50).optional(),
	/** Splits replaced by a newer proposal are left out unless this is true. */
	includeReplaced: z.boolean().optional()
});

export const splitApproveInput = z.object({
	splitId: idField,
	/** Write the pay into the ledger too. Defaults to yes once the payday has come, and to no before it. */
	recordIncome: z.boolean().optional()
});

/** Removes one recorded split, or all of them. removeEntries also voids the pay and the transfers the split wrote to the ledger. */
export const splitDeleteInput = z
	.object({
		splitId: idField.optional(),
		all: z.boolean().optional(),
		removeEntries: z.boolean().optional()
	})
	.refine((v) => (v.splitId !== undefined) !== (v.all === true), {
		message: 'Name one split (splitId), or send all: true to remove every split.'
	});

export const splitSentInput = z.object({
	splitId: idField,
	index: z.number().int().min(0).max(50)
});

export type WalletAddInput = z.infer<typeof walletAddInput>;
export type WalletRemoveInput = z.infer<typeof walletRemoveInput>;
export type FxConvertInput = z.infer<typeof fxConvertInput>;
export type AccountCreateInput = z.infer<typeof accountCreateInput>;
export type AccountUpdateInput = z.infer<typeof accountUpdateInput>;
export type IncomeCreateInput = z.infer<typeof incomeCreateInput>;
export type IncomeUpdateInput = z.infer<typeof incomeUpdateInput>;
export type BillCreateInput = z.infer<typeof billCreateInput>;
export type BillUpdateInput = z.infer<typeof billUpdateInput>;
export type BillOccurrenceUpdateInput = z.infer<typeof billOccurrenceUpdateInput>;
export type BillOccurrenceResetInput = z.infer<typeof billOccurrenceResetInput>;
export type SchedulePreviewInput = z.infer<typeof schedulePreviewInput>;
export type AccountHistoryInput = z.infer<typeof accountHistoryInput>;
export type ChatHistoryInput = z.infer<typeof chatHistoryInput>;
export type ChatListInput = z.infer<typeof chatListInput>;
export type ChatIdInput = z.infer<typeof chatIdInput>;
export type ChatRenameInput = z.infer<typeof chatRenameInput>;
export type ChatPinInput = z.infer<typeof chatPinInput>;
export type ChatArchiveInput = z.infer<typeof chatArchiveInput>;
export type ChatForkInput = z.infer<typeof chatForkInput>;
export type AuditExportInput = z.infer<typeof auditExportInput>;
export type CalendarRangeInput = z.infer<typeof calendarRangeInput>;
export type DataResetInput = z.infer<typeof dataResetInput>;
export type DataResetPreviewInput = z.infer<typeof dataResetPreviewInput>;
export type SettingsSetInput = z.infer<typeof settingsSetInput>;
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
