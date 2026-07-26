/**
 * Daily vocabulary from the day's articles.
 *
 * `generators.js` builds vocabulary from an article's `keyTerms` map, but no
 * scraper populates that map — which is why the vocabulary collection never
 * grew. This module derives words from the article text instead: it picks the
 * genuinely exam-worthy words out of the day's editorials and defines them via
 * the free Dictionary API (dictionaryapi.dev — no key, no quota).
 *
 * Words are chosen the way an aspirant would highlight them while reading:
 * uncommon, editorial-register English, seen in a real sentence today.
 */

import crypto from 'crypto';

const TIMEOUT = 12_000;

/**
 * Long-but-ordinary words. Length alone is a poor proxy for difficulty —
 * "government" and "development" are long and useless as vocabulary.
 */
const COMMON = new Set(`
about above according account across action activity actually addition additional address advance
against agency agreement almost already although always among amount analysis announced another
anything appear application approach approved around article assembly authority available average
because become before beginning behind being believe below benefit between beyond billion budget
building business capacity capital central century certain chairman challenge chance change
channel chapter charge citizen college combined coming committee common community company compared
complete concern condition conference consider constitution continue control country course court
create crore current customer decided decision declared decrease defence demand department
described despite detail develop development different difficult direction director discussion
district division domestic during earlier economic economy education effect effort either
election electric employee english enough entire environment especially essential estimated
even evening event every example except existing expected experience explained express extent
family federal figure finally financial follow foreign formal forward function further future
general getting government greater ground group growth handle happen having health higher
history however hundred important include including increase independent india indian individual
industry information initial instead institute interest international internet issue itself
january journey judgment justice keeping known labour language larger latest leading learning
leave legal level likely limited little living local located longer looking machine
major making management manager market material matter maximum meaning measure media medical
meeting member mention method middle military million minister ministry minute mobile modern
moment money month morning mother movement multiple nation national natural nearly necessary
network never notice number object obtained offer office officer official often operation
opinion opportunity option order organisation organization original other outside overall
package parliament particular partner passed patient pattern people percent perform performance
perhaps period person physical picture place planning platform please point policy political
population position positive possible potential power practice present president press pressure
prevent previous price primary prime private probably problem process produce product production
professional program project property proposal protection provide public purpose quality quarter
question quickly quite rather reached reading ready reason receive recent recognised record
reduce reference region regional register regular related relation release remain remove report
represent request require research reserve resource response result return revenue review right
rising round running rural safety sample school science season second section sector security
sequence series service session setting several share shortage should significant similar simple
single situation slightly small social society something sometimes source special specific
spending stage standard started statement station status still strong structure student study
subject success suggest summer supply support surface survey system table taking target
technology telephone television thanks their themselves theory therefore thing think third
though thought thousand threat through timing today together total toward towards trade
traditional training transfer transport travel treatment trying turned understand union unit
united university unless until update usually value various version village visit volume
watch water weather website weight welfare western whether which while whole widely willing
window within without woman women worked worker working world would writing written yesterday
`.trim().split(/\s+/));

/**
 * Base forms of everyday words. Checked against the STEM, so one entry rules
 * out the whole family: "implement" also blocks implementation / implementing /
 * implemented.
 */
const COMMON_STEMS = new Set(`
accept access account achieve acquire address administer admit advise affect agree allocate
allow announce appear apply appoint approve argue arrange assess assign assist associate assume
attach attempt attend attract authorise authorize avail balance benefit boost calculate cancel
capture categorise categorize celebrate challenge character clarify collect combine commercial
commission communicate compare compete complete comply compose comprehensive compute conclude
conduct confirm connect consider constitute construct consult consume contain continue
contribute convert cooperate coordinate correspond create critical decide declare decrease
dedicate defend define deliver demonstrate depend describe design determine develop differ
direct disclose discriminate discuss display distribute document educate elect eliminate
emphasise emphasize employ enable encourage engage enhance ensure establish estimate evaluate
examine exceed exclude execute exercise exist expand expect experience explain explore express
extend facilitate feature finance follow formulate function fundamental generate govern
guarantee identify illustrate implement import improve include incorporate increase indicate
individual industrial influence inform initiate innovate inspect install institution instruct
integrate interact interest international interpret introduce invest investigate involve issue
justify launch legislate limit locate maintain manage manufacture measure mention modify
monitor motivate navigate negotiate notify observe obtain operate oppose organise organize
participate perform permit persuade plan practise prepare present preserve prevent proceed
process produce promote propose protect provide publish purchase qualify realise realize
receive recognise recognize recommend reduce refer reflect reform register regulate reject
relate release remain remove replace report represent request require research reserve resolve
respond restrict result retain reveal review satisfy secure select separate serve settle
significant specify sponsor stabilise stabilize standard structure submit succeed suggest
supply support suspend sustain technical technology transfer transform translate transport
understand utilise utilize validate vary verify vulnerable
rehabilitate geography geographic exponential organism proportion proportionate ecology
collaborate cooperate character characteristic technology biology psychology sociology
statistic strategy strategic environment infrastructure agriculture population energy
efficient effective sufficient consistent dependent relevant capable available reasonable

`.trim().split(/\s+/));

