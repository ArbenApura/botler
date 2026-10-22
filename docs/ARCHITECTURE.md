# Botler architecture

Summary of the decisions on plan BTL-20261021-0458 (https://afb.arbenger.com/arbenger/BTL/BTL-20261021-0458). The board is the plan of record; this file is the short version for people opening the repo.

## Shape

```
Flutter app (Android) <--HTTPS--> SvelteKit server (botler.arbenger.com) --> PostgreSQL + pgvector
                                        |-- ops layer (one set of verbs)
                                        |-- agent loop --> DeepSeek (through the proxy)
                                        |-- memory layers and jobs
                                        '-- Google Calendar, FCM push
```

- **App** (`app/`): Flutter, Android first. Chat-first single screen with a summary card. Reminders and alarms are scheduled on the phone so they work offline; a sync contract replaces them when the server changes. Writes go through an on-device outbox with a client `requestId`.
- **Server** (`server/`): SvelteKit 3, Svelte 5 runes, TypeScript strict, Drizzle, Better Auth with Google sign-in (closed to an allow-list).
- **Database**: its own PostgreSQL 17 with pgvector, in its own container and volume on the VPS. Every table has `user_id`; forced row level security is generated from a registry; requests run as the non-owning `app_runtime` role inside a transaction-local tenant context.
- **One operations layer**: the HTTP API, the agent tools and the background jobs call the same verbs. Writes are idempotent by `requestId`. Verbs are `free` (record) or `gated` (change the money plan); a gated verb needs an `approvalId` minted only by a user-authenticated HTTP call.

## Money

PHP, integer centavos, Asia/Manila dates. Ledger types: income, expense, transfer (with fee), refund, adjustment. Balance = latest snapshot + signed transactions since it. The payday split is proposed by the agent and approved by the user; a shortfall is shown and the user chooses what to cut. Allocation rules: fixed peso, percentage or the rest, in forms or plain words (parsed, shown, approved). A split always sums exactly to the pay.

## Agent

DeepSeek tool calling behind a proxy (key only in server env, per-user and global spend caps, separate chat and memory budgets). The caller identity is injected by the loop. Web text, other people's calendar text and OCR text are untrusted: after they enter a turn, writes are disabled or forced through approval. The fetch tool blocks private addresses. The DeepSeek payload carries amounts and labels, never account numbers.

## Memory

Own it on Postgres: a core profile always in the prompt (stable prefix for DeepSeek caching), a transcript archive, facts with `valid_from`/`valid_to`, source and suppressed flag, a pgvector + full-text hybrid retrieval weighted by recency and importance, daily/weekly/monthly summaries, a night job, and a bounded mood state that changes tone only. Embeddings come from a small multilingual model on the VPS chosen by a Taglish test. The user can see, edit and delete any memory; wipe covers transcripts, summaries, facts and embeddings.

## Decisions

See ADR 1 to 5 and settled decision 1 on the item: Flutter + SvelteKit + own Postgres; memory on Postgres (not Mem0 or Graphiti); autonomy, payday and rules; privacy and internet access; and the plan-critic amendments.

## Run

Local dev ports: server 5280, preview 5290, Postgres 5434. The VPS layout is in the gitignored `VPS.md`.
