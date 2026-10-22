// EMBEDDINGS: A SMALL MULTILINGUAL MODEL (multilingual-e5-small, 384 NUMBERS A TEXT) RUN INSIDE THE APP, SO NO TEXT LEAVES THE SERVER FOR THIS.
// Chosen by measurement on Taglish (scripts/embed-eval.ts, ADR on the board): recall@1 22/30 and recall@3 24/30 against 11/30 and 17/30 for
// paraphrase-multilingual-MiniLM. The model is loaded the first time it is needed (about 15 s, about 500 MB of memory) and kept.
// Everything that uses it works without it: retrieval falls back to keywords when no embedder is given or the model cannot load.

// -- TYPES -- //

export type Embedder = {
	/** Stored with each vector, so vectors from an older model can be re-made. */
	readonly model: string;
	embed(texts: readonly string[], kind: 'passage' | 'query'): Promise<number[][]>;
};

// -- CONSTANTS -- //

export const EMBEDDING_MODEL = 'multilingual-e5-small-q8';
const HUB_ID = 'Xenova/multilingual-e5-small';

// -- FUNCTIONS -- //

type Extractor = (
	texts: string[],
	options: { pooling: 'mean'; normalize: boolean }
) => Promise<{ tolist(): number[][] }>;

/** The real embedder. The library is imported on first use, so tests and the build never load it. */
export function createLocalEmbedder(
	cacheDir = process.env.BOTLER_EMBED_CACHE ?? './.embed-cache'
): Embedder {
	let loading: Promise<Extractor> | null = null;
	const load = () =>
		(loading ??= (async () => {
			const lib = await import('@huggingface/transformers');
			lib.env.cacheDir = cacheDir;
			return (await lib.pipeline('feature-extraction', HUB_ID, {
				dtype: 'q8'
			})) as unknown as Extractor;
		})().catch((e: unknown) => {
			// A failed load is tried again next time, not remembered for ever
			loading = null;
			throw e;
		}));
	return {
		model: EMBEDDING_MODEL,
		async embed(texts, kind) {
			if (texts.length === 0) return [];
			const extractor = await load();
			const prefixed = texts.map((t) => `${kind === 'query' ? 'query' : 'passage'}: ${t}`);
			const out: number[][] = [];
			// Small batches keep the memory flat
			for (let i = 0; i < prefixed.length; i += 16)
				out.push(
					...(
						await extractor(prefixed.slice(i, i + 16), { pooling: 'mean', normalize: true })
					).tolist()
				);
			return out;
		}
	};
}

let shared: Embedder | null = null;
let active: Embedder | null = null;

/** One real embedder per process, made on first use. */
export function getEmbedder(): Embedder {
	shared ??= createLocalEmbedder();
	return shared;
}

/**
 * The embedder the verbs and jobs use when none is passed. Null until the server turns it on at start (hooks.server.ts), so a test or a
 * script never loads the model by accident, and everything falls back to keywords.
 */
export const activeEmbedder = (): Embedder | null => active;
export const setActiveEmbedder = (e: Embedder | null): void => {
	active = e;
};