/** Words the news cycle repeats endlessly — true but not worth a card. */
const DOMAIN_NOISE = /^(covid|crore|lakh|rupee|modi|delhi|mumbai|bharat|niti|aayog|lok|rajya|sabha)/i;

/**
 * Suffix rewrites used to reach a base form. Applied independently rather than
 * in sequence, because one word can need different routes: "implementation"
 * reduces via -ation→'', while "rehabilitation" needs -ation→'ate'.
 */
const SUFFIXES = [
  [/abilities$/, 'able'], [/ability$/, 'able'],
  [/ations?$/, ''], [/ations?$/, 'ate'], [/ations?$/, 'e'],
  [/izations?$/, 'ize'], [/isations?$/, 'ise'],
  [/ically$/, 'ic'], [/ically$/, 'y'], [/ally$/, 'al'], [/ally$/, ''], [/ly$/, ''],
  [/ements?$/, ''], [/ements?$/, 'e'], [/ments?$/, ''],
  [/ities$/, 'ity'], [/ity$/, ''], [/ies$/, 'y'],
  [/ness(es)?$/, ''], [/ances?$/, ''], [/ences?$/, ''],
  [/ised$/, 'ise'], [/ized$/, 'ize'], [/ising$/, 'ise'], [/izing$/, 'ize'],
  [/ise$/, ''], [/ize$/, ''], [/ives?$/, 'e'], [/ives?$/, ''],
  [/ological$/, 'ology'], [/istics?$/, ''], [/ic$/, ''],
  [/ers?$/, ''], [/ers?$/, 'e'], [/ors?$/, ''], [/ors?$/, 'e'],
  [/al$/, ''], [/ed$/, ''], [/ed$/, 'e'], [/ing$/, ''], [/ing$/, 'e'],
  [/es$/, ''], [/s$/, ''],
];

/**
 * Every plausible base form of a word. Used both to recognise an everyday word
 * behind a long inflection and to collapse spelling/number variants so the same
 * word is not published twice on one day.
 */
function stems(word) {
  const w = word.toLowerCase();
  const out = new Set([w]);
  for (const [re, rep] of SUFFIXES) {
    if (!re.test(w)) continue;
    const next = w.replace(re, rep);
    if (next.length >= 4 && next !== w) out.add(next);
  }
  // One more pass catches two-suffix words ("internationally" → "international").
  for (const s of [...out]) {
    for (const [re, rep] of SUFFIXES) {
      if (!re.test(s)) continue;
      const next = s.replace(re, rep);
      if (next.length >= 4 && next !== s) out.add(next);
    }
  }
  return out;
}

/** Stable key for de-duplicating inflections of the same headword. */
function stemKey(word) {
  return [...stems(word)].sort((a, b) => a.length - b.length || a.localeCompare(b))[0];
}

/** True when the word is just an inflection of an everyday base word. */
function isOrdinary(word) {
  for (const s of stems(word)) {
    if (COMMON.has(s) || COMMON_STEMS.has(s)) return true;
  }
  return false;
}

function hashId(word) {
  return `v_${crypto.createHash('md5').update(word.toLowerCase()).digest('hex').slice(0, 16)}`;
}

