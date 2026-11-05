---
name: coding-guidelines
description: >
    Enforces the Botler coding conventions for Svelte (.svelte) and TypeScript (.ts) in server/ and for Dart (.dart) in app/.
    Covers the repo CLAUDE.md rulebook with examples: Svelte 5 runes only, strict 9-group imports, standardized 13-part section headers ("// -- NAME -- //"),
    UPPERCASE section comments with sentence-case notes, Tailwind on the element (zero style blocks, style="" only for runtime coordinates and multi-stop gradients),
    colour tokens only (calm paper; light and dark; BotlerColors in Dart, CSS variables in Svelte; no literal colours, no dark: variant), icons, accessibility (alt on img, 44px web and 48dp app touch targets, cursor-pointer, focusTrap/scrollLock on modals),
    modal, Select and keyed-each rules, Zod forms from server/src/lib/server/db/zod.ts, the Dart/Flutter rules (strict analysis, no dynamic, outbox, semantic labels, secure storage),
    the Yarn 4 and Flutter gates, and the design-fit check.
    Apply for ANY task touching Svelte, TypeScript, CSS or Dart code in this repository.
---

# Unified Coding Guidelines (Botler)

`CLAUDE.md` at the repo root is the rulebook. This skill adds detail, examples and section order; where the two ever differ, `CLAUDE.md` wins and this file gets fixed. Every change to Svelte components and TypeScript modules in `server/` follows sections 1 to 2, and every change to Dart in `app/` follows section 2G. Botler is a personal AI butler for finance and scheduling: a Flutter Android app (`app/`) on a SvelteKit backend (`server/`).

The plan for any item lives on Agent Flow Board (project BTL, `https://afb.arbenger.com/arbenger/BTL`), read and written through the agent-flow-board MCP (`mcp__afb-arbenger__*`), not in this repo. Code rules below apply to the code in this repo only.

---

## 1. UNIVERSAL RULES

### A. Git and safety
- **Never run `git push`** unless the user asks. **Never commit** unless the user asks. All work stays in the local working tree.
- Work on the checked out branch (`git branch --show-current`, today `main`). Never create or switch branches unless told to.
- Never add co-author trailers, "Generated with" lines or any AI attribution to a commit message, PR, issue or release note. Commit messages follow `type(scope): subject` as in `git log`.
- Never delete `node_modules` or `.git` when cleaning up. Delete only the exact files you made.

### B. Package manager: Yarn 4 only
- `server/` uses Yarn 4 (`.yarnrc.yml`, `nodeLinker: node-modules`, the program in `.yarn/releases/`). Never `npm`, `pnpm` or `npx`.
- Commit `yarn.lock`. Never commit `package-lock.json` or `pnpm-lock.yaml`. The Flutter app uses `flutter pub` and commits `pubspec.lock`.
- `VPS.md` and every `.env*` are gitignored. Never open them, and never put a secret in a command line, a log, a commit, CI or the app binary.
- This repo shares a VPS and a laptop with Agent Flow Board (AFB). Never touch AFB's containers, databases, volumes or ports (5433, 5180, 5190). Botler uses 5280 (dev), 5290 (preview) and 5434 (local Postgres `botler-pg-dev`).

### C. The gates
After each finished change run, from the repo root:
1. `server/`: `yarn check` and fix every error and warning in the files you touched; `yarn eslint <files>` and `yarn prettier --check <files>` on the files you changed (format only your own files with `yarn prettier --write <file>`, never the whole repo); `yarn vitest run <path>` for the related tests. Run the full `yarn test` at the end of a phase.
2. `app/`: `flutter analyze`, `dart format --set-exit-if-changed <files>`, `flutter test <path>`. Run the full `flutter test` at the end of a phase.
3. Checks go against a build or preview, never the dev server. There are no browser checks and no UI shots in this repo's flow. Report errors that already existed elsewhere, but leave them alone.

