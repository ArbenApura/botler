// THE NOTEBOOK TEXT RULES: ADD UNDER A HEADING, REPLACE AND REMOVE EXACT TEXT, SECTIONS, AND THE FIRST DRAFT

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { notebookEditInput } from '../../src/lib/server/db/zod';
import {
	addLine,
	buildDraft,
	EditError,
	emptyTemplate,
	parseSections,
	removeOnce,
	replaceOnce,
	sectionOf
} from '../../src/lib/server/notebook/text';

// -- CONSTANTS -- //

const MAX = 16_000;

const BOOK = `# How Botler talks to you
Short and warm.

# People
- Nena is my mother

# Preferences and rules
- Never suggest cutting savings
- Reply in English
`;

const fails = (fn: () => unknown) => {
	try {
		fn();
	} catch (e) {
		if (e instanceof EditError) return e;
		throw e;
	}
	throw new Error('expected an EditError');
};

// -- TESTS -- //

describe('add a line', () => {
	it('adds a bullet at the end of the section, before the blank line and the next heading', () => {
		const out = addLine(BOOK, 'People', 'Ben is my brother', MAX);
		expect(out.changed).toBe(true);
		expect(out.text).toContain('- Nena is my mother\n- Ben is my brother\n\n# Preferences');
		expect(out.section).toBe('# People\n- Nena is my mother\n- Ben is my brother');
	});

	it('finds the heading ignoring case and the # marks', () => {
		const out = addLine(BOOK, '## preferences AND rules', 'Pay rent first', MAX);
		expect(out.text.endsWith('- Reply in English\n- Pay rent first\n')).toBe(true);
	});

	it('makes the heading at the end when it is missing', () => {
		const out = addLine(BOOK, 'Ongoing plans', 'Saving for a laptop', MAX);
		expect(out.text.endsWith('\n\n# Ongoing plans\n- Saving for a laptop\n')).toBe(true);
		expect(out.section).toBe('# Ongoing plans\n- Saving for a laptop');
		const fresh = addLine('', 'About you', 'Lives in Makati', MAX);
		expect(fresh.text).toBe('# About you\n- Lives in Makati\n');
	});

	it('does not add a line that is already there, and keeps one line per note', () => {
		const same = addLine(BOOK, 'People', '- NENA is my mother', MAX);
		expect(same.changed).toBe(false);
		expect(same.text).toBe(BOOK);
		const multi = addLine(BOOK, 'People', 'one\n\ntwo  words', MAX);
		expect(multi.text).toContain('- one two words\n');
	});

	it('refuses an empty heading or line, and a notebook that would be too long', () => {
		expect(fails(() => addLine(BOOK, ' ', 'x', MAX)).code).toBe('empty');
		expect(fails(() => addLine(BOOK, 'People', '  ', MAX)).code).toBe('empty');
		expect(fails(() => addLine(BOOK, 'People', 'x'.repeat(50), 100)).code).toBe('too_long');
	});
});

describe('replace and remove exact text', () => {
	it('replaces text that appears once and says which section changed', () => {
		const out = replaceOnce(BOOK, 'Reply in English', 'Reply in Taglish', MAX);
		expect(out.text).toContain('- Reply in Taglish\n');
		expect(out.section).toBe(
			'# Preferences and rules\n- Never suggest cutting savings\n- Reply in Taglish'
		);
	});

	it('refuses text that is not there, or is there several times, with a message to act on', () => {
		const none = fails(() => replaceOnce(BOOK, 'Reply in French', 'x', MAX));
		expect(none.code).toBe('no_match');
		expect(none.message).toMatch(/exactly/);
		const twice = fails(() => replaceOnce('a b a', 'a', 'c', MAX));
		expect(twice.code).toBe('several');
		expect(twice.message).toMatch(/2 times/);
		expect(fails(() => removeOnce(BOOK, 'nothing like this')).code).toBe('no_match');
		expect(fails(() => replaceOnce('abc', 'a', 'x'.repeat(10), 5)).code).toBe('too_long');
	});

	it('removes a whole bullet with its line break and leaves no blank line', () => {
		const out = removeOnce(BOOK, '- Never suggest cutting savings');
		expect(out.text).toContain('# Preferences and rules\n- Reply in English\n');
		expect(out.text).not.toContain('\n\n\n');
		const last = removeOnce(BOOK, '- Reply in English');
		expect(last.text.endsWith('- Never suggest cutting savings\n')).toBe(true);
	});

	it('removes a piece of a line without touching the rest', () => {
		const out = removeOnce(BOOK, ' is my mother');
		expect(out.text).toContain('- Nena\n');
	});
});

describe('sections', () => {
	it('reads the sections, with text before the first heading kept', () => {
		const sections = parseSections(`intro words\n${BOOK}`);
		expect(sections.map((s) => s.heading)).toEqual([
			'',
			'How Botler talks to you',
			'People',
			'Preferences and rules'
		]);
		expect(sections[2]?.body).toBe('- Nena is my mother');
	});

	it('finds a section by heading', () => {
		expect(sectionOf(BOOK, 'people')).toBe('# People\n- Nena is my mother');
		expect(sectionOf(BOOK, 'Nothing')).toBeNull();
	});
});

describe('the first draft', () => {
	it('is the empty template when nothing was remembered', () => {
		expect(buildDraft({ persona: '', about: '', facts: [] }, MAX)).toBe(emptyTemplate());
		expect(emptyTemplate().match(/^# /gm)).toHaveLength(5);
	});

	it('puts the persona and about lines first and the facts under their headings, the person’s own words first', () => {
		const draft = buildDraft(
			{
				persona: 'Talk like a sister.',
				about: 'Ana, 29.',
				facts: [
					{ text: 'Likes tea', kind: 'preference', source: 'extracted' },
					{ text: 'Never cut savings', kind: 'preference', source: 'user' },
					{ text: 'Nena is my mother', kind: 'person', source: 'extracted' },
					{ text: 'Laptop in March', kind: 'event', source: 'user' },
					{ text: 'Lives in Makati', kind: 'fact', source: 'extracted' }
				]
			},
			MAX
		);
		expect(sectionOf(draft, 'How Botler talks to you')).toContain('Talk like a sister.');
		expect(sectionOf(draft, 'About you')).toBe('# About you\nAna, 29.\n- Lives in Makati');
		expect(sectionOf(draft, 'People')).toContain('- Nena is my mother');
		expect(sectionOf(draft, 'Ongoing plans')).toContain('- Laptop in March');
		const prefs = sectionOf(draft, 'Preferences and rules') ?? '';
		expect(prefs.indexOf('Never cut savings')).toBeLessThan(prefs.indexOf('Likes tea'));
	});

	it('stays under the limit by dropping the last bullets', () => {
		const facts = Array.from({ length: 200 }, (_, i) => ({
			text: `fact number ${i} ${'x'.repeat(100)}`,
			kind: 'fact',
			source: 'extracted'
		}));
		const draft = buildDraft({ persona: 'p', about: '', facts }, 3000);
		expect(draft.length).toBeLessThanOrEqual(3000);
		expect(draft).toContain('fact number 0 ');
		expect(draft).not.toContain('fact number 199 ');
	});
});

describe('the notebook_edit input names what is missing', () => {
	const message = (input: unknown) => {
		const r = notebookEditInput.safeParse(input);
		return r.success ? null : r.error.issues.map((i) => i.message).join(' | ');
	};

	it('lists the ops when the op is wrong or missing', () => {
		expect(message({ op: 'append', line: 'x' })).toMatch(/"add".*"replace".*"remove"/);
		expect(message({ line: 'x' })).toMatch(/op must be/);
	});
});
