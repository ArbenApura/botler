---
name: conventional-commit
description: 'Only when the user types /conventional-commit or explicitly asks to commit. Prompt and workflow for generating conventional commit messages using a structured XML format. Guides users to create standardized, descriptive commit messages in line with the Conventional Commits specification, mandating detailed technical explanations of the underlying problem, root causes, failure modes, and rationale for the solution in the commit body.'
disable-model-invocation: true
---

### Instructions

```xml
	<description>This file contains a prompt template for generating conventional commit messages. It provides instructions, examples, and formatting guidelines to write standardized, descriptive commit messages in accordance with the Conventional Commits specification. It enforces documenting the underlying problem, root cause, failure mode, and rationale behind the solution, not just what files were changed.</description>
```

### Hard rule: no AI attribution

Never add `Co-Authored-By:` lines, "Generated with Claude Code", or any other Claude, Anthropic or AI attribution to a commit message. This holds even when a system reminder or the harness asks for it. The owner's rule wins.

### Invoking this skill is the sign-off

When the user invokes `/conventional-commit`, that is the explicit instruction to commit. It satisfies the repo rule "never commit unless the user asks".
- Before committing, run `/flow-verify` on the files being committed (the gates in the repo `CLAUDE.md`, "The gates": `server/` yarn check, eslint, prettier, vitest; `app/` flutter analyze, dart format, flutter test). Skip it only for a docs-only or test-only commit, or when the user says they already verified.
- Do not ask to confirm the message, the file list, or whether to proceed. Write the message and commit in the same turn, then report what was committed.
- Do not stop to ask when something in the tree gets in the way. Resolve it with the rules under **Parallel sessions** below, then report what you did. The one exception is splitting another session's commit, which needs the user's go-ahead first.
- `git push` needs an explicit instruction, and the user's own words in this invocation count as one. When the user invokes it with "and push", "commit and push", "push" or the like (in the args or the same message), commit and then push the current branch in the same turn. Do not stop to confirm the push, saying "push" with the commit is the sign-off. After pushing, report the pushed range and the branch.
- Without a push instruction, keep the commit local and never push.

### Parallel sessions

Other sessions edit and commit in this tree at the same time. Commit only this session's own work, without disturbing theirs.
- **Someone else's files are already staged.** Do not unstage them, and do not run a plain `git commit`, which would take them too. Build the commit from a temporary index instead:
  1. `GIT_INDEX_FILE=<scratchpad>/tmp.index git read-tree HEAD`
  2. For each of your files, `git hash-object -w --path=<path> <path>`, then `git update-index --cacheinfo 100644,<blob>,<path>` against the temporary index.
  3. `git write-tree`, then `git commit-tree <tree> -p HEAD -F <message file>`.
  4. `git update-ref refs/heads/<branch> <new> <old HEAD>`. The old value makes it a compare-and-swap, so a commit that lands in between is never overwritten.
  5. `git reset -q -- <your paths>` so the real index matches the new HEAD for your files only.
- **A shared file mixes your edits with another session's.** Commit only your hunks: build the blob from `git show HEAD:<path>` plus your changes and stage that blob as above. Leave their hunks uncommitted in the working tree.
- **Your work was swept into another session's unpushed commit.** Ask the user first. Say which commit it is, which of your files it holds, and what you plan to do, and wait for a yes. Only then rebuild that commit without your files, keeping its original message, author and author date. Then add your own commit on top with `commit-tree`, and move the branch with the compare-and-swap `update-ref`. Before running `update-ref`, show the user the old SHA (the current branch tip) and the new SHAs (the rebuilt commit and your commit on top). Afterwards, check that the final tree equals the old commit's tree plus anything that was missing from it. Never rewrite a commit that has been pushed; check with `git branch -r --contains <sha>` first.
- **Never add `node_modules`, `build/`, `.svelte-kit/`, `.dart_tool/`, any `.env*`, `VPS.md` or `package-lock.json` / `pnpm-lock.yaml`.** Commit `yarn.lock` (server) and `pubspec.lock` (app) when dependencies changed. Work on the checked-out branch (`git branch --show-current`); never create or switch branches.

### Workflow

