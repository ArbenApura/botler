// A STAND-IN EMBEDDER FOR TESTS: WORDS HASHED INTO 384 BUCKETS AND NORMALISED, SO TEXTS THAT SHARE WORDS ARE CLOSE.
// It is not a language model and does not understand Tagalog; it only lets the retrieval, tombstone and re-embed logic run without
// downloading the real model. The real model is measured by scripts/embed-eval.ts.

// -- TYPES -- //
import type { Embedder } from '../../src/lib/server/memory/embed';
// -- MODULES -- //
import { normalizeFact } from '../../src/lib/server/memory/pure';

// -- CONSTANTS -- //

const DIMENSIONS = 384;

// -- FUNCTIONS -- //

function bucket(word: string): number {
	let h = 2166136261;
	for (const ch of word) h = Math.imul(h ^ ch.charCodeAt(0), 16777619);
	return Math.abs(h) % DIMENSIONS;
}

export function hashVector(text: string): number[] {
	const v = new Array<number>(DIMENSIONS).fill(0);
	for (const w of normalizeFact(text)
		.split(' ')
		.filter((x) => x.length >= 3))
		v[bucket(w)] = (v[bucket(w)] ?? 0) + 1;
	const norm = Math.sqrt(v.reduce((s, x) => s + x * x, 0)) || 1;
	return v.map((x) => x / norm);
}

export function fakeEmbedder(model = 'test-hash-v1'): Embedder & { calls: number } {
	const e = {
		model,
		calls: 0,
		async embed(texts: readonly string[]) {
			e.calls += texts.length;
			return texts.map(hashVector);
		}
	};
	return e;
}
