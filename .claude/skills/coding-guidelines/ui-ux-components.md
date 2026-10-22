# UI rules: Flutter widgets and server pages

Botler's UI is mostly the Flutter app (`app/lib/`). The SvelteKit server has only a few pages (sign-in, status, simple settings). Both follow calm paper (`docs/DESIGN.md`, root `CLAUDE.md` "Colour and theme"). Reuse before inventing: look in `app/lib/` for an existing widget and in `server/src/lib/` for an existing component before building a new one. The shared widget and component lists are written as the code grows; do not copy names from another project.

## 1. Tokens and theme

- Colours: `BotlerColors` (a `ThemeExtension`) in Dart, CSS variables in Svelte. Never `Color(0xFF...)`, `Colors.xxx`, `#hex`, `rgb()`, `bg-white` or `text-black` in a widget or component. Hex values live only in the token files.
- Light and dark both exist. Svelte never uses `dark:`; the token changes with the mode, and anything rendered outside the root layout (portal, popover) copies the mode attribute onto its own root.
- One soft sage accent. Danger, warning, success and info are fixed colours; a status never uses the accent and the accent never carries a status. Text on a tinted surface uses the matching ink token.
- Numbers use tabular figures. Fonts come from the theme, never named in a widget.

## 2. Touch and accessibility

- Tap targets at least 48 dp in the app (44 px on web); the hit area may be larger than the drawn control. Nothing scrolls sideways; phone first.
- Every tappable Flutter widget has a semantic label; an icon-only control always has a tooltip or `Semantics` label. On web, an icon-only control has `aria-label`.
- Svelte: every clickable has `cursor-pointer` (and `disabled:cursor-not-allowed`); every `<img>` has `alt`; icons are `import Name from 'phosphor-svelte/lib/Name'`.
- One primary action per view; everything else is a plain button or a link.

## 3. Overlays (sheet, dialog, confirm)

- One kind of dialog and one kind of bottom sheet per app; do not add a second.
- A confirm says what will happen and who it affects. Gated actions (anything that changes the money plan) always show a confirm with the real figures, and only that user confirmation produces an `approvalId`. Never a native `confirm()`, `alert()` or `prompt()` on web.
- While an action runs the primary button shows a busy label, both buttons are disabled and closing is ignored. Close only after success; on failure keep the overlay open and show the error.
- Svelte modals mount with `open={boolean}`, never inside `{#if}`, use snippets for header and footer, `focusTrap` on the panel and `scrollLock` on the body, and keep their data through the close transition.

## 4. States

Every list or data view specifies loading (a placeholder of the final shape, so nothing jumps), empty, partial, error, offline and permission-denied states. Offline writes show as queued (outbox) and change when the replay succeeds or fails.

## 5. Forms

- A form states its own text size on the form and every field and button; labels, fields and the submit button share it.
- Labels are plain questions or actions ("How much did you spend?"), not column names. Put the unit beside the field and a typical value as the placeholder.
- Amounts are typed as pesos and converted to integer centavos at the edge; a money or limit answer shows a live worked example before saving. Validation messages say what to do. Server-side rules are in [form-validation.md](./form-validation.md).

## 6. Lists and selects

- A keyed list (`{#each ... (key)}` in Svelte, `Key` or `ValueKey` in Flutter) is keyed by an id, never by a display value. Options passed to a select have unique values; de-duplicate in the caller.
- Flutter lists are lazy (`ListView.builder`); long lists page or load on scroll with a visible way to see more.

## 7. Dates and times

Use one shared picker per platform; do not hand-roll one. Dates that mean "a day" are Manila (Asia/Manila) calendar dates, and a time shown to the user is shown in Manila time.
