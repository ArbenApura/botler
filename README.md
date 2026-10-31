# Botler

A personal AI butler for finance and scheduling. You talk to it; it plans your payday split across RCBC, GCash, Maya and other accounts, tracks bills and expenses, schedules your routine with its own calendar and the phone clock, keeps a notebook of what it should remember about you (a main notebook plus a library of notebooks with pages), and can search the web.

- `app/`: Flutter Android app, built and released (chat-first, calm paper look, light and dark, English and Filipino). In-app updates come from the VPS.
- `server/`: SvelteKit + TypeScript backend with its own PostgreSQL + pgvector, DeepSeek proxy (the only model host), agent loop and the notebook.
- Settings for currency (about 155 ISO currencies, one wallet per currency in an account, exchange rates for totals) and language (English, Filipino), flexible bill schedules (every 1st Wednesday, any day in the 1st week, a range of days), a calendar with a cash-flow estimate, a tamper-evident audit history per account, and a data reset in Settings.
- `docs/`: [ARCHITECTURE.md](docs/ARCHITECTURE.md), [DESIGN.md](docs/DESIGN.md), [ANDROID.md](docs/ANDROID.md) (build, install, updates, reminders) and [RESTORE.md](docs/RESTORE.md) (restoring a backup).
- `deploy/`: `local/` (init for the dev database) and `vps/` (compose, deploy, backup, restore and egress scripts, app release).
- `CLAUDE.md`: the working rulebook for agents and people. `VPS.md` (gitignored) holds where it runs.

Plans, progress and decisions live on Agent Flow Board, project BTL: https://afb.arbenger.com/arbenger/BTL. The first plan is BTL-20261021-0458.

## Working here

1. Open this folder in Claude Code. The board MCP is declared in `.mcp.json`; run `/mcp` once and sign in to `afb-arbenger`.
2. Use `/flow` to plan and build, `/flow-interview` to settle questions, `/flow-critic` to attack a plan or review code, `/flow-audit` before sign-off, `/flow-verify` for the gates, `/conventional-commit` when you ask for a commit.
3. Server: `cd server`, `corepack enable` is not needed, Yarn 4 comes from `.yarn/releases`. `yarn install`, then `yarn dev` (port 5280). Local Postgres is the Docker container `botler-pg-dev` on port 5434 (never AFB's 5433).
4. App: `cd app`, `flutter pub get`, `flutter run`. Flutter and the debug server address are in [docs/ANDROID.md](docs/ANDROID.md); a debug build reaches the dev server at `http://10.0.2.2:5280`, a release build is https only.

Nothing is pushed or committed unless the owner asks.

## Daily use

- **Talk to it** in the chat: "lunch 180 gcash", "reset my GCash to 0", "what is due this week", "remind me to pay Meralco on the 20th". It records freely and asks (a card, one tap) before it changes the money plan.
- **Calendar** (menu): Botler's own month, week and agenda of bills, paydays, events, routines, tasks and reminders, with an estimate of where your money is heading.
- **Accounts**: tap one for the full history (who did what, where, with the running balance). Menu on the account: I counted this, Set balance, Reset to zero, Export.
- **Settings**: currency and language, reminders, app lock, the audit trail check, and Reset data (the only way to erase; needs the phone lock and a typed word).
- **If a reminder did not ring**, see the battery notes in [docs/ANDROID.md](docs/ANDROID.md). **Backups** are encrypted nightly on the server (`deploy/vps/backup.sh`); copy them off with `deploy/vps/pull-backups.ps1`, and try a restore with [docs/RESTORE.md](docs/RESTORE.md). **Deploy** with `deploy/vps/deploy.ps1` (takes a backup first).

