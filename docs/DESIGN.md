# Botler design: calm paper

A quiet, spacious, notebook-like app. Money and time should feel less stressful, not like a banking dashboard. One idea per screen.

## Feel

- Light mode: warm off-white paper. Dark mode: deep warm charcoal. One soft sage-green accent. Danger, warning, success and info are fixed colours that never come from the accent, and the accent never carries a status.
- Large rounded cards, soft borders, no heavy shadows. Generous empty space.
- Chat: the agent's replies are plain text without bubbles; the user's messages are small soft chips. Actions such as "Approve split" are single clear buttons.
- Chat while the assistant works (`features/chat/live_parts.dart`): "Working on it" / "Thinking" with three soft accent dots under the conversation until the answer starts; its thinking in a quiet panel (muted small plain text, left rule like a quote) that is open while it thinks and folds to one tap line "Thought for N s"; a tool that is running is one small spinner row ("Checking accounts list") that becomes its result in the same place; the answer grows with a soft block at its end. The send button turns into Stop while a turn runs. The dots stand still when the phone removes animations. The list follows the newest words only while the person is at the bottom.
- Top of the chat: a summary card with three quiet lines (total across accounts, next bill, today's first event). It collapses as you scroll.
- Loading (`ui/skeleton.dart`): quiet blocks in the `line` colour that pulse softly where the real rows will be, in the same shape and size, so nothing jumps when the data arrives (it fades in over 180 ms). They stand still when animations are removed in the phone's settings. A page-level spinner is never used. The only spinners left are the sign-in button while signing in and the small "Checking ..." row while a tool runs.
- Empty chat (`features/chat/chat_start.dart`): a skeleton while the earlier chat is coming, a quiet "try again" line if it could not load, and only when it loaded and was empty a plain greeting with three things to tap. A tap fills the message box and never sends.
- Screens arrive through one page transition (`ui/transitions.dart`): a 6% slide in from the right with a fade, 280 ms in and 220 ms out. The first screen and the sign-in only fade, and with animations removed everything only fades.
- Motion is short and gentle. Numbers count up when they change; the payday split slides into place.

## Rules

1. Every colour is a token. Dart: a `BotlerColors` theme extension in light and dark. Svelte pages: CSS variables. No literal colours in widgets or components (`Color(0xFF...)`, `#fff`, `bg-white`). The mode is a user choice; the accent is not.
2. One typeface family, with light large numerals for balances and amounts. Peso figures use tabular figures so columns line up.
3. One primary action per view. Everything else is a plain button or a link.
4. Tap targets at least 48 dp (44 px on the web). Nothing scrolls sideways.
5. Labels are plain questions or actions a person understands without help. A money or limit answer shows a worked example before saving.
6. Amounts read from a photo or screenshot, and large balance changes, are shown for confirmation before they are saved.
7. Check both modes on a phone before calling a screen done. The owner looks at every screen himself.

## Calendar

- Month, week and agenda views over one read model (`calendar_range`). Layer chips (bills, paydays, events, routines, tasks, reminders) are remembered; switching one never refetches.
- Marks are shapes, not only colours: ring = bill (danger ring when overdue, filled when paid), arrow = payday, dot = event, tick = routine, square = task, bar = reminder. At most three marks per day, then `+n`.
- A payment window is a soft band (`accentSoft`) across its days. The cash-flow strip uses `info` for the line, `success` for paydays and `warning` for low days, and is always labelled "Estimate".
- A day cell is at least 48 dp and grows with the text size; its semantic label reads the day in words ("October 5, 1 bill, 1 event"). The one primary action is Add.

## Bills

- "Coming up" is grouped under a header per month (the month's name in the app's language, empty months left out), with "Overdue" first in the `warning` colour. Rows sort by date.
- A due row has two separate targets of at least 48 dp: the body opens the bill sheet, and "Mark paid" pays it (a paid row shows a quiet "Paid" mark instead). The primary action of the screen is Add a bill.
- The bill sheet is the add form with the bill's values. Opened from a date it also offers that date's own change (move it within a month, skip it, put it back); an amount or an account changed on a date asks "Just this one, or every time?". Opened from "All bills" it changes the bill.

## Currencies

- An amount is always written with the symbol of ITS OWN currency (`context.moneyIn`, `Amount(currency:)`); `context.moneyMain` is only for an amount that is in the main currency (a total, the money plan). A dollar is never written with a peso sign.
- The accounts screen opens with one card: "Everything you have" in the main currency, the date of the exchange rates (a quiet line that is also the 48 dp "Update rates" button, `warning` colour once the rates are three days old), and a `warning` line naming a currency with no rate, which is left out of the total. An account with several currencies lists each wallet and "About X in all".
- A currency is picked from one searchable sheet (`pickCurrency`) with the ones already in use first. A move between two currencies asks for the amount sent AND the amount that arrived, and shows the rate they imply; today's rate is only a suggestion for the second box.
- A bill in another currency shows its own amount with "(about ₱…)" at the latest rate, or "(no exchange rate yet)".

## Wordmark

"Botler", with the capital B in the sage accent. The app icon is that B on paper.
