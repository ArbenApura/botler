// A LINE ADDED BESIDE ONE ABOUT THE SAME THING IS FLAGGED, NEVER REFUSED (BTL-20261106-1502)
// The notebook is the owner's of 6 Nov 2026: an old voice line asked for sweetness, and "stop the sweet endings" was added beside it.

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { addLine, similarLines } from '../../src/lib/server/notebook/text';

// -- CONSTANTS -- //

const NOTEBOOK = `# Preferences and rules
- VOICE COMES FIRST. Talk like a friend texting him: warm, casual, a bit sweet, with feeling.
- Tone: casual, warm and easy to talk to. A little sweetness and comfort is welcome.
- Pays rent from RCBC on the fifth.

# People
- Anna is his sister.
`;

// -- TESTS -- //

describe('similarLines', () => {
	it('finds the old lines a new preference about how Botler sounds may disagree with', () => {
		const found = similarLines(
			NOTEBOOK,
			'Stop the repeated sweet endings and the heart emoji on every reply.'
		);
		expect(found.length).toBeGreaterThan(0);
		expect(found.join(' ')).toContain('a bit sweet');
		expect(found.join(' ')).not.toContain('rent');
	});
	it('says nothing for a line about something else, a line already there, or a line with no real words', () => {
		expect(similarLines(NOTEBOOK, 'His dentist is on Rizal Avenue.')).toEqual([]);
		expect(
			similarLines(NOTEBOOK, 'Pays rent from RCBC on the fifth.').some((l) =>
				l.includes('Pays rent')
			)
		).toBe(false);
		expect(similarLines(NOTEBOOK, 'ok')).toEqual([]);
	});
	it('does not change addLine: the line is still added once, and an exact repeat is still refused', () => {
		const added = addLine(NOTEBOOK, 'Preferences and rules', 'No hearts, only face emoji.', 30_000);
		expect(added.changed).toBe(true);
		const again = addLine(
			added.text,
			'Preferences and rules',
			'No hearts, only face emoji.',
			30_000
		);
		expect(again.changed).toBe(false);
	});
});
