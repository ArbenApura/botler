# Botler

A personal AI butler for finance and scheduling. You talk to it; it plans your payday split across RCBC, GCash, Maya and other accounts, tracks bills and expenses, schedules your routine, syncs with Google Calendar and the phone clock, remembers a great deal about you, and can search the web.

- `app/`: Flutter Android app (chat-first, calm paper look).
- `server/`: SvelteKit + TypeScript backend with its own PostgreSQL + pgvector, DeepSeek proxy, agent loop and memory.
- `docs/`: [ARCHITECTURE.md](docs/ARCHITECTURE.md) and [DESIGN.md](docs/DESIGN.md).
- `CLAUDE.md`: the working rulebook for agents and people. `VPS.md` (gitignored) holds where it runs.

Plans, progress and decisions live on Agent Flow Board, project BTL: https://afb.arbenger.com/arbenger/BTL. The first plan is BTL-20261021-0458.

## Working here

1. Open this folder in Claude Code. The board MCP is declared in `.mcp.json`; run `/mcp` once and sign in to `afb-arbenger`.
2. Use `/flow` to plan and build, `/flow-interview` to settle questions, `/flow-critic` to attack a plan or review code, `/flow-audit` before sign-off, `/flow-verify` for the gates, `/conventional-commit` when you ask for a commit.
3. Server: `cd server`, `corepack enable` is not needed, Yarn 4 comes from `.yarn/releases`. `yarn install`, then `yarn dev` (port 5280). Local Postgres is the Docker container `botler-pg-dev` on port 5434 (never AFB's 5433).
4. App: `cd app`, `flutter pub get`, `flutter run` (Flutter is installed in phase P6).

Nothing is pushed or committed unless the owner asks.
