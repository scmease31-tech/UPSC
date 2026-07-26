/**
 * Topic image lookup for articles that ship without artwork.
 *
 * Sources, in order:
 *   1. Wikipedia page image for the best-matching article (via the free MediaWiki
 *      + REST APIs — no key, no quota to speak of).
 *   2. Wikimedia Commons search, when no Wikipedia page carries a lead image.
 *
 * Everything returned is openly licensed, and the caller stores the credit line
 * alongside the URL so the app can attribute it. A match is only accepted when
 * it is demonstrably about the same subject — a wrong-but-pretty photo is worse
 * than the app's generated cover, so this returns null rather than guessing.
 */

const UA = 'UPSCDailyEdge/1.0 (https://github.com/scmease31-tech/UPSC; content pipeline)';
const TIMEOUT = 15_000;

/** Words that carry no topical signal when matching a headline to a page. */
const NOISE = new Set([
  'india', 'indian', 'the', 'and', 'for', 'with', 'from', 'that', 'this', 'what',
  'why', 'how', 'new', 'news', 'first', 'about', 'into', 'over', 'under', 'more',
  'report', 'reports', 'study', 'scheme', 'policy', 'government', 'national',
  'union', 'state', 'states', 'act', 'bill', 'draft', 'plan', 'year', 'years',
  'day', 'days', 'issue', 'issues', 'key', 'facts', 'rapid', 'fire', 'amendment',
  'committee', 'commission', 'council', 'board', 'authority', 'ministry',
]);

const cache = new Map();

async function getJson(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT);
  try {
    const res = await fetch(url, {
      headers: { 'User-Agent': UA, Accept: 'application/json' },
      signal: controller.signal,
    });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Significant, lowercase word set for relevance scoring.
 *
 * Bare numbers are dropped: a shared year ("…Act, 2025") would otherwise make
 * two unrelated pieces of legislation look like a match.
 */
function keywords(text) {
  return new Set(
    (text || '')
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, ' ')
      .split(/\s+/)
      .filter((w) => w.length >= 4 && !/^\d+$/.test(w) && !NOISE.has(w)),
  );
}

/** Fraction of the query's keywords that the candidate covers. */
function overlap(queryWords, candidateText) {
  if (queryWords.size === 0) return 0;
  const cand = keywords(candidateText);
  let hits = 0;
  for (const w of queryWords) {
    if (cand.has(w)) { hits++; continue; }
    // Allow stem-ish matches ("flooding" vs "floods").
    for (const c of cand) {
      if (c.startsWith(w.slice(0, Math.max(4, w.length - 2)))) { hits++; break; }
    }
  }
  return hits / queryWords.size;
}

/** Wikipedia thumbnails are served at a fixed width; ask for a card-sized one. */
function resizeCommons(url, width = 960) {
  if (!url) return url;
  return url.replace(/\/\d+px-/, `/${width}px-`);
}

/**
 * Illustrations that are chrome rather than subject matter. Tested against the
 * FILENAME only — every Wikimedia image is served from upload.wikimedia.org, so
 * matching the whole URL would reject the entire source.
 */
// Emblems, flags and coats of arms are the default lead image on most
// legislation/institution pages. They are technically "relevant" and tell the
// reader nothing, so they are treated as chrome too.
const BAD_IMAGE = /(logo|icon|disambig|question_book|ambox|edit-|symbol[_-]|placeholder|no[_-]image|flag[_ -]|emblem|coat[_ -]of[_ -]arms|seal[_ -]of|insignia)/i;

function usableImage(url) {
  if (!url) return false;
  if (!/\.(jpe?g|png|webp)(\?|$)/i.test(url)) return false;
  const filename = decodeURIComponent(url.split('/').pop() || '');
  return !BAD_IMAGE.test(filename);
}

async function wikipediaSearch(query, limit = 5) {
  const url = 'https://en.wikipedia.org/w/api.php?action=query&list=search'
    + `&srsearch=${encodeURIComponent(query)}&srlimit=${limit}&srnamespace=0&format=json`;
  const data = await getJson(url);
  return data?.query?.search?.map((r) => r.title) || [];
}

async function wikipediaSummary(title) {
  return getJson(`https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(title)}`);
}

async function commonsSearch(query) {
  // Ask Commons directly for a file whose title matches, then resolve its URL.
  const search = 'https://commons.wikimedia.org/w/api.php?action=query&generator=search'
    + `&gsrsearch=${encodeURIComponent(`${query} filetype:bitmap`)}&gsrlimit=5&gsrnamespace=6`
    + '&prop=imageinfo&iiprop=url|extmetadata&iiurlwidth=960&format=json';
  const data = await getJson(search);
  const pages = data?.query?.pages;
  if (!pages) return null;

  const queryWords = keywords(query);
  for (const page of Object.values(pages)) {
    const info = page.imageinfo?.[0];
    const url = info?.thumburl || info?.url;
    if (!usableImage(url)) continue;
    if (overlap(queryWords, page.title) < 0.4) continue;
    const artist = info?.extmetadata?.Artist?.value?.replace(/<[^>]+>/g, '').trim();
    return {
      url,
      credit: `Wikimedia Commons${artist ? ` — ${artist.slice(0, 80)}` : ''}`,
      creditUrl: info?.descriptionurl || 'https://commons.wikimedia.org',
      source: 'Wikimedia Commons',
    };
  }
  return null;
}

