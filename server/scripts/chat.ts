// A THIN TEST CLIENT: TALK TO THE ASSISTANT FROM THE TERMINAL, BEFORE THE PHONE APP EXISTS (yarn chat).
// It runs the same chat service the app will call, against Botler's LOCAL Postgres only (port 5434). It refuses any other database, so it can
// never touch the VPS or AFB's data. It reads server/.env without printing it. Try M2, M3 and M6 here:
//   lunch 180 gcash            (then /undo)
//   /cards  /approve <id>  /reject <id>  /balances  /quit

// -- DEP-MODULES -- //
import { randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';
// -- MODULES -- //
import { handleChat } from '../src/lib/server/agent/chat';
import { user } from '../src/lib/server/db/schema';
import { createPostgres } from '../src/lib/server/db/client';
import { migrateLocked } from '../src/lib/server/db/migrate';
import { decideAction, listActions } from '../src/lib/server/ops/actions';
import { accountBalances } from '../src/lib/server/ops/ledger';
import { assertProviderKeys, type ProviderName } from '../src/lib/server/proxy/provider';
import { createAnthropicClient } from '../src/lib/server/proxy/anthropic';
import { createModelClient } from '../src/lib/server/proxy/deepseek';
import { DEFAULT_LIMITS } from '../src/lib/server/proxy/limits';
import { formatPhp } from '../src/lib/finance/money';
import { EXTRACT_PROMPT, parseJsonObject } from '../src/lib/server/jobs/memory';

// -- CONSTANTS -- //

const DEV_USER = 'user_dev_local';

// -- FUNCTIONS -- //

function loadEnv(): Record<string, string> {
	const out: Record<string, string> = {};
	for (const line of readFileSync(new URL('../.env', import.meta.url), 'utf8').split(/\r?\n/)) {
		const m = /^([A-Z][A-Z0-9_]*)=(.*)$/.exec(line);
		if (m) out[m[1] as string] = (m[2] as string).trim();
	}
	return out;
}

function mustBeLocal(url: string | undefined, name: string): string {
	if (!url) throw new Error(`${name} is missing in server/.env`);
	const u = new URL(url);
	if (!['localhost', '127.0.0.1'].includes(u.hostname) || u.port !== '5434')
		throw new Error(
			`${name} must point at Botler's local Postgres (127.0.0.1:5434). Nothing else is allowed here.`
		);
	return url;
}

function providerClient(env: Record<string, string>) {
	// The script reads its own environment, so the provider check runs here with the same values (tsx cannot use $app/env)
	const provider = (env.MODEL_PROVIDER || 'anthropic').trim().toLowerCase();
	assertProviderKeys(provider, env.ANTHROPIC_API_KEY || '', env.DEEPSEEK_API_KEY || '');
	const limits = DEFAULT_LIMITS;
	if (provider === 'deepseek')
		return {
			provider: 'deepseek' as ProviderName,
			model: createModelClient({
				apiKey: env.DEEPSEEK_API_KEY || '',
				baseUrl: (env.DEEPSEEK_BASE_URL || 'https://api.deepseek.com').replace(/\/$/, ''),
				model: env.DEEPSEEK_MODEL || 'deepseek-flash',
				limits
			})
		};
	return {
		provider: 'anthropic' as ProviderName,
		model: createAnthropicClient({
			apiKey: env.ANTHROPIC_API_KEY || '',
			baseUrl: (env.ANTHROPIC_BASE_URL || 'https://api.anthropic.com').replace(/\/$/, ''),
			model: env.ANTHROPIC_MODEL || 'claude-haiku-5-5',
			limits
		})
	};
}

async function main() {
	const env = loadEnv();
	const runtimeUrl = mustBeLocal(env.DATABASE_URL, 'DATABASE_URL');
	const ownerUrl = mustBeLocal(env.DATABASE_OWNER_URL, 'DATABASE_OWNER_URL');
	const using = providerClient(env);
	const handle = createPostgres({ runtimeUrl, ownerUrl, switchRole: false });
	await migrateLocked(handle);
	await handle.db
		.insert(user)
		.values({ id: DEV_USER, name: 'Dev', email: 'dev@example.invalid' })
		.onConflictDoNothing();
	const ctx = { handle, actor: { userId: DEV_USER, kind: 'person' as const } };
	const rl = createInterface({ input: stdin, output: stdout });
	const model = using.model;
	console.log(
		`Botler test client (local database, dev user, provider ${using.provider}). Type a message, or /cards /approve <id> /reject <id> /balances /quit`
	);
	try {
		for (;;) {
			let line: string;
			try {
				line = (await rl.question('you> ')).trim();
			} catch {
				// The input closed (piped input): end the session without a readline error
				break;
			}
			if (!line) continue;
			if (line === '/quit') break;
			try {
				if (line === '/balances') {
					for (const b of await accountBalances(ctx))
						console.log(`  ${b.name}: ${formatPhp(b.balance)}`);
				} else if (line.startsWith('/memory ')) {
					// The real memory job path, run here synchronously: one memory-bucket call with the extract prompt
					const message = line.slice(8).trim();
					const out = await model.complete(ctx, {
						bucket: 'memory',
						messages: [
							{ role: 'system', content: EXTRACT_PROMPT },
							{ role: 'user', content: message }
						]
					});
					console.log(`  facts: ${JSON.stringify(parseJsonObject(out.content) ?? out.content)}`);
					console.log(`  tokens: ${out.usage.promptTokens} in / ${out.usage.completionTokens} out`);
				} else if (line === '/cards') {
					for (const c of await listActions(ctx, 'pending'))
						console.log(`  [${c.id.slice(0, 8)}] ${c.summary}`);
				} else if (/^\/(approve|reject) /.test(line)) {
					const [cmd, short] = line.split(/\s+/);
					const card = (await listActions(ctx, 'pending')).find((c) =>
						c.id.startsWith(short ?? '#')
					);
					if (!card) console.log('  no such pending card');
					else
						console.log(
							`  ${(await decideAction(ctx, { actionId: card.id, decision: cmd === '/approve' ? 'approve' : 'reject' })).status}`
						);
				} else {
					stdout.write('bot> ');
					for await (const e of handleChat(
						ctx,
						{ clientMessageId: `cli-${randomBytes(8).toString('hex')}`, text: line },
						{ model }
					)) {
						if (e.type === 'delta') stdout.write(e.text);
						else if (e.type === 'tool')
							stdout.write(`\n  [${e.name}: ${e.status}${e.message ? ` - ${e.message}` : ''}]\n`);
						else if (e.type === 'card')
							stdout.write(
								`  [card ${e.actionId.slice(0, 8)}] ${e.summary}  (/approve ${e.actionId.slice(0, 8)})\n`
							);
						else if (e.type === 'fallback')
							stdout.write(`\n  [the assistant is ${e.reason}: use the manual expense form]\n`);
					}
					stdout.write('\n');
				}
			} catch (e) {
				console.log(`  error: ${e instanceof Error ? e.message : 'something went wrong'}`);
			}
		}
	} finally {
		rl.close();
		await handle.close();
	}
}

main().catch((e: unknown) => {
	console.error(e instanceof Error ? e.message : 'failed');
	process.exit(1);
});
