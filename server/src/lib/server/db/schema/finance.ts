// THE FINANCE TABLES: ACCOUNTS, INCOME, BILLS, GOALS, ALLOCATION RULES, THE LEDGER, BALANCE SNAPSHOTS AND SPLIT PLANS
// Every amount is integer centavos (PHP). Every "day" is a Manila calendar date (a date column read as text). Every row belongs to one
// person; a reference to another table also carries user_id (a composite key), so a row can never point at another person's row,
// which a plain foreign key would allow because foreign key checks do not go through row level security.

// -- DEP-MODULES -- //
import { sql } from 'drizzle-orm';
import {
	boolean,
	check,
	date,
	foreignKey,
	index,
	integer,
	jsonb,
	text,
	timestamp,
	unique,
	uniqueIndex,
	uuid
} from 'drizzle-orm/pg-core';
// -- MODULES -- //
import { user } from './auth';
import { centavos, id, oneOf, stamps, userTable, version } from './helpers';

// -- CONSTANTS -- //

export const ACCOUNT_KINDS = ['bank', 'ewallet', 'cash', 'other'] as const;
export const BILL_KINDS = ['fixed', 'variable'] as const;
export const WEEKEND_RULE_VALUES = ['none', 'before', 'after'] as const;
export const RULE_MODE_VALUES = ['fixed', 'percent', 'rest'] as const;
export const RULE_BASE_VALUES = ['pay', 'remaining'] as const;
export const RULE_STATUSES = ['proposed', 'active', 'retired'] as const;
export const TXN_TYPE_VALUES = ['income', 'expense', 'transfer', 'refund', 'adjustment'] as const;
export const TXN_SOURCES = [
	'manual',
	'chat',
	'ocr',
	'screenshot',
	'split',
	'bill',
	'drift'
] as const;
export const SPLIT_STATUSES = ['proposed', 'approved', 'shortfall', 'superseded'] as const;

// -- ACCOUNTS -- //

export const account = userTable(
	'account',
	() => user.id,
	{
		id: id(),
		name: text('name').notNull(),
		kind: text('kind', { enum: ACCOUNT_KINDS }).notNull().default('bank'),
		/** The balance the person wants to keep in it. The split tops it up before spending money elsewhere. */
		minBalance: centavos('min_balance').notNull().default(0),
		sortOrder: integer('sort_order').notNull().default(0),
		archivedAt: timestamp('archived_at', { withTimezone: true }),
		version: version(),
		...stamps()
	},
	(t) => [
		// The composite key other tables point at
		unique('account_user_id_uq').on(t.userId, t.id),
		uniqueIndex('account_user_name_uq').on(t.userId, sql`lower(${t.name})`),
		oneOf('account_kind_chk', t.kind, ACCOUNT_KINDS),
		check('account_min_balance_chk', sql`${t.minBalance} >= 0`)
	]
);

// -- INCOME -- //

export const incomeSchedule = userTable(
	'income_schedule',
	() => user.id,
	{
		id: id(),
		label: text('label').notNull(),
		/** The account the pay lands in. */
		accountId: uuid('account_id').notNull(),
		/** What the pay usually is, centavos. Null when it varies: the person says it on the day. */
		expectedAmount: centavos('expected_amount'),
		/** A Schedule (see src/lib/finance/schedule.ts), checked by Zod on the way in. */
		schedule: jsonb('schedule').notNull(),
		weekendRule: text('weekend_rule', { enum: WEEKEND_RULE_VALUES }).notNull().default('before'),
		active: boolean('active').notNull().default(true),
		version: version(),
		...stamps()
	},
	(t) => [
		unique('income_schedule_user_id_uq').on(t.userId, t.id),
		foreignKey({
			name: 'income_schedule_account_fk',
			columns: [t.userId, t.accountId],
			foreignColumns: [account.userId, account.id]
		}),
		oneOf('income_schedule_weekend_chk', t.weekendRule, WEEKEND_RULE_VALUES),
		check('income_schedule_amount_chk', sql`${t.expectedAmount} is null or ${t.expectedAmount} > 0`)
	]
);

