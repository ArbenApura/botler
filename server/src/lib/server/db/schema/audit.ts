// THE AUDIT TRAIL (BTL-20261022-0218, ADR 5): ONE ROW FOR EVERYTHING DONE TO A PERSON'S MONEY AND PLAN, BY THE PERSON, THE ASSISTANT, A JOB OR SYNC.
// Rows are written by database triggers (see the audit_triggers migration) in the same transaction as the change, so no verb can skip one.
// They are append-only (grants allow SELECT and INSERT only, a trigger refuses UPDATE and DELETE), numbered per person with a sequence and
// chained by a hash, so an edited or removed row is found by audit_verify. Never stored: message text, tokens, account numbers, or free text
// from outside sources (the allow-lists below name every column that is copied).

// -- DEP-MODULES -- //
import { bigint, index, jsonb, text, timestamp, unique, uuid } from 'drizzle-orm/pg-core';
// -- MODULES -- //
import { user } from './auth';
import { id, oneOf, userTable } from './helpers';

// -- TYPES -- //

export type AuditedTable = {
	table: string;
	columns: readonly string[];
	/** The column that names the account the row belongs to, or '' for none. */
	account: string;
	/** 'txn' when an amount change is read from a ledger row, '' for none. */
	amount: '' | 'txn';
	/** The migration that adds this table's trigger when it is not the first audit migration (0016). Empty for the tables of 0016. */
	migration?: string;
	/** The columns the trigger had when its migration ran, kept when a later migration replaced the trigger with a longer list. */
	firstColumns?: readonly string[];
	/**
	 * The later migrations that drop this table's trigger and create it again with a longer list of columns, oldest first. Each keeps the
	 * list it had, so its migration file stays checkable after a newer one adds more; the last one is the current list.
	 */
	redefinitions?: readonly { migration: string; columns: readonly string[] }[];
};

// -- CONSTANTS -- //

export const AUDIT_ACTOR_KINDS = ['person', 'agent', 'job', 'system'] as const;
export const AUDIT_CHANNELS = [
	'app',
	'chat',
	'widget',
	'outbox',
	'calendar_sync',
	'job',
	'system'
] as const;
export const AUDIT_ACTIONS = [
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
] as const;

/**
 * The tables that are audited and what is copied from each: the columns of before and after, the column that names the account the row
 * belongs to, and how an amount change is read. The trigger migration is checked against this list by a test, and a test fails for any
 * other tenant table that is not on EXEMPT_FROM_AUDIT. Titles and notes written by outside sources are never copied.
 */