async function getJson(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT);
  try {
    const res = await fetch(url, { headers: { Accept: 'application/json' }, signal: controller.signal });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/** Sentence containing the word, for the "seen in context" example. */
function exampleSentence(text, word) {
  if (!text) return '';
  const re = new RegExp(`[^.!?\\n]*\\b${word}\\w*\\b[^.!?\\n]*[.!?]`, 'i');
  const hit = text.match(re);
  if (!hit) return '';
  const s = hit[0].replace(/\s+/g, ' ').trim();
  return s.length > 30 && s.length < 300 ? s : '';
}

/**
 * Rank candidate words across the day's articles.
 *
 * A word qualifies when it is long enough to be worth learning, not in the
 * common list, and almost always lowercase in the corpus — capitalised words
 * are proper nouns (people, schemes, places), which belong in flashcards
 * rather than a vocabulary builder.
 */
function candidates(articles) {
  const total = new Map();
  const capitalised = new Map();
  const homeArticle = new Map();

  for (const article of articles) {
    const text = `${article.content || ''}\n${article.summary || ''}`;
    for (const raw of text.match(/\b[A-Za-z][a-z]{6,17}\b/g) || []) {
      const lower = raw.toLowerCase();
      if (DOMAIN_NOISE.test(lower) || isOrdinary(lower)) continue;
      total.set(lower, (total.get(lower) || 0) + 1);
      if (raw[0] === raw[0].toUpperCase()) {
        capitalised.set(lower, (capitalised.get(lower) || 0) + 1);
      }
      if (!homeArticle.has(lower)) homeArticle.set(lower, article);
    }
  }

  const scored = [];
  for (const [word, count] of total) {
    const capRatio = (capitalised.get(word) || 0) / count;
    if (capRatio > 0.4) continue; // proper noun
    // Rare words first, longer words as the tie-break: that is roughly the
    // order in which a reader would flag something as "look this up".
    scored.push({ word, count, score: word.length - count * 1.5, article: homeArticle.get(word) });
  }

  scored.sort((a, b) => b.score - a.score);

  // Collapse inflections so "operationalised" and "operationalized" — or a word
  // and its plural — cannot both be published on the same day.
  const bestByStem = new Map();
  for (const item of scored) {
    const key = stemKey(item.word);
    const held = bestByStem.get(key);
    // Prefer the shorter surface form: it is closer to the dictionary headword.
    if (!held || item.word.length < held.word.length) bestByStem.set(key, item);
  }

  return [...bestByStem.values()].sort((a, b) => b.score - a.score);
}

/** Look a word up in the free dictionary API. */
async function define(word) {
  const data = await getJson(`https://api.dictionaryapi.dev/api/v2/entries/en/${encodeURIComponent(word)}`);
  if (!Array.isArray(data) || data.length === 0) return null;

  const entry = data[0];
  const meaning = entry.meanings?.[0];
  const def = meaning?.definitions?.[0];
  if (!def?.definition || def.definition.length < 12) return null;

  const synonyms = [
    ...(meaning.synonyms || []),
    ...(def.synonyms || []),
  ].filter(Boolean).slice(0, 5);

  const antonyms = [
    ...(meaning.antonyms || []),
    ...(def.antonyms || []),
  ].filter(Boolean).slice(0, 4);

  return {
    partOfSpeech: meaning.partOfSpeech || 'word',
    meaning: def.definition.trim(),
    synonyms,
    antonyms,
  };
}

/**
 * Build vocabulary docs from the day's articles.
 *
 * @param {Array} articles  Scraped article objects.
 * @param {object} [opts]
 * @param {number} [opts.limit=12]   Words to publish for the day.
 * @param {number} [opts.pool=40]    Candidates to look up before giving up.
 * @returns {Promise<Array>} Firestore-ready `vocabulary` docs.
 */
export async function extractDailyVocabulary(articles, { limit = 12, pool = 40, log = console.log } = {}) {
  const ranked = candidates(articles).slice(0, pool);
  if (ranked.length === 0) return [];

  const out = [];
  let cursor = 0;

  const runners = Array.from({ length: 4 }, async () => {
    while (cursor < ranked.length && out.length < limit) {
      const item = ranked[cursor++];
      const entry = await define(item.word);
      if (!entry) continue; // not a real dictionary word — drop it silently
      if (out.length >= limit) break;

      const article = item.article || {};
      const category = (article.categoryTags || []).find((t) => t && t !== 'General') || 'Current Affairs';
      const word = item.word.charAt(0).toUpperCase() + item.word.slice(1);

      out.push({
        id: hashId(item.word),
        word,
        partOfSpeech: entry.partOfSpeech,
        meaning: entry.meaning,
        example: exampleSentence(article.content || '', item.word),
        synonyms: entry.synonyms,
        antonyms: entry.antonyms,
        category,
        publishedDate: article.publishedDate || '',
        newspaper: article.newspaper || '',
        upscUsage: `Seen in ${article.newspaper || 'today\'s'} coverage of ${category}${
          article.publishedDate ? ` on ${article.publishedDate}` : ''
        }.`,
      });
    }
  });

  await Promise.all(runners);

  log(`[Vocab] ${out.length} word(s) from ${ranked.length} candidate(s)`);
  return out.sort((a, b) => a.word.localeCompare(b.word));
}