### D. Colour and theme
- Style: **calm paper** (warm off-white, deep warm charcoal in dark, one soft sage accent, fixed danger/warning/success/info colours that never come from the accent). The scale and layout rules are in `docs/DESIGN.md`.
- Light and dark mode both exist. Every colour is a token: in Dart a `BotlerColors` theme extension, in Svelte a CSS variable (`bg-[var(--surface)]`, `text-[var(--ink)]`, `border-[var(--line)]`; the names are defined by the token files and `docs/DESIGN.md`).
- **Never a literal colour** in a widget or component (`Color(0xFF...)`, `Colors.red`, `#fff`, `rgb()`, `hsl()`, `bg-[#2563eb]`, `bg-white`, `text-black`). An eslint colour rule is planned for `server/` (say "the eslint colour rule"); until then check by grep. Hex values live only in the token files.
- **Never the `dark:` variant.** A token already changes with the mode.
- Danger, warning, success and info are fixed tokens. A status never uses the accent, and the accent never carries a status.
- Text on a tinted surface uses the matching ink token. Every pair must pass AA.
- Anything rendered outside the root layout (a portal, a popover moved to `<body>`) copies the mode attribute onto its own root.
- Fonts come from the font tokens only; never write a font name in a component. Numbers use tabular figures.
- Check every visual change in both modes.

```svelte
<div class="rounded-[12px] border border-[var(--line)] bg-[var(--surface)] p-[16px] text-[var(--ink)]">   <!-- ok -->
<span class="bg-[var(--accent-soft)] text-[var(--accent-text)]">Running</span>                           <!-- ok, matching ink -->
<div class="bg-white dark:bg-black">                                                                      <!-- refused -->
```

### E. Comments and documentation preservation
- **Never remove, strip or truncate existing comments or architectural notes.**
- Section headers and dividers are UPPERCASE: `// -- STATES -- //`, `<!-- SECTION NAME -->`.
- Notes, explanations and inline comments use natural sentence case.
- Technical terms, names, CSS classes, paths and keywords keep their casing.

```svelte
<!-- MOBILE FILTER DRAWER -->
<!-- Phone layout stacks the search bar under the title -->
// TOGGLE THE ITEM FILTER
// Keep the previous range if the person cancels the popover
```

### F. Server rules (when touching `server/src/lib/server/`)
- One operations layer, `server/src/lib/server/ops/`. The HTTP API, the agent tools and the jobs all call it. A verb checks the caller's live identity itself. The caller (user id) is injected server-side; tool schemas never contain `user_id` or tenant columns.
- Every write verb takes a client `requestId` (unique per user); a replay returns the first result. A gated verb (anything that changes the money plan) needs an `approvalId` minted only by a user-authenticated HTTP call; the model can never mint one.
- Every query runs inside the transaction-local tenant context (`set_config(..., true)` with the user id), connected as the non-owning `app_runtime` role. Never query with the owner role from request code. Every table registers with the tenant registry so forced RLS is generated.
- Every background job carries its user id and sets the tenant context before its first query. Jobs are rows with a unique key, retry with backoff, and count against the model-call budget.
- Money is integer centavos everywhere (PHP); never floats. Time zone is the person's (default Asia/Manila); "a day" is a calendar date in it, worked out only in `finance/dates.ts`.
- DeepSeek gets amounts and labels, never account numbers; family names are masked; the filter runs on the final assembled prompt.
- Text from the web, other people's calendars, OCR or anything fetched is untrusted: write verbs in that turn are disabled or forced through approval. Pages are read by DeepSeek's Fetch API; the server first refuses private, loopback, link-local and metadata addresses, local names and non-standard ports, and never connects to an address the model picked.
- Secrets are never returned by an API, a tool or an export, and never logged. Logs never hold message text.
- Missing configuration fails loudly. No silent fail-open paths. Registration is closed to an allow-list.
- Schema changes go through Drizzle migrations (generated, never hand-edited once applied).

---

## 2. SVELTE AND TYPESCRIPT

### A. Svelte 5 runes first
- Runes for all state: `$state`, `$derived`, `$props`, `$effect`, `$bindable`, `{#snippet}`. No `export let`, no `$:`, no `let` reactivity.
- TypeScript is strict. No `any`, no unchecked `null` or `undefined`, no `@ts-ignore` without a reason in a comment.

