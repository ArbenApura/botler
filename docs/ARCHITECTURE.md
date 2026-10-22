# Botler architecture

Summary of the decisions on plan BTL-20261021-0458 (https://afb.arbenger.com/arbenger/BTL/BTL-20261021-0458). The board is the plan of record; this file is the short version for people opening the repo.

## Shape

```
Flutter app (Android) <--HTTPS--> SvelteKit server (botler.arbenger.com) --> PostgreSQL + pgvector
                                        |-- ops layer (one set of verbs)
                                        |-- agent loop --> DeepSeek (through the proxy)
                                        |-- memory layers and jobs
                                        '-- FCM push
```

- **App** (`app/`): Flutter, Android first. Chat-first single screen with a summary card. Reminders and alarms are scheduled on the phone so they work offline; a sync contract replaces them when the server changes. Writes go through an on-device outbox with a client `requestId`.
- **Server** (`server/`): SvelteKit 3, Svelte 5 runes, TypeScript strict, Drizzle, Better Auth with Google sign-in (closed to an allow-list).
- **Database**: its own PostgreSQL 17 with pgvector, in its own container and volume on the VPS. Every table has `user_id`; forced row level security is generated from a registry; requests run as the non-owning `app_runtime` role inside a transaction-local tenant context.
- **One operations layer**: the HTTP API, the agent tools and the background jobs call the same verbs. Writes are idempotent by `requestId`. Verbs are `free` (record) or `gated` (change the money plan); a gated verb needs an `approvalId` minted only by a user-authenticated HTTP call.

## Money

PHP, integer centavos, Asia/Manila dates. Ledger types: income, expense, transfer (with fee), refund, adjustment. Balance = latest snapshot + signed transactions since it. The payday split is proposed by the agent and approved by the user; a shortfall is shown and the user chooses what to cut. Allocation rules: fixed peso, percentage or the rest, in forms or plain words (parsed, shown, approved). A split always sums exactly to the pay.

### Currency, schedules, calendar and audit

- **Settings**: one `user_setting` row per person (currency, language, reply language, week start). Money is formatted and parsed only by `finance/currency.ts` (server) and `core/money.dart` (app); a currency change never converts amounts.
- **Schedules**: `finance/schedule.ts` models monthly (with last day and every N months), semi-monthly, every N days, weekly, nth weekday, week of month, day range and yearly. Every occurrence is a window `{start, end}`; a single day has start equal to end and the end is the due date. A payment stores its window and matches by overlap, so editing a schedule never makes a paid window look unpaid. Paydays accept single-day kinds only.
- **One due date changed on its own** (BTL-20261022-0650): `bill_override` holds a change to a single due date of a bill, keyed by the date its schedule gives (`original_due_date`): moved up to 31 days, another amount, another paying account, or skipped. The bill, its payments and its other dates stay as they are. `finance/occurrence.ts` (`effectiveOccurrences`, pure) is the one place that applies overrides, and every reader of a bill's dates goes through it via `dueBills` (the Bills screen, the payday split, reminders, the calendar, sync) and `markBillPaid`, which stores the effective window. The free verbs `bill_occurrence_update` (merge: a left-out field keeps its value, null clears it) and `bill_occurrence_reset` are available to the assistant; an amount on a bill whose amount varies turns into an approval card, and a paid date is corrected in the ledger, not here. `bill_update` (all dates) drops the overrides from today on that a new schedule, weekend rule, amount or account replaces, and says how many (`clearedOverrides`). Migration 0018 also carries the audit trigger and the newer `data_reset` function; 0016 and 0017 stay as they ran, and their tests pin them.
- **Calendar** (Botler's own; the Google Calendar sync was removed in BTL-20261022-1311, migration 0019 drops its table and columns): the read verb `calendar_range` (at most 92 days) returns bills as windows, paydays, events, routines, tasks and reminders, plus a labelled estimate of each account's balance over the days. The app draws month, week and agenda views from it and keeps the last range for offline.
- **Audit**: triggers on 16 tenant tables write `audit_event` rows in the same transaction, with actor, channel, approval and turn read from transaction-local settings. `account_history` replays a running balance; `audit_verify` walks the chain; `audit_export` is person-only. `data_reset` erases by scope through a SECURITY DEFINER function and leaves one tombstone row.
- **Live chat** (BTL-20261022-0738): `POST /api/v1/agent/chat` answers as server-sent events. Kept with a finished message and replayed: `tool`, `card`, `fallback` (the `STORED` allow-list in `agent/chat.ts`). Live only, never stored, replayed or logged: `start` (sent as soon as the message is claimed, before memory or the model), `phase` (`thinking` at the start of each model call, `writing` at its first word), `reasoning` (the model's thinking), `tool_start` (`{id, name}` only, never the arguments; every one gets a `tool` event with the same `id`). Then `delta`, `done` and `error` as before. A `: ping` comment goes out every 10 s so the phone can tell a quiet stream from a dead one (the app gives up after 45 s of nothing). A claim error (a reused id, bad input) is still an ordinary HTTP error: the claim and the first event happen before the Response exists. The response says `content-encoding: identity` and `no-transform`, and the Caddy site block compresses only listed types, because a compressing proxy holds small pieces back. Thinking is on when `DEEPSEEK_THINKING` is not 0/false and only for the streamed chat bucket (never memory jobs); it asks DeepSeek for `thinking`, raises `max_tokens` to 8192 (thinking shares it with the answer), sends no temperature, and counts against the monthly cap. `reasoning_content` goes back to DeepSeek in later tool rounds like content: kept with real values restored (`Completion.reasoningRaw`) and masked again by `maskMessages` with the turn's masker, so the placeholders are the same ones DeepSeek saw (masking the wire text itself would rewrite `[NAME_1]` into `[NAME-1]`). A round cut off by the limit (`finish_reason: length`) never runs its tool calls; it ends with `stopped: 'length'`, is stored as failed and is not read for memory.
- **Chat history** (BTL-20261022-0827): the chat is empty on every app start unless the app asks, because the screen state lives only in memory while every turn is already stored in `chat_turn`. `chat_history` (registry kind `person`, so the assistant is never offered it; `limit` 1 to 30, default 20) is a plain read inside the tenant context: no model call, no tokens, and the model's own prompt is unchanged (it keeps its bounded history in `agent/chat.ts`: 10 finished turns, 1500 characters each; `tests/agent/history.test.ts` pins that). It returns the newest turns oldest first, never a running turn, with `clientMessageId` and `status`; stored events are validated one by one (an odd one is skipped, never the call), at most 12 per turn, tool `data` over 4000 characters dropped, the whole answer kept under about 200 KB (old tool data goes first, then the oldest turns). A card event carries the action's status now (`pending`, `applied`, `rejected`, `failed`, `expired`, or `gone` for a missing action); a pending card past its time is reported `expired` although nothing wrote that yet. The app calls it once per run from the chat screen (`ChatNotifier.restore()`, flag in the notifier, reset when another person signs in), keeps the result apart from the live items, shows it read-only (no Undo, no figures that are not in the stored data, only a live pending card answerable) and drops a turn it already sent in this run. A photo message comes back as its typed text only; thinking is never stored, so none comes back.

### Egress wall

The fetch tool refuses private addresses in code, and `deploy/vps/egress.sh` is the second wall: a firewall inside botler-app's own network namespace that rejects new connections to private, link-local (metadata) and carrier-grade ranges and to the Docker host, with one exception, tcp 5432 on botler-db. It works inside the container because AFB's app shares a Docker network with botler-app and the host firewall cannot see same-network traffic. `deploy/vps/egress-test.sh` proves it from inside the container. It runs after every deploy (`deploy.ps1`) and on reboot (cron `@reboot`).

## Agent

DeepSeek tool calling behind a proxy (key only in server env, per-user and global spend caps, separate chat and memory budgets). The caller identity is injected by the loop. Web text, other people's calendar text and OCR text are untrusted: after they enter a turn, writes are disabled or forced through approval. The fetch tool blocks private addresses. The DeepSeek payload carries amounts and labels, never account numbers.

## Memory

Own it on Postgres: a core profile always in the prompt (stable prefix for DeepSeek caching), a transcript archive, facts with `valid_from`/`valid_to`, source and suppressed flag, a pgvector + full-text hybrid retrieval weighted by recency and importance, daily/weekly/monthly summaries, a night job, and a bounded mood state that changes tone only. Embeddings come from a small multilingual model on the VPS chosen by a Taglish test. The user can see, edit and delete any memory; wipe covers transcripts, summaries, facts and embeddings.

## Decisions

See ADR 1 to 5 and settled decision 1 on the item: Flutter + SvelteKit + own Postgres; memory on Postgres (not Mem0 or Graphiti); autonomy, payday and rules; privacy and internet access; and the plan-critic amendments.

## Run

Local dev ports: server 5280, preview 5290, Postgres 5434. The VPS layout is in the gitignored `VPS.md`.