export const AUDITED_TABLES: readonly AuditedTable[] = [
	{
		table: 'account',
		columns: [
			'id',
			'name',
			'kind',
			'min_balance',
			'sort_order',
			'archived_at',
			'purpose',
			'currency',
			'icon',
			'image_id'
		],
		account: 'id',
		amount: '',
		// The label is typed by the person (24 characters, no long digit runs), so it is safe to copy. The icon is a catalogue key and image_id an id: the picture bytes are never copied
		firstColumns: ['id', 'name', 'kind', 'min_balance', 'sort_order', 'archived_at'],
		redefinitions: [
			{
				migration: '0022',
				columns: ['id', 'name', 'kind', 'min_balance', 'sort_order', 'archived_at', 'purpose']
			},
			{
				migration: '0025',
				columns: [
					'id',
					'name',
					'kind',
					'min_balance',
					'sort_order',
					'archived_at',
					'purpose',
					'currency'
				]
			},
			{
				migration: '0041',
				columns: [
					'id',
					'name',
					'kind',
					'min_balance',
					'sort_order',
					'archived_at',
					'purpose',
					'currency',
					'icon',
					'image_id'
				]
			}
		]
	},
	{
		table: 'account_wallet',
		columns: ['id', 'account_id', 'currency'],
		account: 'account_id',
		amount: '',
		migration: '0025'
	},
	{
		table: 'ledger_txn',
		columns: [
			'id',
			'type',
			'account_id',
			'to_account_id',
			'amount',
			'fee',
			'category',
			'note',
			'occurred_at',
			'source',
			'bill_id',
			'split_id',
			'voided_at',
			'currency',
			'to_currency',
			'to_amount'
		],
		account: 'account_id',
		amount: 'txn',
		firstColumns: [
			'id',
			'type',
			'account_id',
			'to_account_id',
			'amount',
			'fee',
			'category',
			'note',
			'occurred_at',
			'source',
			'bill_id',
			'split_id',
			'voided_at'
		],
		// The currency of a row travels inside the hashed before and after, so the chain covers it
		redefinitions: [
			{
				migration: '0025',
				columns: [
					'id',
					'type',
					'account_id',
					'to_account_id',
					'amount',
					'fee',
					'category',
					'note',
					'occurred_at',
					'source',
					'bill_id',
					'split_id',
					'voided_at',
					'currency',
					'to_currency',
					'to_amount'
				]
			}
		]
	},
	{
		table: 'balance_snapshot',
		columns: ['id', 'account_id', 'amount', 'taken_at', 'expected_amount', 'source', 'currency'],
		account: 'account_id',
		amount: '',
		firstColumns: ['id', 'account_id', 'amount', 'taken_at', 'expected_amount', 'source'],
		redefinitions: [
			{
				migration: '0025',
				columns: ['id', 'account_id', 'amount', 'taken_at', 'expected_amount', 'source', 'currency']
			}
		]
	},
	{
		table: 'bill',
		columns: [
			'id',
			'name',
			'category',
			'account_id',
			'kind',
			'amount',
			'schedule',
			'weekend_rule',
			'deferrable',
			'active',
			'starts_on',
			'currency',
			'icon',
			'image_id'
		],
		account: 'account_id',
		amount: '',
		// The first day the bill counts is a date the person chose, so it is safe to copy
		firstColumns: [
			'id',
			'name',
			'category',
			'account_id',
			'kind',
			'amount',
			'schedule',
			'weekend_rule',
			'deferrable',
			'active'
		],
		redefinitions: [
			{
				migration: '0023',
				columns: [
					'id',
					'name',
					'category',
					'account_id',
					'kind',
					'amount',
					'schedule',
					'weekend_rule',
					'deferrable',
					'active',
					'starts_on'
				]
			},
			{
				migration: '0025',
				columns: [
					'id',
					'name',
					'category',
					'account_id',
					'kind',
					'amount',
					'schedule',
					'weekend_rule',
					'deferrable',
					'active',
					'starts_on',
					'currency'
				]
			},
			{
				migration: '0041',
				columns: [
					'id',
					'name',
					'category',
					'account_id',
					'kind',
					'amount',
					'schedule',
					'weekend_rule',
					'deferrable',
					'active',
					'starts_on',
					'currency',
					'icon',
					'image_id'
				]
			}
		]
	},
	{
		table: 'bill_payment',
		columns: [
			'id',
			'bill_id',
			'due_date',
			'window_start',
			'window_end',
			'amount',
			'txn_id',
			'currency',
			'paid_currency',
			'paid_amount'
		],
		account: '',
		amount: '',
		firstColumns: ['id', 'bill_id', 'due_date', 'window_start', 'window_end', 'amount', 'txn_id'],
		redefinitions: [
			{
				migration: '0025',
				columns: [
					'id',
					'bill_id',
					'due_date',
					'window_start',
					'window_end',
					'amount',
					'txn_id',
					'currency',
					'paid_currency',
					'paid_amount'
				]
			}
		]
	},
	{
		table: 'bill_override',
		columns: [
			'id',
			'bill_id',
			'original_due_date',
			'new_due_date',
			'amount',
			'account_id',
			'skipped'
		],
		account: 'account_id',
		amount: '',
		migration: '0018'
	},
	{
		table: 'goal',
		columns: ['id', 'name', 'account_id', 'target_amount', 'per_payday', 'active'],
		account: 'account_id',
		amount: ''
	},
	{
		table: 'allocation_rule',
		columns: [
			'id',
			'position',
			'mode',
			'amount',
			'basis_points',
			'base',
			'target_account_id',
			'target_goal_id',
			'effective_from',
			'status',
			'approved_at',
			'label',
			'funds_bill_id'
		],
		account: 'target_account_id',
		amount: '',
		firstColumns: [
			'id',
			'position',
			'mode',
			'amount',
			'basis_points',
			'base',
			'target_account_id',
			'target_goal_id',
			'effective_from',
			'status',
			'approved_at'
		],
		// The label is a short name the person or the assistant chose, so it is safe to copy
		redefinitions: [
			{
				migration: '0032',
				columns: [
					'id',
					'position',
					'mode',
					'amount',
					'basis_points',
					'base',
					'target_account_id',
					'target_goal_id',
					'effective_from',
					'status',
					'approved_at',
					'label'
				]
			},
			// The bill a rule saves for is an id the person or the assistant chose (BTL-20261029-0119)
			{
				migration: '0033',
				columns: [
					'id',
					'position',
					'mode',
					'amount',
					'basis_points',
					'base',
					'target_account_id',
					'target_goal_id',
					'effective_from',
					'status',
					'approved_at',
					'label',
					'funds_bill_id'
				]
			}
		]
	},
	{
		table: 'income_schedule',
		columns: ['id', 'label', 'account_id', 'expected_amount', 'schedule', 'weekend_rule', 'active'],
		account: 'account_id',
		amount: ''
	},
	{
		table: 'split_plan',
		columns: [
			'id',
			'income_schedule_id',
			'payday',
			'pay',
			'status',
			'gap',
			'approved_at',
			'approved_by'
		],
		account: '',
		amount: ''
	},
	{
		table: 'task',
		columns: ['id', 'status', 'priority', 'due_at', 'follow_up_at', 'source', 'done_at'],
		account: '',
		amount: ''
	},
	{
		table: 'calendar_event',
		columns: ['id', 'starts_at', 'ends_at', 'all_day', 'source', 'ref_key', 'deleted_at'],
		account: '',
		amount: ''
	},
	{
		table: 'routine',
		columns: ['id', 'recurrence', 'lead_minutes', 'active'],
		account: '',
		amount: ''
	},
	{
		table: 'reminder',
		columns: ['id', 'kind', 'ref_key', 'remind_at', 'status', 'origin'],
		account: '',
		amount: ''
	},
	{
		table: 'user_setting',
		columns: [
			'id',
			'currency',
			'language',
			'reply_language',
			'week_starts_on',
			'model_provider',
			'show_net_balance',
			'photo_mode',
			'time_zone',
			'time_format',
			'date_style'
		],
		account: '',
		amount: '',
		firstColumns: ['id', 'currency', 'language', 'reply_language', 'week_starts_on'],
		// Which host receives the person's chat is a choice worth a trail: only the provider name is copied
		redefinitions: [
			{
				migration: '0029',
				columns: [
					'id',
					'currency',
					'language',
					'reply_language',
					'week_starts_on',
					'model_provider'
				]
			},
			{
				migration: '0035',
				columns: [
					'id',
					'currency',
					'language',
					'reply_language',
					'week_starts_on',
					'model_provider',
					'show_net_balance'
				]
			},
			{
				migration: '0036',
				columns: [
					'id',
					'currency',
					'language',
					'reply_language',
					'week_starts_on',
					'model_provider',
					'show_net_balance',
					'photo_mode'
				]
			},
			{
				migration: '0047',
				columns: [
					'id',
					'currency',
					'language',
					'reply_language',
					'week_starts_on',
					'model_provider',
					'show_net_balance',
					'photo_mode',
					'time_zone',
					'time_format',
					'date_style'
				]
			}
		]
	},
	{
		table: 'agent_action',
		columns: ['id', 'verb', 'status', 'turn_id', 'expires_at', 'decided_at'],
		account: '',
		amount: ''
	},
	// -- HEALTH (0045) -- //
	// Numbers, ids, dates and source codes only. A food name, a label, a note or a nutrient map can come from a photo or a product database, so it is never copied
	{
		table: 'health_profile',
		columns: ['id', 'height_mm', 'birth_year', 'sex', 'activity', 'setup_done_at'],
		account: '',
		amount: '',
		migration: '0045'
	},
	{
		table: 'health_goal',
		columns: ['id', 'kind', 'goal_weight_g', 'pace_bp', 'target_kcal', 'protein_tenths'],
		account: '',
		amount: '',
		migration: '0045'
	},
	{
		table: 'food_item',
		columns: ['id', 'source', 'kcal', 'serving_g', 'archived_at'],
		account: '',
		amount: '',
		migration: '0045'
	},
	{
		table: 'food_entry',
		columns: [
			'id',
			'day',
			'meal',
			'grams',
			'kcal',
			'low_kcal',
			'high_kcal',
			'source_kind',
			'food_item_id'
		],
		account: '',
		amount: '',
		migration: '0045'
	},
	{
		table: 'day_status',
		columns: ['id', 'day', 'complete'],
		account: '',
		amount: '',
		migration: '0045'
	},
	{
		table: 'weight_entry',
		columns: ['id', 'day', 'grams'],
		account: '',
		amount: '',
		migration: '0045'
	},
	{
		table: 'energy_estimate',
		columns: [
			'id',
			'week_key',
			'trend_g',
			'burn_kcal',
			'intake_kcal',
			'complete_days',
			'weigh_ins'
		],
		account: '',
		amount: '',
		migration: '0045'
	},
	{
		table: 'health_proposal',
		columns: ['id', 'kind', 'week_key', 'status', 'answered_at'],
		account: '',
		amount: '',
		migration: '0045'
	},
	{
		table: 'program',
		columns: ['id', 'template_key', 'started_on', 'stopped_at', 'week'],
		account: '',
		amount: '',
		migration: '0045'
	},
	{
		table: 'planned_workout',
		columns: [
			'id',
			'program_id',
			'day',
			'starts_at',
			'minutes',
			'kind',
			'session_key',
			'status',
			'week_key'
		],
		account: '',
		amount: '',
		migration: '0045'
	},
	{
		table: 'workout_session',
		columns: [
			'id',
			'planned_id',
			'program_id',
			'day',
			'kind',
			'minutes',
			'distance_m',
			'finished_at'
		],
		account: '',
		amount: '',
		migration: '0045'
	},
	{
		table: 'workout_set',
		columns: ['id', 'session_id', 'exercise_key', 'position', 'reps', 'seconds', 'done'],
		account: '',
		amount: '',
		migration: '0045'
	},
	{
		table: 'sleep_entry',
		columns: ['id', 'day', 'starts_at', 'ends_at', 'nap'],
		account: '',
		amount: '',
		migration: '0045'
	},
	{
		table: 'weekly_block',
		columns: ['id', 'weekday', 'start_minute', 'end_minute', 'kind'],
		account: '',
		amount: '',
		migration: '0045'
	},
	{
		table: 'availability_override',
		columns: ['id', 'day', 'off'],
		account: '',
		amount: '',
		migration: '0045'
	},
	{
		table: 'availability_setting',
		columns: ['id', 'wake_start_minute', 'wake_end_minute', 'travel_minutes', 'wind_down'],
		account: '',
		amount: '',
		migration: '0045'
	}
];

