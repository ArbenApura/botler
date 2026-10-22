# Design fit: new screens must match the screens around them

A screen that comes out bigger, busier or more confusing than the screens next to it is the most common design finding. This file says how Botler checks for it. Read it before building or changing any user-facing screen (Flutter or server page), and again before `/flow-critic` reviews it (Lens F).

Sources, in order of authority:

1. The root `CLAUDE.md`, "Colour and theme": calm paper, tokens only, one primary action, 48 dp targets.
2. `docs/DESIGN.md`: the scale, the tokens, the layout rules, what was tried and dropped. It is written separately and may not exist yet; if it does not, say so and follow `CLAUDE.md` plus the nearest sibling screen, and invent no new size.
3. The sibling screens themselves. When `docs/DESIGN.md` and a sibling disagree, the sibling wins and the disagreement is a finding on one of them.

There are no mockup files, no UI changes tables, no UI shots and no browser checks (standing override). The owner looks at every screen himself.

## 1. The plain rules

1. **Calm paper.** Warm off-white, deep warm charcoal in dark, one soft sage accent, fixed danger/warning/success/info colours that never come from the accent. Every colour is a token (`BotlerColors` in Dart, a CSS variable in Svelte). No literal colour, no `dark:` variant.
2. **Match the nearest sibling screen.** Name 1 to 3 screens a person visits next to the new one and copy their sizes and spacing level by level.
3. **Never larger than a sibling at the same level.** A heading, button, field or picture bigger than the one beside it is a defect. For emphasis use weight or colour from the tokens, not size.
4. **Invent no new size.** Use the values in `docs/DESIGN.md`. A new value needs a reason written in the plan.
5. **One primary action per view.** Everything else is a plain button or a link. Do not add a new fill style.
6. **48 dp targets.** Every tap target is at least 48 by 48 dp in the app (44 px on web), phone first, nothing scrolls sideways. Numbers use tabular figures. Motion is short and gentle.
7. **Plain labels.** A label is a plain question or action a person understands without help. A money or limit answer shows a live worked example (for example the split result in pesos) before saving.
8. **Reuse before inventing.** Use the existing widget or component. A second kind of dialog, sheet, tab bar or card is a design finding.
9. **Small pictures.** An illustration takes at most about 12% of the first screen and stays out of the way of the first action.

## 2. How a change is checked

- The author names the sibling screens and the primary action in the plan's spec, and writes in the report that the screen was not looked at by the agent.
- `/flow-critic` Lens F reads the code of the changed screen and its siblings, compares sizes level by level, and checks the rules above. A size larger than its sibling, a new pattern where an existing one fits, a second primary action or a label that needs explaining is a `HIGH`. Taste alone is `MEDIUM` and never blocks.
- Both modes are handled by the tokens; the owner confirms them on the phone.