// -- BILLS -- //

export const bill = userTable(
	'bill',
	() => user.id,
	{
		id: id(),
		name: text('name').notNull(),
		/** The parents' share is a bill with the category "parents". Other categories are free text such as "rent". */
		category: text('category').notNull().default('other'),
		/** The account the bill is paid from. */
		accountId: uuid('account_id').notNull(),
		kind: text('kind', { enum: BILL_KINDS }).notNull().default('fixed'),
		/** The amount of a fixed bill, or what the person said a variable bill usually is (used until there are 3 payments). */
		amount: centavos('amount'),
		schedule: jsonb('schedule').notNull(),
		weekendRule: text('weekend_rule', { enum: WEEKEND_RULE_VALUES }).notNull().default('none'),
		/** Can wait for the next payday when the pay is short. */
		deferrable: boolean('deferrable').notNull().default(false),
		active: boolean('active').notNull().default(true),
		version: version(),
		...stamps()
	},
	(t) => [
		unique('bill_user_id_uq').on(t.userId, t.id),
		foreignKey({
			name: 'bill_account_fk',
			columns: [t.userId, t.accountId],
			foreignColumns: [account.userId, account.id]
		}),
		oneOf('bill_kind_chk', t.kind, BILL_KINDS),
		oneOf('bill_weekend_chk', t.weekendRule, WEEKEND_RULE_VALUES),
		check('bill_amount_chk', sql`${t.amount} is null or ${t.amount} > 0`),
		// A fixed bill always has its amount
		check('bill_fixed_amount_chk', sql`${t.kind} <> 'fixed' or ${t.amount} is not null`)
	]
);

// -- GOALS -- //

export const goal = userTable(
	'goal',
	() => user.id,
	{
		id: id(),
		name: text('name').notNull(),
		/** The account the saved money sits in. */
		accountId: uuid('account_id').notNull(),
		/** The amount the person wants to reach, centavos. Null for an open goal. */
		targetAmount: centavos('target_amount'),
		/** What is set aside on every payday, centavos. Zero means only the rules feed it. */
		perPayday: centavos('per_payday').notNull().default(0),
		active: boolean('active').notNull().default(true),
		version: version(),
		...stamps()
	},
	(t) => [
		unique('goal_user_id_uq').on(t.userId, t.id),
		uniqueIndex('goal_user_name_uq').on(t.userId, sql`lower(${t.name})`),
		foreignKey({
			name: 'goal_account_fk',
			columns: [t.userId, t.accountId],
			foreignColumns: [account.userId, account.id]
		}),
		check('goal_target_chk', sql`${t.targetAmount} is null or ${t.targetAmount} > 0`),
		check('goal_per_payday_chk', sql`${t.perPayday} >= 0`)
	]
);

// -- ALLOCATION RULES -- //

