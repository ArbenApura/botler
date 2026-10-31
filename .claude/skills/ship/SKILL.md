---
name: ship
description: 'Only when the user types /ship or says ship it. Commits EVERYTHING in the working tree (own work, other sessions, untracked files) as conventional commits, then releases it all: gates, version bump and changelog, server deploy to the VPS, Android APK publish, push if a remote exists. Fully automatic, asks no question.'
disable-model-invocation: true
---

### What this skill is

`/ship` is the one-word sign-off for the whole chain: commit everything, deploy the server to the VPS, publish the Android build. Typing it is the explicit instruction and the confirmation that `CLAUDE.md` asks for before commits, VPS deploys and app publishes (see the owner's standing rule: "publish" means do it, no questions). It overrides the "ask before the VPS" rule for this run only.

### Hard rules

- **Ask nothing, from start to the final report.** Do not ask to confirm the message, the file list, the version, the deploy or the publish. Decide, act, report.
- **Commit everything.** Every modified, deleted and untracked file in the tree goes in, including other sessions' work. Do not use the temporary-index route of `/conventional-commit`, do not leave anything behind "because it is not mine".
- Still never commit: `node_modules`, `build/`, `.svelte-kit/`, `.dart_tool/`, any `.env*`, `VPS.md`, `app/android/key.properties`, key files, `package-lock.json`, `pnpm-lock.yaml`. If one shows up untracked, leave it out silently (check `.gitignore` first). Commit `yarn.lock` and `pubspec.lock`.
- **No AI attribution**: no `Co-Authored-By`, no "Generated with Claude Code", anywhere.
- Work on the checked out branch. Never create or switch branches. Never `--force`.
- Never touch AFB: its containers, databases, volumes, ports (5433, 5173, 5180, 5190), compose project, Caddyfile. Only `deploy/vps/deploy.ps1` and `deploy/vps/release-app.ps1`, which are Botler-only.
- Never print a secret or a token. Never put a password in a command line.
- The one thing that stops the run: a gate that still fails after you tried to fix it, or a deploy script that fails. A broken build is never deployed. Stop there and report what failed, in one short message, not as a question.

### Steps (in this order, no pauses)

1. **Look.** `git branch --show-current`, `git status --short`, `git diff --stat`, `git log -5 --oneline`. Work out which areas changed: `server/`, `app/`, docs/skills/deploy only.
2. **Version and changelog (only when `app/` changed).**
   - Read the live build: `ssh` per `deploy/vps/host.ps1` to `cat /srv/botler-releases/latest.json` (read-only, standing permission).
   - If `app/pubspec.yaml` versionCode is already above the live one and `app/assets/changelog.json` has exactly one entry for it, use them as they are (a previous session prepared them). Make sure the entry covers the changes being shipped; extend its `en` and `fil` lines if not.
   - Otherwise bump `version: X.Y.Z+N` (patch +1, build +1; minor +1 for a `feat`), and add a changelog entry for that versionCode with the same `versionName`, plain `en` lines and matching `fil` lines (what the person sees, not commit jargon). `release-app.ps1` refuses a build without both.
   - If only `server/` or non-app files changed, do not bump the app and do not publish an APK.
3. **Gates**, scoped to what changed, exactly as in `CLAUDE.md` "The gates" (use `/flow-verify` logic):
   - `server/`: `yarn check`, `yarn eslint <files>`, `yarn prettier --check <files>`, `yarn vitest run <paths>`; full `yarn test` when server code changed broadly. Docker Desktop must be running for server tests (`botler-pg-dev` on 5434); start Docker Desktop and wait if it is not.
   - `app/`: `flutter analyze`, `dart format --set-exit-if-changed <files>`, `flutter test`. Flutter is at `C:\Users\Admin\dev\flutter\bin` (not on PATH).
   - Fix every failure you can, including in files that came from other sessions, then rerun. `yarn prettier --write` / `dart format` on the changed files is fine. Skip gates only for docs-only, skills-only or test-only changes.
4. **Commit.** Stage everything with `git add -A` (then unstage anything from the never-commit list). Split into several conventional commits when the tree holds clearly separate concerns (for example `feat(agent)` for server and `feat(app)` for the phone, or an unrelated `docs`/`skills` change); one commit when it is one change. Follow the `/conventional-commit` format: `type(scope): imperative lowercase summary`, a body explaining the problem, root cause and why this fixes it, the flow item id in brackets when the work belongs to one. Write the message to a file in the scratchpad and `git commit -F`. Commit before deploying: `deploy.ps1` packs tracked files only.
5. **Deploy the server** (only when `server/`, `deploy/` or `docs/` that the image uses changed, or when the app needs a new server key; if in doubt, deploy). Run `deploy/vps/deploy.ps1` from PowerShell with `C:\Windows\System32` first on PATH (GNU tar from Git breaks the file list). Docker Desktop must be running. It backs up, builds locally, loads the image, migrates, checks the running build id and waits for `/healthz`. Server goes live **before** the app that depends on it is published.
6. **Publish the app** (only when `app/` changed): `deploy/vps/release-app.ps1 -Publish`. It validates the changelog, builds the split and universal APKs, checks the pinned certificate and uploads, manifest last.
7. **Push.** `git remote` first. If a remote exists, `git push` the current branch (never `--force`). If none exists, skip it and say so in the report. This repo has had no remote so far.
8. **Flow board.** If an item is claimed in this session, record the finished steps and call `work_stop`. Never end the session holding a claim. Do not start the `/flow` skills otherwise.
9. **Memory.** Update the project's `pending-after-*` memory (or add one) with the commit hashes, the server build id, the app version and what is left for the owner to check on the phone.

### Report (the only output, at the end)

One short message: the commits (hash and header), gates run and their result, server build id live or "not deployed, nothing server changed", app version published or "no app change", push result or "no remote", and anything left for the owner. Plain words, no questions.