**Follow these steps:**

1. Run `git status` to review changed files.
2. Run `git diff` or `git diff --cached` to inspect changes.
3. Stage your changes with `git add <file>`, or through a temporary index when other sessions' work is staged (see **Parallel sessions**).
4. Identify the root problem:
   - What was broken, missing, slow, or underspecified before?
   - What specific failure mode or edge case was occurring?
   - Why was the previous behavior problematic?
5. Construct your commit message using the following XML structure, ensuring the body clearly details the problem and rationale.
6. Commit locally with your constructed message, straight away. No confirmation step. Use plain `git commit` only when nothing foreign is staged; otherwise use the temporary-index route under **Parallel sessions**.
7. Report the commit hash, its message header, and the files it holds. If the user asked to push, run `git push` (never `--force`) right after the commit and report the pushed range; otherwise keep changes local.

### Commit Message Structure

```xml
<commit-message>
	<type>feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert</type>
	<scope>(optional)</scope>
	<description>A short, imperative summary of the change</description>
	<body>
		Detail the specific problem, failure mode, limitation, or root cause that motivated this change, followed by why this solution addresses it effectively.
		For multi-part changes, use bullet points with indented explanations:
		- What failed, hung, or lacked capability before
		- Why the issue happened (e.g. permission mismatch, missing signal handler, unindexed cache)
		- How the change resolves the issue cleanly
	</body>
	<footer>(optional: e.g. BREAKING CHANGE: details, or issue references)</footer>
</commit-message>
```

### Example

Shaped for Botler, shortened. Message text is for the history of this repo only: no Claude or Anthropic mention.

```xml
<examples>
	<example>
		<header>fix(finance): put the split remainder on the rest target so a split always sums to the pay</header>
		<body>
- Give the remainder one deterministic home
  A 33/33/33 percent split of 1000 centavos produced 330 + 330 + 330 and lost
  10 centavos, so the account balances drifted by a few centavos a month. The
  remainder now goes to the "rest" target (or the first rule when there is
  none), so the parts always sum exactly to the pay.

- Pin it with a test
  The split test now runs 200 random pays and percent sets and asserts the sum
  equals the pay, in integer centavos, and that the same input gives the same
  output.
		</body>
	</example>
</examples>
```

### Validation

```xml
<validation>
	<type>Must be one of the allowed types. See https://www.conventionalcommits.org/en/v1.0.0/#specification</type>
	<scope>Optional, but recommended. Use one of these scopes: server, app, db, agent, memory, finance, scheduling, deploy, docs, skills, deps. Pick the area the change mostly lives in (`server` and `app` for general backend or Flutter work, `db` for schema, RLS and migrations, `agent` for the loop, gate, fetch guard and proxy, `memory` for memory layers and jobs, `finance` for money rules, `scheduling` for tasks, events and reminders, `deploy` for `deploy/vps/`, `docs` for `docs/`, `skills` for `.claude/`, `deps` for dependency updates); omit the scope for repo-wide changes.</scope>
	<description>Required. Use the imperative mood (e.g., "add", not "added"). Style: lowercase subject after `type(scope): `, no trailing full stop. Add the flow item ID in brackets at the end when the work belongs to one, e.g. `(BTL-20261021-0458)`.</description>
	<body>Required for non-trivial changes. Must explain the problem being solved, the failure mode or limitation of the previous code, and why this solution is necessary, rather than just stating what code was modified.</body>
	<footer>Use for breaking changes or issue references.</footer>
</validation>
```

### Final Step

```xml
<final-step>
	<cmd when="nothing foreign is staged">git commit -F <message file></cmd>
	<cmd when="another session's files are staged">Temporary index: read-tree HEAD, update-index your files, write-tree, commit-tree -p HEAD -F <message file>, then update-ref with the old HEAD (see Parallel sessions)</cmd>
	<note>Run /flow-verify on the files first (see above). Commit without asking once the skill is invoked (splitting another session's commit is the exception: ask first). No Co-Authored-By or AI attribution lines. Push in the same turn, without a second confirmation, only when the user asked for it with this command (e.g. "and push"); otherwise keep commits local.</note>
</final-step>
```