export const allocationRule = userTable(
	'allocation_rule',
	() => user.id,
	{
		id: id(),
		position: integer('position').notNull(),
		mode: text('mode', { enum: RULE_MODE_VALUES }).notNull(),
		amount: centavos('amount'),
		/** Hundredths of a percent: 2000 is 20%. */
		basisPoints: integer('basis_points'),
		base: text('base', { enum: RULE_BASE_VALUES }).notNull().default('pay'),
		/** Exactly one of the two targets is set. */
		targetAccountId: uuid('target_account_id'),
		targetGoalId: uuid('target_goal_id'),
		effectiveFrom: date('effective_from', { mode: 'string' }).notNull(),
		/** A rule is proposed first and applies only once the person approves it. */
		status: text('status', { enum: RULE_STATUSES }).notNull().default('proposed'),
		/** The words the person used, when the rule was read from plain text. */
		sourceText: text('source_text'),
		approvedAt: timestamp('approved_at', { withTimezone: true }),
		version: version(),
		...stamps()
	},
	(t) => [
		index('allocation_rule_user_status_idx').on(t.userId, t.status, t.position),
		foreignKey({
			name: 'allocation_rule_account_fk',
			columns: [t.userId, t.targetAccountId],
			foreignColumns: [account.userId, account.id]
		}),
		foreignKey({
			name: 'allocation_rule_goal_fk',
			columns: [t.userId, t.targetGoalId],
			foreignColumns: [goal.userId, goal.id]
		}),
		oneOf('allocation_rule_mode_chk', t.mode, RULE_MODE_VALUES),
		oneOf('allocation_rule_base_chk', t.base, RULE_BASE_VALUES),
		oneOf('allocation_rule_status_chk', t.status, RULE_STATUSES),
		check(
			'allocation_rule_target_chk',
			sql`(${t.targetAccountId} is not null)::int + (${t.targetGoalId} is not null)::int = 1`
		),
		check(
			'allocation_rule_value_chk',
			sql`(${t.mode} = 'fixed' and ${t.amount} > 0 and ${t.basisPoints} is null)
				or (${t.mode} = 'percent' and ${t.basisPoints} between 1 and 10000 and ${t.amount} is null)
				or (${t.mode} = 'rest' and ${t.amount} is null and ${t.basisPoints} is null)`
		)
	]
);

// -- THE LEDGER -- //

export const ledgerTxn = userTable(
	'ledger_txn',
	() => user.id,
	{
		id: id(),
		type: text('type', { enum: TXN_TYPE_VALUES }).notNull(),
		/** The account it happens in. For a transfer, the source. */
		accountId: uuid('account_id').notNull(),
		/** The destination of a transfer. */
		toAccountId: uuid('to_account_id'),
		/** Centavos. Above zero for every type but an adjustment, which is signed and never zero. */
		amount: centavos('amount').notNull(),
		/** Charged to the source account of a transfer. */
		fee: centavos('fee').notNull().default(0),
		category: text('category'),
		note: text('note').notNull().default(''),
		occurredAt: timestamp('occurred_at', { withTimezone: true }).notNull().defaultNow(),
		source: text('source', { enum: TXN_SOURCES }).notNull().default('manual'),
		billId: uuid('bill_id'),
		/** A split that created it, as a transfer marked sent. */
		splitId: uuid('split_id'),
		/** Undone, kept for the record, and counted as nothing. */
		voidedAt: timestamp('voided_at', { withTimezone: true }),
		...stamps()
	},
	(t) => [
		unique('ledger_txn_user_id_uq').on(t.userId, t.id),
		index('ledger_txn_account_time_idx').on(t.userId, t.accountId, t.occurredAt),
		index('ledger_txn_to_account_idx').on(t.userId, t.toAccountId),
		foreignKey({
			name: 'ledger_txn_account_fk',
			columns: [t.userId, t.accountId],
			foreignColumns: [account.userId, account.id]
		}),
		foreignKey({
			name: 'ledger_txn_to_account_fk',
			columns: [t.userId, t.toAccountId],
			foreignColumns: [account.userId, account.id]
		}),
		foreignKey({
			name: 'ledger_txn_bill_fk',
			columns: [t.userId, t.billId],
			foreignColumns: [bill.userId, bill.id]
		}),
		oneOf('ledger_txn_type_chk', t.type, TXN_TYPE_VALUES),
		oneOf('ledger_txn_source_chk', t.source, TXN_SOURCES),
		check(
			'ledger_txn_amount_chk',
			sql`(${t.type} = 'adjustment' and ${t.amount} <> 0) or (${t.type} <> 'adjustment' and ${t.amount} > 0)`
		),
		check('ledger_txn_fee_chk', sql`${t.fee} >= 0 and (${t.fee} = 0 or ${t.type} = 'transfer')`),
		check(
			'ledger_txn_transfer_chk',
			sql`(${t.type} = 'transfer' and ${t.toAccountId} is not null and ${t.toAccountId} <> ${t.accountId}) or (${t.type} <> 'transfer' and ${t.toAccountId} is null)`
		)
	]
);

