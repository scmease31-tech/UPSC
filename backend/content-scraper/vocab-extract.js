/**
 * Daily vocabulary from the day's articles.
 *
 * `generators.js` builds vocabulary from an article's `keyTerms` map, but no
 * scraper populates that map — which is why the vocabulary collection never
 * grew. This module derives words from the article text instead: it picks the
 * genuinely exam-worthy words out of the day's editorials and defines them via
 * Wikimedia's structured Wiktionary definition endpoint (no key required).
 * The previous dictionaryapi.dev endpoint timed out for every candidate from
 * GitHub Actions, so historical backfills could never complete.
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

function clean(value) {
  return String(value ?? '').normalize('NFKC').replace(/\s+/g, ' ').trim();
}

export function normalizeVocabularyWord(word) {
  return clean(word).toLocaleLowerCase('en-US');
}

function hashId(word) {
  return `v_${crypto.createHash('md5').update(normalizeVocabularyWord(word)).digest('hex').slice(0, 16)}`;
}

function uniqueWords(values, limit) {
  const seen = new Set();
  const out = [];
  for (const value of values || []) {
    const word = clean(value);
    const key = word.toLowerCase();
    if (!word || seen.has(key)) continue;
    seen.add(key);
    out.push(word);
    if (out.length >= limit) break;
  }
  return out;
}

function htmlText(value) {
  const entities = new Map([
    ['amp', '&'], ['lt', '<'], ['gt', '>'], ['quot', '"'], ['apos', "'"], ['nbsp', ' '],
  ]);
  return clean(String(value ?? '')
    .replace(/<[^>]*>/g, ' ')
    .replace(/&(#x?[0-9a-f]+|[a-z]+);/gi, (_, entity) => {
      if (entity[0] === '#') {
        const hex = entity[1]?.toLowerCase() === 'x';
        const code = Number.parseInt(entity.slice(hex ? 2 : 1), hex ? 16 : 10);
        return Number.isFinite(code) ? String.fromCodePoint(code) : ' ';
      }
      return entities.get(entity.toLowerCase()) ?? ' ';
    }))
    .replace(/\s+([,.;:!?])/g, '$1');
}

function parseDictionaryEntry(data) {
  // Wiktionary: { en: [{ partOfSpeech, definitions: [{ definition }] }] }
  const wiktionaryEntries = Array.isArray(data?.en) ? data.en : null;
  if (wiktionaryEntries) {
    for (const entry of wiktionaryEntries) {
      for (const definition of entry?.definitions || []) {
        const text = htmlText(definition?.definition);
        if (text.length < 12) continue;
        return {
          partOfSpeech: clean(entry.partOfSpeech) || 'word',
          meaning: text,
          synonyms: [],
          antonyms: [],
        };
      }
    }
    return null;
  }

  // Backward-compatible parser for injected tests and any legacy provider.
  if (!Array.isArray(data) || data.length === 0) return null;
  for (const entry of data) {
    for (const meaning of entry?.meanings || []) {
      for (const definition of meaning?.definitions || []) {
        const text = clean(definition?.definition);
        if (text.length < 12) continue;
        return {
          partOfSpeech: clean(meaning.partOfSpeech) || 'word',
          meaning: text,
          synonyms: uniqueWords([...(meaning.synonyms || []), ...(definition.synonyms || [])], 5),
          antonyms: uniqueWords([...(meaning.antonyms || []), ...(definition.antonyms || [])], 4),
        };
      }
    }
  }
  return null;
}

function retryDelay(attempt, { baseDelayMs, maxDelayMs, jitterRatio, random }) {
  const raw = Math.min(maxDelayMs, baseDelayMs * (2 ** Math.max(0, attempt - 1)));
  const jitter = raw * jitterRatio * ((random() * 2) - 1);
  return Math.max(0, Math.round(raw + jitter));
}

/**
 * Bounded dictionary lookup with observable attempts and transient backoff.
 * 404/other ordinary client misses are final; 429, 5xx, timeouts and network
 * failures are retried.
 */