### A2. Keyed each blocks: every key unique, always
- A keyed `{#each items as item (key)}` with two equal keys throws `each_key_duplicate` at runtime and takes the component down. `yarn check`, eslint and unit tests do not catch it; it only shows when the data holds a repeat.
- **Key by a field unique by definition** (an `id`), never by a display value (a title, a label, a status name).
- **Where a value really can repeat, make the list unique before it renders.** If the repeats mean the same thing, merge them into one entry and name them all in its label or hint. If they differ, key by a compound that is unique (`` `${a.id}_${idx}` ``).
- **Shared components key by what you pass them.** `Select.svelte` keys its options by `value`, so every `options` list handed to it needs unique values. De-duplicate in the caller; never change the shared component to hide it.
- **Lists built from joins, merges or several sources** (items plus drafts, members from two orgs) are where repeats come from. De-duplicate with a `Map` or `Set` on the key before rendering.

```ts
// One option per project key; projects that share a label are named together.
const options = $derived.by(() => {
	const byValue = new Map<string, { value: string; label: string; hint: string }>();
	for (const p of projects) {
		const seen = byValue.get(p.key);
		if (seen) seen.hint = `${seen.hint}, ${p.name}`;
		else byValue.set(p.key, { value: p.key, label: p.key, hint: p.name });
	}
	return [...byValue.values()];
});
```

### B. Styling: Tailwind on the element
- **Zero `<style>` blocks.** Do not create them; when you refactor a component, convert its existing rules to Tailwind utilities. No component-level CSS variables. No new external `.css` files.
- Use arbitrary-value classes for one-off values from the scale in `docs/DESIGN.md` (`w-[248px]`, `rounded-[12px]`), colours always as `var(--token)`.
- Dynamic classes go through the `class` attribute (string or array) or a small `cn()` helper if the server has one.
- The only inline `style=""` uses are (1) a multi-stop `linear-gradient()` Tailwind cannot express and (2) runtime layout coordinates (percent widths, popover coordinates). Each carries an UPPERCASE comment saying why.

```svelte
<!-- PROGRESS FILL WIDTH IS A RUNTIME PERCENT -->
<div class="h-[6px] rounded-[999px] bg-[var(--accent)]" style="width: {percent}%;"></div>

<!-- POPOVER COORDINATES COME FROM THE ANCHOR RECT AT RUNTIME -->
<div style="top: {pending.y}px; left: {pending.x}px;"></div>
```

### C. Interaction and accessibility
- **Modals and drawers**: `scrollLock` on the body and `focusTrap` on the panel (shared actions in `server/src/lib/actions/`, planned). A hand-made overlay must do both.
- **Images**: every `<img>` has `alt=""` (decorative) or a descriptive alt.
- **Icons**: `import Name from 'phosphor-svelte/lib/Name'`, one import per icon. An icon-only control always has an `aria-label`.
- **Touch targets**: at least 44 by 44 px on web (48 dp in the app); the hit area may be larger than the drawn control. Nothing scrolls sideways.
- **Pointer cursor on everything clickable**: buttons, `<a>` styled as buttons or rows, clickable rows, cards, chips, tabs, toggles, menu options, icon buttons carry `cursor-pointer`. Tailwind 4 preflight gives `<button>` the arrow cursor, so add it. Pair it with `disabled:cursor-not-allowed` (or `cursor-not-allowed` on an `aria-disabled` element). Static text and labels never get it.
- **Semantic markup**: dialogs use `role="dialog"`, `aria-modal="true"` and a label; close buttons carry `aria-label="Close"`; toggles of collapsible panels carry `aria-expanded` and `aria-controls`.

```svelte
<button type="button" class="cursor-pointer disabled:cursor-not-allowed disabled:opacity-40" onclick={save}>Save</button>
```

### C2. Scrolling tab rows and confirmations
Apply to any tab bar, chip row or segmented strip that scrolls sideways.