// -- BILL PAYMENTS -- //

export const billPayment = userTable(
	'bill_payment',
	() => user.id,
	{
		id: id(),
		billId: uuid('bill_id').notNull(),
		/** The due date this payment is for. */
		dueDate: date('due_date', { mode: 'string' }).notNull(),
		amount: centavos('amount').notNull(),
		paidAt: timestamp('paid_at', { withTimezone: true }).notNull().defaultNow(),
		/** The expense this payment wrote in the ledger. */
		txnId: uuid('txn_id'),
		...stamps()
	},
	(t) => [
		unique('bill_payment_due_uq').on(t.userId, t.billId, t.dueDate),
		index('bill_payment_bill_paid_idx').on(t.userId, t.billId, t.paidAt),
		foreignKey({
			name: 'bill_payment_bill_fk',
			columns: [t.userId, t.billId],
			foreignColumns: [bill.userId, bill.id]
		}).onDelete('cascade'),
		foreignKey({
			name: 'bill_payment_txn_fk',
			columns: [t.userId, t.txnId],
			foreignColumns: [ledgerTxn.userId, ledgerTxn.id]
		}),
		check('bill_payment_amount_chk', sql`${t.amount} > 0`)
	]
);

// -- BALANCE SNAPSHOTS -- //

export const balanceSnapshot = userTable(
	'balance_snapshot',
	() => user.id,
	{
		id: id(),
		accountId: uuid('account_id').notNull(),
		/** What the account really held when counted, centavos. */
		amount: centavos('amount').notNull(),
		takenAt: timestamp('taken_at', { withTimezone: true }).notNull().defaultNow(),
		/** What the app expected at that moment, so the drift can be shown later. */
		expectedAmount: centavos('expected_amount'),
		source: text('source', { enum: TXN_SOURCES }).notNull().default('manual'),
		...stamps()
	},
	(t) => [
		index('balance_snapshot_account_time_idx').on(t.userId, t.accountId, t.takenAt),
		foreignKey({
			name: 'balance_snapshot_account_fk',
			columns: [t.userId, t.accountId],
			foreignColumns: [account.userId, account.id]
		}).onDelete('cascade')
	]
);

// -- SPLIT PLANS -- //

export const splitPlan = userTable(
	'split_plan',
	() => user.id,
	{
		id: id(),
		incomeScheduleId: uuid('income_schedule_id'),
		payday: date('payday', { mode: 'string' }).notNull(),
		pay: centavos('pay').notNull(),
		status: text('status', { enum: SPLIT_STATUSES }).notNull().default('proposed'),
		/** For a shortfall, how much more the pay would need to be. */
		gap: centavos('gap').notNull().default(0),
		/** The result of the engine: lines, transfers, cut options. Ids, labels and centavos only. */
		result: jsonb('result').notNull(),
		/** Which transfers the person marked as sent, by position in the transfer list. */
		sentTransfers: jsonb('sent_transfers').notNull().default([]),
		approvedAt: timestamp('approved_at', { withTimezone: true }),
		/** Who approved: always a person, never the agent. */
		approvedBy: text('approved_by'),
		...stamps()
	},
	(t) => [
		unique('split_plan_user_id_uq').on(t.userId, t.id),
		index('split_plan_user_payday_idx').on(t.userId, t.payday),
		foreignKey({
			name: 'split_plan_income_fk',
			columns: [t.userId, t.incomeScheduleId],
			foreignColumns: [incomeSchedule.userId, incomeSchedule.id]
		}),
		oneOf('split_plan_status_chk', t.status, SPLIT_STATUSES)
	]
);