export async function lookupDictionaryWord(word, {
  fetchImpl = globalThis.fetch,
  timeoutMs = TIMEOUT,
  retries = 2,
  baseDelayMs = 1_500,
  maxDelayMs = 10_000,
  jitterRatio = 0.15,
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  random = Math.random,
  onStatus = () => {},
} = {}) {
  if (typeof fetchImpl !== 'function') throw new TypeError('fetchImpl must be a function');
  const maxAttempts = Math.max(1, Math.trunc(retries) + 1);
  const url = `https://en.wiktionary.org/api/rest_v1/page/definition/${encodeURIComponent(word)}`;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), Math.max(1, timeoutMs));
    try {
      const response = await fetchImpl(url, {
        headers: {
          Accept: 'application/json',
          'User-Agent': 'UPSC-Daily-Edge/1.6 (educational vocabulary backfill; contact via repository)',
        },
        signal: controller.signal,
      });
      const httpStatus = Number(response?.status || 0);
      if (!response?.ok) {
        const notFound = httpStatus === 404;
        const retryable = httpStatus === 429 || httpStatus >= 500 || httpStatus === 0;
        if (!notFound && retryable && attempt < maxAttempts) {
          const retryAfter = Number.parseFloat(
            response?.headers?.get?.('retry-after') || '',
          );
          const retryAfterMs = Number.isFinite(retryAfter)
            ? Math.max(0, Math.round(retryAfter * 1_000))
            : 0;
          const delayMs = Math.max(
            retryAfterMs,
            retryDelay(attempt, { baseDelayMs, maxDelayMs, jitterRatio, random }),
          );
          onStatus({ word, attempt, maxAttempts, status: 'retry', httpStatus, delayMs });
          await sleep(delayMs);
          continue;
        }
        const status = notFound || (httpStatus >= 400 && httpStatus < 500 && httpStatus !== 429)
          ? 'not_found'
          : 'error';
        onStatus({ word, attempt, maxAttempts, status, httpStatus });
        return { status, attempts: attempt, httpStatus, error: status === 'error' ? `HTTP ${httpStatus}` : '' };
      }

      const entry = parseDictionaryEntry(await response.json());
      const status = entry ? 'success' : 'not_found';
      onStatus({ word, attempt, maxAttempts, status, httpStatus });
      return { status, entry, attempts: attempt, httpStatus };
    } catch (error) {
      if (attempt < maxAttempts) {
        const delayMs = retryDelay(attempt, { baseDelayMs, maxDelayMs, jitterRatio, random });
        onStatus({ word, attempt, maxAttempts, status: 'retry', error: error?.message || String(error), delayMs });
        await sleep(delayMs);
        continue;
      }
      onStatus({ word, attempt, maxAttempts, status: 'error', error: error?.message || String(error) });
      return { status: 'error', attempts: attempt, error: error?.message || String(error) };
    } finally {
      clearTimeout(timer);
    }
  }
  return { status: 'error', attempts: maxAttempts, error: 'lookup exhausted' };
}

/** Sentence containing the word, for the "seen in context" example. */
function exampleSentence(text, word) {
  if (!text) return '';
  const escaped = word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`[^.!?\\n]*\\b${escaped}\\w*\\b[^.!?\\n]*[.!?]`, 'i');
  const hit = String(text).match(re);
  if (!hit) return '';
  const sentence = clean(hit[0]);
  return sentence.length > 30 && sentence.length < 300 ? sentence : '';
}

/** Deterministic ranked candidates, exported for pure tests and planning. */
export function rankVocabularyCandidates(articles) {
  const total = new Map();
  const capitalised = new Map();
  const homeArticle = new Map();

  for (const article of articles || []) {
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
    if ((capitalised.get(word) || 0) / count > 0.4) continue;
    scored.push({ word, count, score: word.length - count * 1.5, article: homeArticle.get(word) });
  }
  scored.sort((a, b) => b.score - a.score || a.word.localeCompare(b.word));

  const bestByStem = new Map();
  for (const item of scored) {
    const key = stemKey(item.word);
    const held = bestByStem.get(key);
    if (!held || item.word.length < held.word.length ||
        (item.word.length === held.word.length && item.word.localeCompare(held.word) < 0)) {
      bestByStem.set(key, item);
    }
  }
  return [...bestByStem.values()].sort(
    (a, b) => b.score - a.score || a.word.localeCompare(b.word)
  );
}

function normalizeLookupResult(result) {
  if (!result) return { status: 'not_found', attempts: 1 };
  if (result.status) return result;
  if (result.meaning) return { status: 'success', entry: result, attempts: 1 };
  return { status: 'not_found', attempts: 1 };
}

function categoryFor(article) {
  const tag = (article.categoryTags || []).find(
    (value) => clean(value) && clean(value).toLowerCase() !== 'general'
  );
  return clean(tag || article.category || 'Current Affairs');
}