/**
 * Find an openly-licensed image for an article.
 *
 * @param {string} title       The headline.
 * @param {string[]} [tags]    Topic tags, most specific first.
 * @returns {Promise<{url,credit,creditUrl,source}|null>} null when nothing
 *          sufficiently on-topic was found — the app then draws its own cover.
 */
/**
 * Wikipedia disambiguates works of fiction and media in the title. Searching a
 * generic word like "Health" happily returns "Health (film)" — whose lead image
 * is a movie poster.
 */
const MEDIA_PAGE = /\((film|movie|album|song|band|tv series|television series|novel|book|magazine|video game|play|opera|musician|singer|actor|character|comics?)\)/i;
const MEDIA_DESC = /\b(film|movie|album|song|band|novel|sitcom|tv series|video game|manga|anime)\b/i;

/** Try a single query, returning the first sufficiently on-topic lead image. */
async function tryQuery(query, minScore) {
  const queryWords = keywords(query);
  if (queryWords.size === 0) return null;

  for (const pageTitle of (await wikipediaSearch(query, 5)).slice(0, 5)) {
    if (MEDIA_PAGE.test(pageTitle)) continue;

    const summary = await wikipediaSummary(pageTitle);
    if (!summary || summary.type === 'disambiguation') continue;
    if (MEDIA_DESC.test(summary.description || '')) continue;

    const image = summary.originalimage?.source || summary.thumbnail?.source;
    if (!usableImage(image)) continue;

    const score = Math.max(
      overlap(queryWords, summary.title),
      overlap(queryWords, `${summary.title} ${summary.description || ''}`),
    );
    if (score < minScore) continue;

    return {
      url: resizeCommons(summary.thumbnail?.source || image),
      credit: `Wikipedia — ${summary.title}`,
      creditUrl: summary.content_urls?.desktop?.page
        || `https://en.wikipedia.org/wiki/${encodeURIComponent(summary.title)}`,
      source: 'Wikipedia',
      matched: summary.title,
    };
  }
  return null;
}

/**
 * Find an openly-licensed image for an article.
 *
 * @param {string} title       The headline.
 * @param {string[]} [tags]    Topic tags, most specific first.
 * @param {string[]} [entities] Named entities the article actually discusses
 *        (Drishti's related-topics list: "Brahmaputra", "Southwest Monsoon", …).
 *        A headline is often un-searchable ("India's 1st …"), while the entities
 *        inside it map cleanly onto encyclopaedia pages with real photographs.
 * @returns {Promise<{url,credit,creditUrl,source}|null>} null when nothing
 *          sufficiently on-topic was found — the app then draws its own cover.
 */
export async function findTopicImage(title, tags = [], entities = []) {
  const clean = (title || '').replace(/[:|–—].*$/, '').trim();
  if (clean.length < 6) return null;

  const cacheKey = clean.toLowerCase();
  if (cache.has(cacheKey)) return cache.get(cacheKey);

  // 1. The headline itself — strictest, because a headline match means the
  //    page really is about this story.
  let result = await tryQuery(clean, 0.34);

  // 2. Named entities from the article body. These are exact subjects, so a
  //    near-exact title match is required rather than a loose overlap.
  if (!result) {
    for (const entity of entities.slice(0, 5)) {
      const e = String(entity || '').trim();
      // Only true multi-word named entities ("Southwest Monsoon", "Dam Safety
      // Act"). Single generic tags like "Health" or "Judiciary" are the
      // article's subject label, not its subject, and they resolve to
      // encyclopaedia pages whose lead image says nothing about the story.
      if (!/\s/.test(e) || e.length < 8) continue;
      if (/^GS Paper|^Prelims|^Mains|Facts$/i.test(e)) continue;
      // Near-exact page match required — the image must be OF this entity.
      result = await tryQuery(e, 0.75);
      if (result) break;
    }
  }

  // 3. Commons fallback on the headline.
  if (!result) result = await commonsSearch(clean);

  cache.set(cacheKey, result);
  return result;
}

/**
 * Fill in `imageUrl`/`imageCredit` for any article that has no artwork.
 * Mutates and returns the same array. Failures are non-fatal by design.
 */
export async function enrichImages(articles, { concurrency = 3, log = console.log } = {}) {
  const needy = articles.filter((a) => !a.imageUrl);
  if (needy.length === 0) return articles;

  log(`[Images] ${needy.length} article(s) without artwork — searching open sources…`);

  let cursor = 0;
  let found = 0;
  const runners = Array.from({ length: Math.min(concurrency, needy.length) }, async () => {
    while (cursor < needy.length) {
      const a = needy[cursor++];
      try {
        const hit = await findTopicImage(a.title, a.categoryTags || [], a.relatedTopics || []);
        if (hit) {
          a.imageUrl = hit.url;
          a.imageCredit = hit.credit;
          a.imageCreditUrl = hit.creditUrl;
          found++;
        }
      } catch { /* keep the generated cover */ }
    }
  });
  await Promise.all(runners);

  log(`[Images] matched ${found}/${needy.length}`);
  return articles;
}