1. **No vertical scrollbar on a sideways row.** `overflow-x-auto` alone computes `overflow-y: auto` too, so a 1px overhang (a tab with `-mb-px` on the row's `border-b`, a focus ring, a badge) shows a vertical bar. Pair it with `overflow-y-hidden`.
2. **Hide the row's scrollbar with `!`.** Global CSS sets `scrollbar-width: thin` outside Tailwind's layers, so a plain `[scrollbar-width:none]` loses. Use `[scrollbar-width:none]!` plus `[&::-webkit-scrollbar]:hidden`, and `overscroll-x-contain` so a swipe at the end does not pull the page.
3. **Centre the active item with the row's own `scrollTo`**, never `scrollIntoView` (it also scrolls the page vertically).

```svelte
<script lang="ts">
	// -- STATES -- //

	let tabRow = $state<HTMLElement>();

	// -- REACTIVE STATEMENTS -- //

	// The active tab slides to the centre of the row on a tab change and on first load
	$effect(() => {
		void activeTab;
		const row = tabRow;
		const active = row?.querySelector<HTMLElement>('[aria-current="page"]');
		if (!row || !active) return;
		const left = active.getBoundingClientRect().left - row.getBoundingClientRect().left + row.scrollLeft - (row.clientWidth - active.offsetWidth) / 2;
		row.scrollTo({ left: Math.max(0, left), behavior: 'smooth' });
	});
</script>

<nav bind:this={tabRow} class="flex gap-[4px] overflow-x-auto overflow-y-hidden overscroll-x-contain border-b border-[var(--line)] [scrollbar-width:none]! [&::-webkit-scrollbar]:hidden" aria-label="Item sections">
	{#each tabs as t (t.key)}<a href={t.href} aria-current={t.key === activeTab ? 'page' : undefined} class="-mb-px shrink-0 cursor-pointer border-b-2 px-[12px] py-[10px] whitespace-nowrap">{t.label}</a>{/each}
</nav>
```

4. **Never a native `confirm()`, `alert()` or `prompt()`.** For a final action use an `askConfirm({ title, body, confirmLabel, tone })` helper (a shared confirm helper shown by one host in the root layout, planned; resolves `true` on yes). `body` says what will happen and who it affects. For anything with a form, use a modal with a `busy` state (see 2.E). Close only after success; on failure keep it open and show `toast.error`.

### C3. Forms people fill in
1. **A form states its own text size.** Set the size on the form and on its `input`, `select`, `textarea` and `button` explicitly; never rely on inheritance. Labels, fields and the submit button of one form share one size. Use the shared field components if the server has them rather than bare inputs; they follow `docs/DESIGN.md`.
2. **Labels are questions or actions a person understands without help.** Write the plain question ("Which project should this item go in?"), not a column name ("project_id"). Every option says what it means, never a bare Yes or No. Put the unit beside the field and a typical value as the placeholder.
3. **Show the effect of money or limit answers before saving.** When an answer changes a figure (a split, a limit, a budget), show a live worked example from the record's own data under the fields (for example the split in pesos), so a wrong answer is visible before it is saved.
4. **Look at it, do not only type-check it.** The owner checks the screen himself in both modes at phone width; state in your report that you did not look at it.

### D. Script structure

#### Import groups in strict order (no blank lines inside or between groups)
Nine groups, each introduced by a `// -- NAME -- //` label, skipping a label when its group is empty:

| # | Label | Contents |
|---|-------|----------|
| 1 | `// -- ASSETS -- //` | Images, SVGs, static files |
| 2 | `// -- DEP-TYPES -- //` | `import type` from npm dependencies |
| 3 | `// -- TYPES -- //` | `import type` from internal modules or `./$types` |
| 4 | `// -- ENVS -- //` | `$app/environment`, `$env/...` |
| 5 | `// -- CONSTANTS -- //` | Constant-only named imports |
| 6 | `// -- DEP-MODULES -- //` | Svelte runtime, transitions, npm packages |
| 7 | `// -- MODULES -- //` | Internal runtime utilities, stores, actions, ops |
| 8 | `// -- DEP-COMPONENTS -- //` | Icons (`phosphor-svelte/lib/*`), npm components |
| 9 | `// -- COMPONENTS -- //` | Internal Svelte components |

```ts
// -- DEP-TYPES -- //
import type { Snippet } from 'svelte';
// -- MODULES -- //
import { cn } from '$lib/ui/cn.js';
import { toast } from '$lib/ui/toast.svelte.js';
// -- DEP-COMPONENTS -- //
import Plus from 'phosphor-svelte/lib/Plus';
// -- COMPONENTS -- //
import Button from '$lib/ui/Button.svelte';
```

#### Component sections in strict order (one blank line below each header)
1. `// -- REQUIRED PROPS -- //`
2. `// -- OPTIONAL PROPS -- //`
3. `// -- DEBUGGING -- //`
4. `// -- TYPES -- //`
5. `// -- CONSTANTS -- //`
6. `// -- STATES -- //`
7. `// -- PERSISTED STORES -- //`
8. `// -- STORES -- //`
9. `// -- REACTIVE STATES -- //`
10. `// -- REACTIVE STATEMENTS -- //`
11. `// -- FUNCTIONS -- //`
12. `// -- SUBSCRIPTIONS -- //`
13. `// -- LIFECYCLES -- //`

Use only the sections the file needs, never duplicate one, never reorder.

```ts
// -- STATES -- //

let open = $state(false);
let anchor = $state<HTMLDivElement>();
```

### E. UI components, modals and popovers (server pages)
Botler's server has only a few pages, so the component library is small and lives in `server/src/lib/` (see [ui-ux-components.md](./ui-ux-components.md)). Reuse before inventing; a second kind of dialog, tab bar or card is a design finding.

1. **Modal lifecycle and snippets.**
   - Never wrap a modal in a parent `{#if}`. Mount it with `open={boolean}` so the out transition plays.
   - Keep the active data during the close transition, so content does not flash blank (hold the last record in a `$state` or `$derived` that outlives `open`).
   - Compose with Svelte 5 snippets for header and footer.
   - `focusTrap` on the panel and `scrollLock` on the body. While an action runs, set a `busy` state: the primary button shows a busy label, both buttons are disabled and close is ignored.
2. **Form sync from props.** Inside an `$effect` that syncs a form from props (`open`, `editing`), wrap internal writes in `untrack()` and guard with a previous-value tracker (`prevOpen`). Without it, the effect re-runs on its own writes and wipes keystrokes while the person types.
3. **SSR safety.** Never fetch a relative URL eagerly during SSR (a module-level `fetch('/x.json')` has no origin on the server). Load client data inside `onMount`, or guard with `if (typeof window === 'undefined') return`.
4. **Popovers, dropdowns and outside clicks.** Options inside a dropdown use `onmousedown={(e) => e.preventDefault()}` to keep focus and run the handler in `onclick` (plus keyboard). Never run a toggle on both mousedown and click: it fires twice and undoes the choice.
5. **Dates and times.** Use one shared picker; do not hand-roll one. Dates that mean "a day" are calendar dates in the person's time zone (`finance/dates.ts` on the server, `core/clock.dart` in the app, the only file that formats a date or time).
6. **Collapsible panels.** The toggle is a real `<button type="button">` with `aria-expanded` and `aria-controls` pointing at the body `id` (build it from `const uid = $props.id();` on its own line). It carries `cursor-pointer`. Start collapsed until `onMount` decides, so server render and first paint agree. Respect reduced motion (`motion-reduce:`).

### F. Validation with Zod
See [form-validation.md](./form-validation.md). Every form and every action payload is validated with Zod schemas generated from the Drizzle tables in `server/src/lib/server/db/zod.ts`; the same schemas serve the HTTP API, the agent tool inputs and the forms.

### G. Dart / Flutter (`app/`)
Same spirit as the Svelte and TypeScript rules; `CLAUDE.md` "Dart style" is the rulebook.

- **Strict analysis.** `analysis_options.yaml` keeps `strict-casts`, `strict-inference` and `strict-raw-types`. No `dynamic`, sound null safety, no `!` without a reason comment. Fix every analyzer warning in files you touched; no `// ignore` without a reason.
- **Small widgets, one concern each.** No business rules in widgets: they call the API; splits, balances and approvals are computed on the server. State lives in the one state-management library chosen in P6.1; do not add a second one.
- **Section comments.** The same UPPERCASE section headers (`// -- STATES -- //`, `// -- FUNCTIONS -- //`, `// -- LIFECYCLES -- //`) and sentence-case notes. Never remove existing comments.
- **Colours are tokens.** Read colours from the `BotlerColors` theme extension (`Theme.of(context).extension<BotlerColors>()`); never `Color(0xFF...)` or `Colors.xxx` in a widget. Hex values live only in the token file. Light and dark both exist; one soft sage accent; status colours fixed.
- **Tap targets and semantics.** Every tappable widget is at least 48 by 48 dp and has a semantic label (`Semantics`, `tooltip` or `semanticLabel`). One primary action per screen. Numbers use tabular figures (`FontFeature.tabularFigures()`).
- **Money and time.** Amounts are `int` centavos end to end; never `double` for money, never parse user input into a float. Format pesos only at the display edge. Dates that mean "a day" are calendar dates in the person's time zone, and every date or time shown goes through `core/clock.dart`.
- **Outbox and `requestId`.** Offline writes go through the outbox. Generate the `requestId` once when the user acts, store it with the queued write and reuse it on every retry, so a replay returns the first result.
- **Secrets.** Tokens and keys only in secure storage; never in source, assets, `SharedPreferences`, logs or crash reports. Logs never hold message text. The app never auto-approves a gated action: the `approvalId` comes from the user's own confirmation.
- **Lifecycle.** Dispose controllers, focus nodes and stream subscriptions; check `mounted` before using a `BuildContext` after an `await`; lists are lazy (`ListView.builder`).

```dart
// -- STATES -- //

// Amounts stay in centavos; only the label turns them into pesos
final int amountCentavos;
```

---

## 3. REFERENCE FILES

1. [UI components](./ui-ux-components.md): the Botler UI rules for server pages and Flutter, the overlay contract, touch and a11y standards.
2. [Zod form validation](./form-validation.md): where schemas live, the parse pattern and test requirements (server).
3. [Design fit](./design-fit.md): how a new or changed screen is checked against `docs/DESIGN.md` (calm paper tokens, one primary action, 48 dp targets). **Read it before building or changing any user-facing screen**; `/flow-critic` Lens F checks against it.

---

## 4. CHECKLIST BEFORE FINISHING

- [ ] A new or changed screen follows `docs/DESIGN.md` and its sibling screens: nothing larger than its sibling at the same level, no new size, one primary action ([design-fit.md](./design-fit.md))
- [ ] Phone first; tap targets at least 48 dp (44 px on web), nothing scrolls sideways; both modes handled by tokens (the owner looks at the screen himself)
- [ ] Colours are tokens only (`BotlerColors`, CSS variables): no literal colour, no `dark:` variant; portaled roots carry the mode attribute
- [ ] Svelte 5 runes only; zero `<style>` blocks, Tailwind on the element, `style=""` only for runtime coordinates or multi-stop gradients with an UPPERCASE comment
- [ ] Nine import groups and thirteen section headers in order (Svelte and TypeScript), no duplicates; existing comments preserved, headers UPPERCASE, notes sentence case
- [ ] Icons imported from `phosphor-svelte/lib/<Name>`; every `<img>` has `alt`
- [ ] Every clickable element has `cursor-pointer` (and `disabled:cursor-not-allowed` where it can be disabled)
- [ ] Modals mounted with `open={boolean}`, never inside `{#if}`, snippets for header and footer, data kept through the close transition; no native `confirm()` / `alert()` / `prompt()`
- [ ] Every keyed `{#each}` has a unique key (an id), and every list passed to `Select` has unique values
- [ ] Sideways rows: `overflow-y-hidden`, `[scrollbar-width:none]!` with `[&::-webkit-scrollbar]:hidden`, active item centred with `scrollTo` (2.C2)
- [ ] Forms: own text size on fields and buttons, plain-question labels, live worked example for money or limit answers, Zod from `server/src/lib/server/db/zod.ts`
- [ ] Server code goes through `server/src/lib/server/ops/`, tenant context set, write verbs take a `requestId`, money is integer centavos, no secret or message text returned or logged
- [ ] Dart: strict analysis clean, no `dynamic`, semantic labels, `BotlerColors` only, outbox with `requestId`, secrets in secure storage
- [ ] `server/`: `yarn check`, `yarn eslint <files>`, `yarn prettier --check <files>` clean on the touched files; `yarn vitest run <path>` for the related tests; full `yarn test` at the end of a phase
- [ ] `app/`: `flutter analyze`, `dart format --set-exit-if-changed <files>`, `flutter test <path>`; full `flutter test` at the end of a phase
- [ ] Yarn only for `server/` (no `npm` or `pnpm`); `yarn.lock` and `pubspec.lock` committed, no other lockfile
- [ ] Nothing pushed, nothing committed unless the user asked; no AI attribution anywhere
