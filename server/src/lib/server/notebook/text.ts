// THE NOTEBOOK AS PLAIN TEXT: ADD A LINE UNDER A HEADING, REPLACE OR REMOVE EXACT TEXT, FIND A SECTION, AND BUILD THE FIRST DRAFT.
// No database here. Every edit is exact: a change that matches nothing, or matches in several places, is refused with a plain message the
// assistant can read and act on, never guessed. A heading is a Markdown line that starts with one to six # characters.

// -- TYPES -- //

export type EditCode = 'no_match' | 'several' | 'too_long' | 'empty';

export type DraftFact = { text: string; kind: string; source: string };

export type DraftInput = { persona: string; about: string; facts: DraftFact[] };

export type Section = { heading: string; level: number; body: string };

type HeadingKey = 'talks' | 'about' | 'people' | 'prefs' | 'plans';

type Line = {
	text: string;
	start: number;
	heading: { level: number; title: string } | null;
};

// -- CONSTANTS -- //

/** The fixed headings of the first draft and of the empty template. */
export const HEADINGS: Record<HeadingKey, string> = {
	talks: 'How Botler talks to you',
	about: 'About you',
	people: 'People',
	prefs: 'Preferences and rules',
	plans: 'Ongoing plans'
};

const HEADING_LINE = /^(#{1,6})[ \t]+(.*?)[ \t]*#*[ \t]*$/;

const KEYS = Object.keys(HEADINGS) as HeadingKey[];

// -- FUNCTIONS -- //

/** A refused edit. The message is for the assistant: it says what to do next. */
export class EditError extends Error {
	constructor(
		readonly code: EditCode,
		message: string
	) {
		super(message);
		this.name = 'EditError';
	}
}

/** The empty template: the five headings and nothing under them. */
export function emptyTemplate(): string {
	return KEYS.map((k) => `# ${HEADINGS[k]}\n`).join('\n');
}

const normalize = (s: string) => s.trim().replace(/\s+/g, ' ').toLowerCase();

/** The title of a heading given with or without its # marks. */
const headingTitle = (heading: string) => heading.replace(/^#+\s*/, '').trim();

/** The lines of the text with where each starts and whether it is a heading. */
function linesOf(text: string): Line[] {
	const out: Line[] = [];
	let start = 0;
	for (const raw of text.split('\n')) {
		const m = HEADING_LINE.exec(raw);
		out.push({
			text: raw,
			start,
			heading: m ? { level: (m[1] ?? '').length, title: (m[2] ?? '').trim() } : null
		});
		start += raw.length + 1;
	}
	return out;
}

/** The sections of the text: each heading with the lines under it up to the next heading. Text before the first heading has no heading. */
export function parseSections(text: string): Section[] {
	const sections: Section[] = [];
	let current: { heading: string; level: number; lines: string[] } | null = null;
	const lead: string[] = [];
	const flush = () => {
		if (current)
			sections.push({
				heading: current.heading,
				level: current.level,
				body: current.lines.join('\n').trim()
			});
	};
	for (const l of linesOf(text)) {
		if (l.heading) {
			flush();
			current = { heading: l.heading.title, level: l.heading.level, lines: [] };
		} else if (current) current.lines.push(l.text);
		else lead.push(l.text);
	}
	flush();
	const intro = lead.join('\n').trim();
	return intro ? [{ heading: '', level: 0, body: intro }, ...sections] : sections;
}

/** The section that holds a position of the text, from its heading line to just before the next heading. Null for text before any heading. */
export function sectionAt(text: string, index: number): string | null {
	const lines = linesOf(text);
	let from = -1;
	for (const [i, l] of lines.entries()) {
		if (l.start > index) break;
		if (l.heading) from = i;
	}
	if (from < 0) return null;
	let to = lines.length;
	for (let i = from + 1; i < lines.length; i++)
		if (lines[i]?.heading) {
			to = i;
			break;
		}
	return lines
		.slice(from, to)
		.map((l) => l.text)
		.join('\n')
		.trim();
}

/** The section under a heading (matched ignoring case and the # marks), or null when there is none. */
export function sectionOf(text: string, heading: string): string | null {
	const want = normalize(headingTitle(heading));
	const hit = linesOf(text).find((l) => l.heading && normalize(l.heading.title) === want);
	return hit ? sectionAt(text, hit.start) : null;
}

/** One line of a note: a single line, with no bullet mark of its own. */
const cleanLine = (line: string) =>
	line
		.replace(/\s+/g, ' ')
		.replace(/^[-*]\s+/, '')
		.trim();

const tooLong = (max: number) =>
	new EditError(
		'too_long',
		`The notebook would be longer than ${max} characters. Remove or shorten something first.`
	);

/**
 * Adds "- line" at the end of the section under `heading`, making the heading at the end of the notebook when it is not there. A line that
 * is already in that section is not added twice.
 */
export function addLine(
	text: string,
	heading: string,
	line: string,
	max: number
): { text: string; section: string; changed: boolean } {
	const title = headingTitle(heading);
	const note = cleanLine(line);
	if (!title) throw new EditError('empty', 'Give the heading to add the line under.');
	if (!note) throw new EditError('empty', 'The line to add is empty.');
	const bullet = `- ${note}`;
	const lines = linesOf(text);
	const at = lines.findIndex((l) => l.heading && normalize(l.heading.title) === normalize(title));
	let next: string;
	let placed: number;
	if (at < 0) {
		const head = `${text.trimEnd()}${text.trim() ? '\n\n' : ''}# ${title}\n`;
		next = `${head}${bullet}\n`;
		placed = head.length;
	} else {
		let end = lines.length;
		for (let i = at + 1; i < lines.length; i++)
			if (lines[i]?.heading) {
				end = i;
				break;
			}
		const body = lines.slice(at + 1, end);
		if (body.some((l) => normalize(l.text.replace(/^[-*]\s+/, '')) === normalize(note)))
			return { text, section: sectionAt(text, lines[at]?.start ?? 0) ?? '', changed: false };
		// After the last line that has words, so the blank line before the next heading stays where it was
		let last = at;
		for (let i = end - 1; i > at; i--)
			if ((lines[i]?.text ?? '').trim() !== '') {
				last = i;
				break;
			}
		const out = lines.map((l) => l.text);
		out.splice(last + 1, 0, bullet);
		next = out.join('\n');
		placed = (lines[last]?.start ?? 0) + (lines[last]?.text.length ?? 0) + 1;
	}
	if (next.length > max) throw tooLong(max);
	return { text: next, section: sectionAt(next, placed) ?? bullet, changed: true };
}

/** Words too common to say a line is about the same thing. */
const COMMON = new Set([
	'that',
	'this',
	'with',
	'when',
	'then',
	'them',
	'they',
	'will',
	'have',
	'only',
	'never',
	'always',
	'every',
	'about',
	'from',
	'into',
	'your',
	'what',
	'there',
	'their',
	'does',
	'dont',
	'not',
	'user',
	'person',
	'reply',
	'replies'
]);

/** Words that mean the same kind of preference: how the assistant sounds. Two lines that both touch one of these may disagree. */
const VOICE_WORDS = new Set([
	'sweet',
	'sweetness',
	'love',
	'affectionate',
	'heart',
	'hearts',
	'emoji',
	'tone',
	'voice',
	'warm',
	'casual',
	'format',
	'short',
	// The same kind of preference in Filipino
	'tamis',
	'matamis',
	'lambing',
	'malambing',
	'tono',
	'boses',
	'ikli',
	'maikli'
]);

const wordsOf = (line: string): Set<string> =>
	new Set(
		(line.toLowerCase().match(/\p{L}{3,}/gu) ?? []).filter((w) => w.length >= 4 && !COMMON.has(w))
	);

/**
 * The lines already in a notebook that are about the same thing as a new line, so the assistant can replace one instead of keeping two that
 * may disagree (in the chat of 6 Nov "stop the sweet endings" was added beside an old line that asked for sweetness, and the old one won).
 * A hint, never a refusal: shared words, and a bonus when both lines are about how the assistant sounds. At most three, best first.
 */
export function similarLines(text: string, line: string, limit = 3): string[] {
	const mine = wordsOf(cleanLine(line));
	if (mine.size < 2) return [];
	const mineVoice = [...mine].some((w) => VOICE_WORDS.has(w));
	const scored: { line: string; score: number }[] = [];
	for (const l of linesOf(text)) {
		if (l.heading) continue;
		const existing = cleanLine(l.text);
		if (!existing || normalize(existing) === normalize(cleanLine(line))) continue;
		const theirs = wordsOf(existing);
		let shared = 0;
		for (const w of mine) if (theirs.has(w)) shared++;
		const bonus = mineVoice && [...theirs].some((w) => VOICE_WORDS.has(w)) ? 1 : 0;
		const score = shared + bonus;
		if (shared >= 1 && score >= 2) scored.push({ line: existing, score });
	}
	return scored
		.sort((a, b) => b.score - a.score)
		.slice(0, limit)
		.map((s) => (s.line.length > 200 ? `${s.line.slice(0, 197)}...` : s.line));
}

/** The positions of every exact occurrence of `find`, without overlaps. */
function occurrences(text: string, find: string): number[] {
	const out: number[] = [];
	let from = 0;
	for (;;) {
		const i = text.indexOf(find, from);
		if (i < 0) return out;
		out.push(i);
		from = i + find.length;
	}
}

/** The one place `find` appears, or a refusal that says why not. */
function once(text: string, find: string): number {
	if (!find) throw new EditError('empty', 'Give the exact text to find.');
	const hits = occurrences(text, find);
	if (hits.length === 0)
		throw new EditError(
			'no_match',
			'That text is not in the notebook. Copy it exactly as it is written there.'
		);
	if (hits.length > 1)
		throw new EditError(
			'several',
			`That text is in the notebook ${hits.length} times. Use a longer piece of text that appears once.`
		);
	return hits[0] ?? 0;
}

/** Replaces the one exact occurrence of `find` with `replacement`. */
export function replaceOnce(
	text: string,
	find: string,
	replacement: string,
	max: number
): { text: string; section: string } {
	const at = once(text, find);
	const next = text.slice(0, at) + replacement + text.slice(at + find.length);
	if (next.length > max) throw tooLong(max);
	return { text: next, section: sectionAt(next, at) ?? replacement };
}

/** Removes the one exact occurrence of `find`. A whole line (or lines) goes with its line break, so no blank line is left behind. */
export function removeOnce(text: string, find: string): { text: string; section: string } {
	const at = once(text, find);
	let from = at;
	let to = at + find.length;
	const startsLine = from === 0 || text[from - 1] === '\n';
	const endsLine = to === text.length || text[to] === '\n';
	if (startsLine && endsLine) {
		if (to < text.length) to += 1;
		else if (from > 0) from -= 1;
	}
	const next = text.slice(0, from) + text.slice(to);
	const anchor = Math.max(0, Math.min(from, next.length - 1));
	return { text: next, section: sectionAt(next, anchor) ?? '' };
}

/**
 * The first draft of a notebook, made from what the old memory held: the persona and about lines, then the facts under fixed headings, what
 * the person said themselves first. The seed job tidies it later. Kept under `max` characters by dropping the last bullets.
 */
export function buildDraft(input: DraftInput, max: number): string {
	const place = (kind: string): HeadingKey =>
		kind === 'person'
			? 'people'
			: kind === 'preference' || kind === 'money'
				? 'prefs'
				: kind === 'event'
					? 'plans'
					: 'about';
	const persona = input.persona.trim();
	const about = input.about.trim();
	const bullets: Record<HeadingKey, string[]> = {
		talks: [],
		about: [],
		people: [],
		prefs: [],
		plans: []
	};
	const ordered = [...input.facts].sort(
		(a, b) => Number(b.source === 'user') - Number(a.source === 'user')
	);
	for (const f of ordered) {
		const t = cleanLine(f.text);
		if (t) bullets[place(f.kind)].push(`- ${t}`);
	}
	if (!persona && !about && ordered.length === 0) return emptyTemplate();
	const build = () =>
		KEYS.map((k) => {
			const body =
				k === 'talks'
					? persona
					: k === 'about'
						? [about, ...bullets.about].filter(Boolean).join('\n')
						: bullets[k].join('\n');
			return `# ${HEADINGS[k]}\n${body ? `${body}\n` : ''}`;
		}).join('\n');
	let text = build();
	// Drop the last bullet of the longest list until it fits
	while (text.length > max) {
		const longest = KEYS.reduce((a, b) => (bullets[b].length > bullets[a].length ? b : a));
		if (bullets[longest].length === 0) return text.slice(0, max);
		bullets[longest].pop();
		text = build();
	}
	return text;
}

/** Words that name a relation, not a person: a bullet that starts with one is read as "Relation: Name". */
const RELATIONS = new Set([
	'mother',
	'mom',
	'mama',
	'father',
	'dad',
	'papa',
	'sister',
	'brother',
	'wife',
	'husband',
	'partner',
	'son',
	'daughter',
	'friend',
	'boss',
	'cousin',
	'aunt',
	'uncle',
	'grandmother',
	'grandfather',
	'lola',
	'lolo',
	'nanay',
	'tatay',
	'ate',
	'kuya'
]);

/**
 * The names under the "People" heading of the main notebook, for the masker: each bullet's name before a bracket, colon, comma or dash
 * ("- Maria Cruz (sister)", "- Sister: Maria Cruz"), as a whole and as single capitalised words of three letters or more. Only capitalised
 * words count, so a plain sentence is not taken for a name. Pure and bounded: at most 60 names of 40 characters.
 */
export function peopleNames(text: string): string[] {
	const out = new Set<string>();
	let inside = false;
	for (const raw of text.split('\n')) {
		const h = HEADING_LINE.exec(raw);
		if (h) {
			inside = normalize(h[2] ?? '') === normalize(HEADINGS.people);
			continue;
		}
		if (!inside) continue;
		const bullet = /^\s*(?:[-*+]|\d+[.)])\s+(.*)$/.exec(raw);
		if (!bullet?.[1]) continue;
		let rest = bullet[1].trim();
		const colon = /^([\p{L}'-]+)\s*:\s*(.*)$/u.exec(rest);
		if (colon?.[1] && RELATIONS.has(colon[1].toLowerCase())) rest = colon[2] ?? '';
		const head = (rest.split(/[(:,;]|\s[-–—]\s/)[0] ?? '').trim();
		const words = head.split(/\s+/).filter(Boolean);
		if (words.length === 0 || words.length > 4) continue;
		if (!words.every((w) => /^\p{Lu}[\p{L}'.-]*$/u.test(w))) continue;
		if (words.length === 1 && RELATIONS.has(head.toLowerCase())) continue;
		if (head.length >= 2 && head.length <= 40) out.add(head);
		for (const w of words) if (w.length >= 3 && w.length <= 40) out.add(w.replace(/[.'-]+$/, ''));
		if (out.size >= 60) break;
	}
	return [...out].slice(0, 60);
}

/** The text with fenced code blocks and inline code spans cut out, so a link written inside code is not a link. */
export function withoutCode(text: string): string {
	let inFence: string | null = null;
	const kept: string[] = [];
	for (const line of text.split('\n')) {
		const fence = /^\s{0,3}(`{3,}|~{3,})/.exec(line);
		if (inFence) {
			if (fence?.[1] && fence[1][0] === inFence[0] && fence[1].length >= inFence.length)
				inFence = null;
			continue;
		}
		if (fence?.[1]) {
			inFence = fence[1];
			continue;
		}
		kept.push(line.replace(/(`+)[^`]*?\1(?!`)/g, ' '));
	}
	return kept.join('\n');
}

/** The targets of the [[...]] links in a text, outside code: the whole text of each link (before a | label), trimmed. */
export function linkTargets(text: string): string[] {
	const out: string[] = [];
	for (const m of withoutCode(text).matchAll(/\[\[([^[\]\n|]{1,200})(?:\|[^\]\n]{0,200})?\]\]/g)) {
		const t = (m[1] ?? '').trim();
		if (t) out.push(t);
	}
	return out;
}

/**
 * Whether a text links to the page `title` of the notebook `book`. A link written [[Title]] points at a page of the notebook the text is
 * in (`sameBook`); one written [[Notebook/Title]] points there from anywhere. Case does not matter. Links in code do not count.
 */
export function linksTo(text: string, book: string, title: string, sameBook: boolean): boolean {
	const lower = (s: string) => s.trim().toLowerCase();
	const plain = lower(title);
	const full = lower(`${book}/${title}`);
	return linkTargets(text).some((t) => {
		const x = lower(t);
		return x === full || (sameBook && x === plain);
	});
}
