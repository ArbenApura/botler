// THE LABEL A TOOL CALL CARRIES TO THE SCREEN: BUILT FROM CHECKED ARGUMENTS ONLY, NO UNTRUSTED TEXT, NOTHING FOR ODD ARGUMENTS, AND EVERY TOOL EITHER HAS
// A FAMILY OR IS ON THE LIST OF TOOLS WITH THEIR OWN CARDS.

// -- DEP-MODULES -- //
import { describe, expect, it } from 'vitest';
// -- MODULES -- //
import { NO_LABEL, buildTools, describeCall } from '../../src/lib/server/agent/tools';

// -- FUNCTIONS -- //

const tool = (name: string, kind: 'read' | 'free' | 'gated' | 'web' | 'device' = 'read') => ({
	name,
	kind
});

// -- TESTS -- //

describe('describeCall', () => {
	it('names the page, the notebook and the search of the notebook tools', () => {
		expect(describeCall(tool('page_get'), { notebook: 'Trips', page: 'Trip plan' })).toEqual({
			family: 'page_read',
			subject: 'Trip plan'
		});
		expect(describeCall(tool('notebook_search'), { query: 'passport' })).toEqual({
			family: 'notebook_search',
			subject: 'passport'
		});
		expect(
			describeCall(tool('notebook_edit', 'free'), { notebook: 'Money rules', op: 'add' })
		).toEqual({
			family: 'notebook_write',
			subject: 'Money rules'
		});
		// The main notebook has no title to name
		expect(describeCall(tool('notebook_edit', 'free'), { op: 'add' })).toEqual({
			family: 'notebook_write'
		});
		expect(describeCall(tool('page_create', 'free'), { notebook: 'Trips', title: 'Cebu' })).toEqual(
			{
				family: 'page_write',
				subject: 'Cebu'
			}
		);
		expect(describeCall(tool('page_edit', 'free'), { page: 'Cebu' })).toEqual({
			family: 'page_write',
			subject: 'Cebu'
		});
	});

	it('shows a web page as its host only, and a search as its words', () => {
		expect(
			describeCall(tool('web_read', 'web'), { url: 'https://www.example.com/a/b?x=1' })
		).toEqual({
			family: 'web_read',
			subject: 'example.com'
		});
		expect(describeCall(tool('web_read', 'web'), { url: 'file:///etc/passwd' })).toEqual({
			family: 'web_read'
		});
		expect(describeCall(tool('research', 'web'), { question: 'Fares to Cebu in March' })).toEqual({
			family: 'web',
			subject: 'Fares to Cebu in March'
		});
	});

	it('keeps a subject short, plain and free of a run of five digits', () => {
		const long = describeCall(tool('page_get'), { page: 'a'.repeat(200) });
		expect(long?.subject?.length).toBe(80);
		expect(describeCall(tool('notebook_search'), { query: 'card 1234 5678 9' })).toEqual({
			family: 'notebook_search'
		});
		// Angle brackets and line breaks become single spaces
		expect(describeCall(tool('page_get'), { page: 'Plan <b>one</b>\n' })?.subject).toBe(
			'Plan b one /b'
		);
	});

	it('gives the kind but no subject once untrusted text entered the turn or the call was blocked', () => {
		expect(describeCall(tool('page_get'), { page: 'Trip plan' }, { tainted: true })).toEqual({
			family: 'page_read'
		});
		expect(
			describeCall(tool('research', 'web'), { question: 'secret plans' }, { blocked: true })
		).toEqual({
			family: 'web'
		});
	});

	it('gives nothing when the arguments do not parse or have the wrong type', () => {
		expect(describeCall(tool('page_get'), null)).toBeUndefined();
		expect(describeCall(tool('page_get'), 'text')).toBeUndefined();
		expect(describeCall(tool('page_get'), ['a'])).toBeUndefined();
		expect(describeCall(tool('page_get'), { page: 42 })).toBeUndefined();
		expect(describeCall(tool('notebook_search'), { query: { a: 1 } })).toBeUndefined();
	});

	it('gives the phone tools no label, they keep their own cards', () => {
		for (const name of NO_LABEL) expect(describeCall(tool(name, 'device'), {})).toBeUndefined();
	});

	it('covers every tool: a family, or a place on the no-label list', () => {
		const missing = buildTools({ device: true })
			.filter((t) => !NO_LABEL.has(t.name) && describeCall(t, {}) === undefined)
			.map((t) => t.name);
		expect(missing).toEqual([]);
	});
});
