// SessionStart and UserPromptSubmit hook: names the Claude Code tab "TAB_NAME: BTL-YYYYMMDD-HHMM" for the item this session works on
// (Botler uses project key BTL; the pattern below is generic, so any project key works).
// The agent-flow-board MCP (connection afb-arbenger) answers work_start (and session_start with an item) with a displayTitle in exactly that form. This hook
// reads the latest one from the session transcript and answers { hookSpecificOutput: { sessionTitle } }, which the VS Code tab and
// the terminal show like a manual "Rename session tab". It calls no board tool and needs no token.
// The title is sent only when it changes, so a title typed by hand is overwritten only by a switch to another item. A resumed or
// compacted session gets its title back. stdout is ONE pure JSON line or nothing: on UserPromptSubmit any other text would be added to
// the prompt, and any error stays silent.

// -- DEP-MODULES -- //
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

// -- CONSTANTS -- //

// The reply of work_start sits inside the transcript as escaped JSON, so the quotes may carry backslashes
const TITLE = /displayTitle\\*"\s*:\s*\\*"([A-Z][A-Z0-9_]*: [A-Za-z0-9]+-\d{8}-\d{4}(?:-[a-z])?)\\*"/g;

// -- FUNCTIONS -- //

/** The last title the transcript holds, or null. */
export function latestTitle(text) {
	let last = null;
	for (const m of text.matchAll(TITLE)) last = m[1];
	return last;
}

/** The JSON line to print, or null when no title is due. `seen` remembers what was sent for a session. */
export function titleLine(input, dir) {
	const file = input.transcript_path;
	if (!file || !input.session_id || !existsSync(file)) return null;
	const title = latestTitle(readFileSync(file, 'utf8'));
	if (!title) return null;
	const event = input.hook_event_name === 'SessionStart' ? 'SessionStart' : 'UserPromptSubmit';
	const state = join(dir, '.afb', 'tab-titles');
	const seen = join(state, `${String(input.session_id).replace(/[^A-Za-z0-9_-]/g, '_')}.txt`);
	const force = event === 'SessionStart' && (input.source === 'resume' || input.source === 'compact');
	if (!force && existsSync(seen) && readFileSync(seen, 'utf8') === title) return null;
	if (event === 'SessionStart' && !force) return null;
	mkdirSync(state, { recursive: true });
	writeFileSync(seen, title);
	return JSON.stringify({ hookSpecificOutput: { hookEventName: event, sessionTitle: title } });
}

async function main() {
	let raw = '';
	for await (const chunk of process.stdin) raw += chunk;
	const input = JSON.parse(raw || '{}');
	const dir = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
	const line = titleLine(input, dir);
	if (line) process.stdout.write(`${line}\n`);
}

if (process.argv[1] && /afb-tab-title\.mjs$/.test(process.argv[1])) await main().catch(() => {});
