// EMBEDDINGS (RETIRED): THE LOCAL MODEL IS NOT LOADED ANY MORE, THE NOTEBOOK REPLACED THE FACT MEMORY AND ITS SEARCH.
// Only the interface stays, so old facts, the legacy verbs and the tests keep working: with no embedder everything falls back to keywords.

// -- TYPES -- //

export type Embedder = {
	/** Stored with each vector, so vectors from an older model can be re-made. */
	readonly model: string;
	embed(texts: readonly string[], kind: 'passage' | 'query'): Promise<number[][]>;
};

// -- CONSTANTS -- //

export const EMBEDDING_MODEL = 'multilingual-e5-small-q8';

// -- STATES -- //

let active: Embedder | null = null;

/**
 * The embedder the verbs and jobs use when none is passed. Always null in the server now (nothing turns it on), so everything falls back
 * to keywords; a test may set one.
 */
export const activeEmbedder = (): Embedder | null => active;
export const setActiveEmbedder = (e: Embedder | null): void => {
	active = e;
};