/** Tenant tables that are not audited, and why. A table on neither list fails the registry test. */
export const EXEMPT_FROM_AUDIT: Record<string, string> = {
	audit_event: 'it is the trail itself',
	device: 'push registration, no money or plan',
	model_usage: 'a counter of model calls',
	request_log: 'idempotency bookkeeping',
	undo_journal: 'bookkeeping for undo; the changes it undoes are audited',
	chat_turn: 'the chat transcript, which holds message text and is never copied elsewhere',
	chat: 'a conversation; its title can be message text, so it is kept out of the trail like the transcript',
	memory_fact: 'memory has its own provenance, editing and wipe',
	memory_profile: 'memory has its own provenance, editing and wipe',
	memory_summary: 'memory has its own provenance, editing and wipe',
	notebook:
		'personal text with its own revisions (who changed it, and the text it replaced) and its own wipe, kept out of the trail like the transcript',
	notebook_revision: 'the revisions of the notebook: the notebook is the history, not the trail',
	notebook_page:
		'personal text with its own revisions (who changed it, and the text it replaced) and its own wipe, kept out of the trail like the notebook it belongs to',
	notebook_page_revision: 'the revisions of a page: the page is the history, not the trail',
	picture:
		'image bytes that mark an account or a bill; the owning row is audited with its icon and image id, the bytes are never copied into the trail'
};