function documentFor(item, entry) {
  const article = item.article || {};
  const category = categoryFor(article);
  const normalizedWord = normalizeVocabularyWord(item.word);
  const word = item.word.charAt(0).toUpperCase() + item.word.slice(1);
  const publishedDate = clean(article.publishedDate);
  const newspaper = clean(article.newspaper);
  return {
    id: hashId(normalizedWord),
    schemaVersion: 2,
    word,
    normalizedWord,
    partOfSpeech: clean(entry.partOfSpeech) || 'word',
    meaning: clean(entry.meaning),
    example: exampleSentence(article.content || '', item.word),
    synonyms: uniqueWords(entry.synonyms, 5),
    antonyms: uniqueWords(entry.antonyms, 4),
    category,
    articleRef: clean(article.id),
    sourceUrl: clean(article.sourceUrl),
    upscPaper: clean(article.upscPaper),
    publishedDate,
    newspaper,
    upscUsage: `Seen in ${newspaper || "today's"} coverage of ${category}${
      publishedDate ? ` on ${publishedDate}` : ''
    }.`,
  };
}

/**
 * Detailed extractor used by daily and historical orchestration. Effects are
 * injectable, existing normalized words are excluded before any lookup, and
 * candidate-order batches make the chosen limit independent of response timing.
 */
export async function extractDailyVocabularyDetailed(articles, {
  limit = 12,
  pool = 40,
  concurrency = 1,
  excludeWords = new Set(),
  lookup = lookupDictionaryWord,
  lookupOptions = {},
  interBatchDelayMs,
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  log = console.log,
  onStats = () => {},
  onLookupStatus,
} = {}) {
  const ranked = rankVocabularyCandidates(articles).slice(0, Math.max(0, pool));
  const excluded = new Set([...excludeWords].map(normalizeVocabularyWord));
  const pending = ranked.filter((item) => !excluded.has(normalizeVocabularyWord(item.word)));
  const stats = {
    candidateCount: ranked.length,
    excludedCount: ranked.length - pending.length,
    lookupCount: 0,
    attemptCount: 0,
    successCount: 0,
    missCount: 0,
    errorCount: 0,
  };
  const docs = [];
  const width = Math.max(1, Math.trunc(concurrency) || 1);
  // Wikimedia asks clients to avoid request bursts. Production lookups are
  // spaced at two requests/second; injected tests stay instant unless they opt
  // into a delay. This throttle is shared by each sequential batch rather than
  // hidden inside retries, so successful requests are rate-limited too.
  const batchDelay = interBatchDelayMs === undefined
    ? (lookup === lookupDictionaryWord ? 500 : 0)
    : Math.max(0, Number(interBatchDelayMs) || 0);
  const statusLogger = onLookupStatus || ((status) => {
    const detail = status.httpStatus ? ` http=${status.httpStatus}` : '';
    const wait = status.delayMs !== undefined ? ` backoffMs=${status.delayMs}` : '';
    log(`[VocabLookup] word=${status.word} attempt=${status.attempt}/${status.maxAttempts} status=${status.status}${detail}${wait}`);
  });

  for (let offset = 0; offset < pending.length && docs.length < limit; offset += width) {
    const batch = pending.slice(offset, offset + width);
    const results = await Promise.all(batch.map(async (item) => {
      stats.lookupCount++;
      try {
        return normalizeLookupResult(await lookup(item.word, {
          ...lookupOptions,
          onStatus: statusLogger,
        }));
      } catch (error) {
        statusLogger({ word: item.word, attempt: 1, maxAttempts: 1, status: 'error', error: error?.message || String(error) });
        return { status: 'error', attempts: 1, error: error?.message || String(error) };
      }
    }));

    for (let index = 0; index < batch.length; index++) {
      const result = results[index];
      stats.attemptCount += Number(result.attempts || 1);
      if (result.status === 'success' && result.entry) {
        stats.successCount++;
        if (docs.length < limit) docs.push(documentFor(batch[index], result.entry));
      } else if (result.status === 'error') {
        stats.errorCount++;
      } else {
        stats.missCount++;
      }
    }
    if (batchDelay > 0 && offset + width < pending.length && docs.length < limit) {
      await sleep(batchDelay);
    }
  }

  log(
    `[Vocab] candidates=${stats.candidateCount} excluded=${stats.excludedCount} ` +
    `lookups=${stats.lookupCount} attempts=${stats.attemptCount} ` +
    `success=${stats.successCount} misses=${stats.missCount} errors=${stats.errorCount}`
  );
  onStats({ ...stats });
  return { docs: docs.sort((a, b) => a.normalizedWord.localeCompare(b.normalizedWord)), stats };
}

/** Backward-compatible array-only daily API. */
export async function extractDailyVocabulary(articles, options = {}) {
  const { docs } = await extractDailyVocabularyDetailed(articles, options);
  return docs;
}
