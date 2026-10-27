# botler rules

Botler is a personal AI butler for finance and scheduling: a Flutter Android app (`app/`) and a SvelteKit backend (`server/`, Svelte 5 runes, TypeScript strict, Drizzle, Better Auth, Tailwind 4 for the few server pages) on its own PostgreSQL with pgvector. The agent runs on the DeepSeek API through a proxy in `server/`. One operations layer behind the HTTP API and the agent tools. Plans live on Agent Flow Board (project BTL, https://afb.arbenger.com/arbenger/BTL) and are read and written through its MCP by the `/flow` skills. The first plan is BTL-20261021-0458. This file is the working rulebook.

## Git and safety

- Never run `git push` unless the user asks. Never commit unless the user asks. All work stays in the local working tree.
- Work on the checked out branch (`git branch --show-current`, `main`). Never create or switch branches unless told to.
- Never add co-author trailers or AI attribution to a commit message, pull request or note.
- Never delete `node_modules` or `.git` when cleaning up. Delete only the exact files you made.
- Package manager for `server/` is Yarn 4 (`.yarnrc.yml`, `nodeLinker: node-modules`, the program is `.yarn/releases/`), never `npm` or `pnpm`. Commit `yarn.lock`. Never commit `package-lock.json` or `pnpm-lock.yaml`. The Flutter app uses `flutter pub` and commits `pubspec.lock`.
- `VPS.md` and every `.env*` are gitignored. Never put a secret in a command line, a log, a commit, the app binary or CI. Never print a token.
- **This repo shares a VPS and a laptop with Agent Flow Board (AFB). Never touch AFB's containers, databases, volumes or ports**: not `5433` (its local Postgres), not its compose project. Never suggest or run `docker compose down -v`, removing a volume, `DROP DATABASE` or a database reset on anything that holds data the user wants to keep. For tests use a throwaway Postgres (a new container with its own volume, or the embedded one), and ask before any destructive step.
- Anything that reaches the VPS, Cloudflare or a Google console (creating the container or a port, the DNS record, the OAuth client, editing AFB's Caddyfile, a deploy, a restore) is confirmed with the user immediately before. See `VPS.md`.

## Flow plans and running sessions

- Keep the plan on the board in sync with the code at all times. Record every finished step with `step_done` as you finish it, before the next one, and keep status, decisions and the resume note true.
- A claimed item shows a "running" badge until released or 120 minutes pass without a heartbeat. Call `work_stop` after the last step, when you hand the work back and before moving to another item. Never end a session with a claim held.
- Work that belongs to no item is not claimed. Before asking for sign-off run `/flow-audit`.
- No UI CHANGES tables, mockup files, Playwright or browser automation in plans (the owner looks at screens himself).

## Local development

- Ports: Botler server dev **5280**, preview **5290**, local Postgres container `botler-pg-dev` on **5434** with its own volume. Never use 5173, 5180, 5190 or 5433 (AFB's). If a port is busy, find what holds it and ask before stopping it.
- Never point a dev server, seed or test at the AFB database or the VPS database, and never put a `DATABASE_URL` with a real password in a command line or a log.

## The gates

After each finished change, from the repo root:

1. `server/`: `yarn check`, then `yarn eslint <files>` and `yarn prettier --check <files>` on the files you changed (`yarn prettier --write <file>` for your own files only), then `yarn vitest run <path>`. Full `yarn test` at the end of a phase.
2. `app/`: `flutter analyze`, `dart format --set-exit-if-changed <files>`, `flutter test <path>`. Full `flutter test` at the end of a phase.
3. Checks run against a build or preview, never a dev server. Every phase ends with a counted gate step.

## Money, time and data rules

- Each person has a MAIN currency (`user_setting`, default PHP, any of the ~155 ISO currencies in `finance/currency.ts`) and time zone Asia/Manila. An account holds one WALLET per currency (`account_wallet`; `ledger_txn` and `balance_snapshot` carry a `currency`), and a bill has its own currency. Amounts are integer minor units of their own currency (centavos for PHP, whole yen for JPY, fils for KWD) everywhere (database as 64 bit, API, Dart). Format and parse only through `finance/currency.ts` and `core/money.dart`. Never floats for money. Dates that mean "a day" are Manila calendar dates.
- Amounts of different currencies are never added. A total converts each wallet with the stored exchange rates (`finance/fx.ts`, integer maths, rates as decimal text in `fx_rate`, fetched from the fixed https `FX_RATES_URL`); a wallet with no rate is named and left out, never counted as zero. The money plan (income, goals, rules, minimum balance, the split) is in the main currency and uses an account's main currency wallet; a bill in another currency is counted in the split at the stored rate, rounded up, and the rate is kept with the plan. Changing the main currency relabels the plan amounts and converts nothing but totals.
- A split always sums exactly to the pay. Percent splits put the remainder on the "rest" target or the first rule, deterministically.
- Balance = latest snapshot plus signed transactions since it. A transfer between own accounts is never spending.
- Amounts read from a photo or screenshot, and large balance changes, are confirmed by the user before saving.
- Every write verb takes a client `requestId` (unique per user) and a replay returns the first result.

## Audit and data reset

- Every write to a person's tables is captured by database triggers into the append-only `audit_event` table (per-person `seq` and hash chain). A verb body can never skip it; a new tenant table is either audited or on the written exempt list, and a test fails otherwise. `audit_event` is never edited or deleted by the app.
- Resetting a balance is `snapshot_record` with `mode: 'reset'` and a reason: the history stays and the difference is a reset, not spending. Nothing deletes history to "set a balance".
- `data_reset` is person-only: a single-use token from `data_reset_preview`, the typed word and the phone's lock. It is never in an agent tool schema and never behind an approval card.

## Agent, privacy and untrusted text

- The agent records freely (expenses, tasks, events, reminders) and edits what already exists freely (`account_update`, `bill_update`, `goal_update`, `income_update`: names, amounts, the linked account; owner decision 2026-10-22, the audit trail names the agent as actor). It asks before adding to or removing from the money plan (new account, bill, goal or payday, removing a goal with `goal_delete`, hiding an account) and before a balance count. The gated verb list lives in the ops layer. A gated verb needs an `approvalId` minted only by a user-authenticated HTTP call; the model can never mint one.
- The caller (user id) is injected server-side. Tool schemas never contain `user_id` or tenant columns.
- DeepSeek gets amounts and labels, never account numbers; family names are masked. The filter runs on the final assembled prompt (memories and tool results included).
- Text from the web, other people's calendars, OCR or anything fetched is untrusted data. After it enters a turn, write verbs in that turn are disabled or forced through approval. Facts are extracted only from the user's own turns.
- The fetch tool blocks private, loopback, link-local and metadata addresses and re-checks every redirect. Never put memory text in a fetched URL.
- Logs and error reports never hold message text. Secrets are never returned by an API, a tool or an export.
- Botler's Notebook is one Markdown document per person, always in the prompt as the second system message (frozen for the whole message). The person edits it (the whole text, saved from the version they opened, a stale one refused); the agent edits it only with `notebook_edit` (add a line under a heading, replace or remove exact text), and in a turn that read untrusted text that becomes an approval card showing the words. Every change keeps the replaced text as a revision (newest 50). Never balances, account numbers or text from the web, a photo or someone else's calendar in it, and it never changes what needs approval. `memory_*` and `profile_*` verbs are app-only (`agent: false`, kept for older apps); the fact pipeline (extractor, digests, embedder) is retired and old facts stay unused.
- Sums beyond one small addition go through `calc` and forecasts through `cashflow_forecast`: the model quotes their numbers and never adds bills or balances by hand. Thinking blocks are never masked again, never stored and never in history.

## Server rules

- One operations layer (`server/src/lib/server/ops/`). The HTTP API, the agent tools and the jobs all call it. A verb checks the caller's live identity itself.
- Every query runs inside the transaction-local tenant context (`set_config(..., true)` with the user id), connected as the non-owning `app_runtime` role. Never query with the owner role from request code. Every table registers with the tenant registry so forced RLS is generated; a test fails on any table without it.
- Every background job carries its user id and sets the tenant context before its first query. Jobs are rows with a unique key, retry with backoff, and count against the model-call budget when they call the model (a job such as `fx.refresh` that makes no model call is outside it).
- Validate every form and payload with Zod schemas generated from the Drizzle tables.
- Missing configuration fails loudly. No silent fail-open paths. Registration is closed to an allow-list.

## Colour and theme (app and server pages)

- Light and dark both exist. Style: **calm paper** (warm off-white, deep warm charcoal in dark, one soft sage accent, fixed danger/warning/success/info colours that never come from the accent). Every colour is a token: in Dart a `BotlerColors` theme extension, in Svelte a CSS variable. Never write a literal colour in a widget or component (`Color(0xFF…)`, `#fff`, `bg-white`). The scale and layout rules are in `docs/DESIGN.md`.
- One primary action per view. Tap targets at least 48 dp (44 px on web). Numbers use tabular figures. Short gentle motion only.

## Svelte and TypeScript style (server/)

- Svelte 5 runes only (`$state`, `$derived`, `$props`, `$effect`). No `export let`, no `$:`. Zero `<style>` blocks; Tailwind utilities on the element. TypeScript strict: no `any`, no unchecked null, no `@ts-ignore` without a reason.
- Comments: section headers and dividers UPPERCASE (`// -- STATES -- //`), notes in sentence case. Never remove existing comments.
- Imports in nine groups in this order with no blank lines: `// -- ASSETS -- //`, DEP-TYPES, TYPES, ENVS, CONSTANTS, DEP-MODULES, MODULES, DEP-COMPONENTS, COMPONENTS. Component sections in order: REQUIRED PROPS, OPTIONAL PROPS, DEBUGGING, TYPES, CONSTANTS, STATES, PERSISTED STORES, STORES, REACTIVE STATES, REACTIVE STATEMENTS, FUNCTIONS, SUBSCRIPTIONS, LIFECYCLES. Load `/coding-guidelines` before any Svelte, TypeScript or CSS change.

## Dart style (app/)

- Same spirit as above: `analysis_options.yaml` strict (`strict-casts`, `strict-inference`, `strict-raw-types`), no `dynamic`, sound null safety, no `!` without a reason comment. Small widgets, one concern each. Same uppercase section comments (`// -- STATES -- //`) and never remove existing comments. State lives in one state-management library chosen in P6.1; no business rules in widgets, they call the API.
- Every tappable widget has a semantic label. Secrets only in secure storage. Offline writes go through the outbox with a `requestId`.

## Where things live

`server/src/lib/server/ops/` verbs (and `registry.ts`, the one list of every verb with its class: read, free, gated, person), `server/src/lib/finance/` and `server/src/lib/schedule/` pure money and time rules (no database), `server/src/lib/server/db/` schema, RLS and migrations, `server/src/lib/server/auth/`, `server/src/lib/server/agent/` loop, tools, approval cards and fetch guard, `server/src/lib/server/notebook/` the notebook text rules (add, replace, remove, first draft) with `ops/notebook.ts` its verbs, `server/src/lib/server/memory/` the retired fact memory (kept for the old verbs and export), `server/src/lib/server/agent/transcript.ts` and `compact.ts` the stored tool rounds and the long-chat history and summary, `server/src/lib/finance/calc.ts` and `forecast.ts` the calculator and the cash-flow forecast (`ops/calc.ts`, `ops/forecast.ts` their verbs), `server/src/lib/server/jobs/` the job queue and its handlers (chat summary, notebook seed, push, fx), `server/src/lib/server/calendar/` Google Calendar sync, `server/src/lib/server/push/` Firebase push, `server/src/lib/server/schedule/` the reminder engine, `server/src/lib/server/proxy/` DeepSeek proxy, `app/lib/` Flutter code (`core/` server client and outbox, `state/` providers, `features/` screens, `theme/tokens.dart` the only file with literal colours), `docs/` architecture, design and `ANDROID.md`, `deploy/vps/` compose files for the VPS and `release-app.ps1` (publishes an Android build for the in-app update), `server/src/lib/app-update/` and `server/src/lib/server/appUpdate/` the update rules and the two update endpoints, `app/lib/core/app_update.dart` with `state/update.dart` and `features/update/` the in-app update, `app/assets/changelog.json` with `app/lib/core/changelog.dart` the "What's new" notes shown once after an update (a version bump needs an entry in `en` and `fil`; `release-app.ps1` refuses a build without one).

Two rules that came out of building it: a plain foreign key does not go through row level security, so every reference between a person's tables is a composite (user_id, id) key; and a zod `.default()` inside a field that is later `.partial()`-ed resets the column on every update, so defaults belong to the database column.