// -- AUDIT -- //

export const auditEvent = userTable(
	'audit_event',
	() => user.id,
	{
		id: id(),
		/** 1, 2, 3 ... per person. The order of the chain and of the history. */
		seq: bigint('seq', { mode: 'number' }).notNull(),
		/** The start of the transaction. Two rows of one change share it, so the order is the sequence, never this. */
		at: timestamp('at', { withTimezone: true }).notNull().defaultNow(),
		actorKind: text('actor_kind', { enum: AUDIT_ACTOR_KINDS }).notNull(),
		/** 'agent' when a person approved a card the assistant proposed: the assistant asked, the person did it. */
		onBehalf: text('on_behalf'),
		/** The assistant's tool, the job kind or a short reference. Never message text. */
		actorRef: text('actor_ref'),
		channel: text('channel', { enum: AUDIT_CHANNELS }).notNull(),
		verb: text('verb'),
		entity: text('entity').notNull(),
		entityId: text('entity_id').notNull(),
		/** The account the row belongs to. Not a foreign key: the trail outlives an account that a reset deletes. */
		accountId: uuid('account_id'),
		action: text('action', { enum: AUDIT_ACTIONS }).notNull(),
		/** The effect on the account's balance of a ledger row, signed. */
		amountDelta: bigint('amount_delta', { mode: 'number' }),
		before: jsonb('before'),
		after: jsonb('after'),
		note: text('note'),
		requestId: text('request_id'),
		approvalId: text('approval_id'),
		turnId: text('turn_id'),
		undoOf: text('undo_of'),
		prevHash: text('prev_hash'),
		hash: text('hash').notNull()
	},
	(t) => [
		unique('audit_event_user_seq_uq').on(t.userId, t.seq),
		index('audit_event_account_idx').on(t.userId, t.accountId, t.seq.desc()),
		oneOf('audit_event_actor_chk', t.actorKind, AUDIT_ACTOR_KINDS),
		oneOf('audit_event_channel_chk', t.channel, AUDIT_CHANNELS),
		oneOf('audit_event_action_chk', t.action, AUDIT_ACTIONS)
	],
	{ appendOnly: true }
);
