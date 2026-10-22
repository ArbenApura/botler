// CHOOSING THE EMBEDDING MODEL (P4.2): TWO SMALL MULTILINGUAL MODELS ON 30 FACTS AND 30 QUESTIONS IN TAGALOG, ENGLISH AND TAGLISH.
// Run:  yarn tsx scripts/embed-eval.ts   (downloads each model once into EMBED_CACHE or ./.embed-cache; nothing personal is used)
// It prints recall@1, recall@3, time per text and the memory the process used, so the pick is a measurement.

// -- DEP-MODULES -- //
import { env, pipeline } from '@huggingface/transformers';

// -- CONSTANTS -- //

/** [fact, question that should find it] */
const SET: [string, string][] = [
	["Mama's birthday is on March 3.", 'kailan birthday ni Mama?'],
	['I am allergic to shrimp.', 'bawal ba sa akin ang hipon?'],
	['My landlord is Mr. Reyes and the rent is due every 1st.', 'sino ang nagpapaupa sa akin?'],
	['I prefer paying bills through GCash.', 'saan ako madalas magbayad ng bills?'],
	['I am saving for a work laptop, target 50,000 pesos.', 'para saan ang iniipon ko?'],
	['Ate Liza lives in Cebu and I visit her every December.', 'where does my sister live?'],
	['I get paid every 15th and 30th into RCBC.', 'kailan ang sweldo ko?'],
	[
		'I send 3,000 pesos to my parents every payday.',
		'magkano ang binibigay ko kina Nanay at Tatay?'
	],
	['I do not like spicy food.', 'ayoko ng maanghang diba?'],
	['My gym membership renews on the 5th.', 'when do I renew the gym?'],
	['I commute to Makati by MRT.', 'paano ako pumapasok sa trabaho?'],
	['Gusto kong matuto ng gitara.', 'what instrument do I want to learn?'],
	['My dog is named Brownie.', 'ano pangalan ng aso ko?'],
	['I wake up at 5:30 every weekday.', 'anong oras ako gumigising?'],
	['My Meralco bill is usually around 3,000 pesos.', 'magkano kuryente ko usually?'],
	['I eat vegetarian on Fridays.', 'ano kinakain ko tuwing Biyernes?'],
	['Kuya Jun owes me 2,000 pesos.', 'sino may utang sa akin?'],
	['My Maya savings are for emergencies only.', 'para saan yung Maya ko?'],
	['I work at a software company in BGC.', 'where do I work?'],
	['I want to travel to Japan next year.', 'saan ako gustong pumunta next year?'],
	['My phone plan is Globe 999 per month.', 'magkano ang plan ko sa phone?'],
	['I take vitamin C every morning.', 'anong vitamins iniinom ko?'],
	['The wedding of my cousin Ana is on November 22.', 'kailan ang kasal ni Ana?'],
	['I like my coffee without sugar.', 'paano ko gusto ang kape ko?'],
	['The internet bill is paid to PLDT on the 10th.', 'sino ang ISP ko?'],
	['Do not remind me about bills after 9 PM.', 'anong oras bawal mag-remind?'],
	['My uncle Boy is a doctor.', 'who in my family is a doctor?'],
	['I budget 200 pesos a day for lunch.', 'magkano budget ko sa tanghalian?'],
	['I sleep late on Saturdays.', 'late ba ako natutulog tuwing Sabado?'],
	['My cat is afraid of thunder.', 'takot sa kulog ba ang pusa ko?']
];

const MODELS: { id: string; query: string; passage: string }[] = [
	{ id: 'Xenova/multilingual-e5-small', query: 'query: ', passage: 'passage: ' },
	{ id: 'Xenova/paraphrase-multilingual-MiniLM-L12-v2', query: '', passage: '' }
];

// -- FUNCTIONS -- //

async function main() {
	env.cacheDir = process.env.EMBED_CACHE ?? './.embed-cache';
	for (const m of MODELS) {
		const t0 = Date.now();
		const extractor = await pipeline('feature-extraction', m.id, { dtype: 'q8' });
		const loadMs = Date.now() - t0;
		const embed = async (texts: string[]) => {
			const out = await extractor(texts, { pooling: 'mean', normalize: true });
			return out.tolist() as number[][];
		};
		const t1 = Date.now();
		const facts = await embed(SET.map(([f]) => m.passage + f));
		const questions = await embed(SET.map(([, q]) => m.query + q));
		const perText = (Date.now() - t1) / (SET.length * 2);
		let hit1 = 0;
		let hit3 = 0;
		questions.forEach((q, i) => {
			const ranked = facts
				.map((f, j) => ({ j, s: f.reduce((sum, v, k) => sum + v * (q[k] ?? 0), 0) }))
				.sort((a, b) => b.s - a.s)
				.map((x) => x.j);
			if (ranked[0] === i) hit1++;
			if (ranked.slice(0, 3).includes(i)) hit3++;
		});
		console.log(
			JSON.stringify({
				model: m.id,
				dimensions: facts[0]?.length,
				recallAt1: `${hit1}/${SET.length}`,
				recallAt3: `${hit3}/${SET.length}`,
				loadMs,
				msPerText: Math.round(perText),
				rssMb: Math.round(process.memoryUsage().rss / 1_048_576)
			})
		);
	}
}

main().catch((e: unknown) => {
	console.error(e instanceof Error ? e.message : 'failed');
	process.exit(1);
});
