# Botler design: calm paper

A quiet, spacious, notebook-like app. Money and time should feel less stressful, not like a banking dashboard. One idea per screen.

## Feel

- Light mode: warm off-white paper. Dark mode: deep warm charcoal. One soft sage-green accent. Danger, warning, success and info are fixed colours that never come from the accent, and the accent never carries a status.
- Large rounded cards, soft borders, no heavy shadows. Generous empty space.
- Chat: the agent's replies are plain text without bubbles; the user's messages are small soft chips. Actions such as "Approve split" are single clear buttons.
- Top of the chat: a summary card with three quiet lines (total across accounts, next bill, today's first event). It collapses as you scroll.
- Motion is short and gentle. Numbers count up when they change; the payday split slides into place.

## Rules

1. Every colour is a token. Dart: a `BotlerColors` theme extension in light and dark. Svelte pages: CSS variables. No literal colours in widgets or components (`Color(0xFF...)`, `#fff`, `bg-white`). The mode is a user choice; the accent is not.
2. One typeface family, with light large numerals for balances and amounts. Peso figures use tabular figures so columns line up.
3. One primary action per view. Everything else is a plain button or a link.
4. Tap targets at least 48 dp (44 px on the web). Nothing scrolls sideways.
5. Labels are plain questions or actions a person understands without help. A money or limit answer shows a worked example before saving.
6. Amounts read from a photo or screenshot, and large balance changes, are shown for confirmation before they are saved.
7. Check both modes on a phone before calling a screen done. The owner looks at every screen himself.

## Wordmark

"Botler", with the capital B in the sage accent. The app icon is that B on paper.
