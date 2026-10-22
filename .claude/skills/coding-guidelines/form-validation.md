# Zod Form Validation Conventions

How Botler validates form submissions, API payloads, agent tool inputs and query parameters with Zod (in `server/`). The Flutter app does not duplicate these rules: it sends the payload and shows the server's plain message.

The working example is `server/src/lib/server/db/zod.ts` (schemas generated from the Drizzle tables with `drizzle-zod`, plus refinements) and its test `server/src/lib/server/db/zod.test.ts`. Once the HTTP API routes exist, they and the ops verbs are the callers to read for `safeParse` usage. Read the current files; do not copy schemas from memory or from old docs. If a file named here does not exist yet, it is planned: create it in the place named.

---

## 1. Core guarantees

- **One schema source.** Every form and every action payload is validated with a Zod schema generated from the Drizzle tables (`createInsertSchema`, `createSelectSchema`, `createUpdateSchema`) in `server/src/lib/server/db/zod.ts`. The UI actions, the HTTP API and the agent tools share them, so a rule changes in one place. Money fields are integer centavos (`z.number().int()`), never floats; a `requestId` field is required on every write payload.
- **Add refinements next to the generated schema**, not in the caller: the rules a column type cannot hold (a name pattern, a max length, a row rule such as "percent splits add up to 100"). Give each refinement a message a person can act on ("The split must add up to the full amount").
- **Fail fast and loudly.** Required fields fail with an explicit user-facing message. Missing configuration is an error, never a silent default. Optional structured data (a JSON array in a form field) may fall back to a safe default on unparseable input, parsed inside a `try`.
- **Type inference.** Export types with `z.infer<typeof schema>` so the form, the ops verb and the API agree.
- **The ops verb validates too.** The UI action parses the input, but the verb in `server/src/lib/server/ops/` is the gate that checks the caller's live identity, gating (`approvalId`) and its input; never trust that a caller already validated.
- **Never echo secrets** (passwords, tokens, keys) or message text in an error message or a returned form value, and never log them. Tool schemas given to the model never contain `user_id` or tenant columns.

---

## 2. Where schemas live

- Table-derived schemas and their refinements: `server/src/lib/server/db/zod.ts`.
- Rules shared with the browser (vocabularies, patterns): `server/src/lib/shared/`, imported by `zod.ts`.
- A form that has no table behind it (a sign-in, a search box) keeps a small schema in a module next to the route's server code, with the same message style.

Server actions receive `FormData`. Put a small `parse<Name>FormData(fd)` helper next to the schema that reads and trims the fields, parses any JSON inside a `try` with a safe default, and returns `schema.safeParse(...)`. The action returns `fail(400, { message })` with the first issue's message when parsing fails, and the form shows it through the field's `error` prop (the shared field components take `error` and `hint`).

---

## 3. Testing requirements

Every Zod schema module has a `.test.ts` beside it covering:

1. Valid input with all fields populated.
2. Missing or blank required fields, checking the exact user-facing message.
3. Format rules (URL, pattern, length) and boundary values.
4. Malformed JSON or unknown keys, with the fallback or the rejection the schema promises.

Run it with `yarn vitest run <path>` (from `server/`, for example `yarn vitest run src/lib/server/db/zod.test.ts`).
