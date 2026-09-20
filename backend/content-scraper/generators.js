/**
 * Content Generators
 *
 * Derives supplementary UPSC study content from scraped article objects:
 *   - vocabulary  → `vocabulary` collection
 *   - flashcards  → `flashcards` collection
 *   - schemes     → `govtSchemes` collection
 *
 * These functions are pure: they take an array of article objects (the same
 * shape produced by scrapers.js) and return arrays of Firestore-ready docs.
 * No network, no file I/O — so they can be unit-tested and reused by both the
 * daily scraper and the PDF ingest script.
 */

import crypto from 'crypto';

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

function hashId(prefix, ...parts) {
  const h = crypto
    .createHash('md5')
    .update(parts.join('|').toLowerCase())
    .digest('hex')
    .slice(0, 16);
  return `${prefix}_${h}`;
}

function clean(str) {
  return (str || '').replace(/\s+/g, ' ').trim();
}

/** Find the first sentence in `text` that contains `term` (for usage examples). */
function findExampleSentence(text, term) {
  if (!text || !term) return '';
  const sentences = text.split(/(?<=[.!?])\s+/);
  const lower = term.toLowerCase();
  const hit = sentences.find(
    (s) => s.toLowerCase().includes(lower) && s.length > 25 && s.length < 260
  );
  return hit ? clean(hit) : '';
}

/** Map an article's primary category tag to a broad UPSC sector label. */
function primaryCategory(article) {
  const tags = article.categoryTags || [];
  const first = tags.find((t) => t && t.toLowerCase() !== 'general');
  return clean(first || tags[0] || 'General');
}

// ─────────────────────────────────────────────────────────────────────────────
// Vocabulary
// ─────────────────────────────────────────────────────────────────────────────

// Words too common to be worth a flashcard even if they look "hard".
const STOPWORDS = new Set([
  'India', 'Indian', 'Government', 'Minister', 'Ministry', 'National',
  'Central', 'State', 'Union', 'Committee', 'Report', 'Scheme', 'Policy',
  'Council', 'Board', 'Authority', 'Commission', 'Department', 'Programme',
  'Program', 'Mission', 'Yojana', 'January', 'February', 'March', 'April',
  'May', 'June', 'July', 'August', 'September', 'October', 'November',
  'December', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
  'Saturday', 'Sunday',
]);

/**
 * Build vocabulary docs from an article's `keyTerms` map. That map is the
 * cleanest source ({ term: definition }) since it is curated by the scraper.
 */
function vocabFromKeyTerms(article) {
  const out = [];
  const keyTerms = article.keyTerms || {};
  const category = primaryCategory(article);

  for (const [term, definition] of Object.entries(keyTerms)) {
    const word = clean(term);
    const meaning = clean(definition);
    if (!word || word.length < 3 || meaning.length < 15) continue;

    out.push({
      id: hashId('v', word),
      word,
      partOfSpeech: word.includes(' ') ? 'phrase' : 'noun',
      meaning,
      example: findExampleSentence(article.content, word),
      synonyms: [],
      antonyms: [],
      category,
      upscUsage: `Relevant to ${article.upscPaper || category} — appeared in current affairs on ${article.publishedDate}.`,
    });
  }
  return out;
}

/**
 * Generate vocabulary docs for a batch of articles.
 * De-duplicates by word (case-insensitive) within the batch.
 */
export function generateVocabulary(articles) {
  const byWord = new Map();

  for (const article of articles) {
    for (const doc of vocabFromKeyTerms(article)) {
      const key = doc.word.toLowerCase();
      if (!byWord.has(key)) byWord.set(key, doc);
    }
  }

  return [...byWord.values()];
}

// ─────────────────────────────────────────────────────────────────────────────
// Flashcards
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Generate flashcard docs (front/back/category) from articles.
 * Two kinds of cards:
 *   1. Term cards   — front = key term, back = its definition
 *   2. Concept cards — front = "Why in news: <title>?", back = summary
 */
/**
 * Split a structured body into "## Heading" → content blocks.
 * Bodies without headings yield nothing, which is correct — there is no
 * section to build a card from.
 */
function sections(content) {
  const out = [];
  let heading = null;
  let buf = [];

  const flush = () => {
    if (heading && buf.length) {
      const body = buf.join(' ').replace(/^[•◦]\s*/gm, '').replace(/\s+/g, ' ').trim();
      if (body.length > 40) out.push({ heading, body });
    }
    buf = [];
  };

  for (const line of (content || '').split('\n')) {
    const t = line.trim();
    if (!t) continue;
    const h = t.match(/^#{2,3}\s+(.+)$/);
    if (h) { flush(); heading = h[1].replace(/[:?]+$/, '').trim(); continue; }
    buf.push(t.replace(/^[•◦]\s*/, ''));
  }
  flush();
  return out;
}

/** Section names too generic to make a useful card front on their own. */
const WEAK_HEADING = /^(summary|context|source|introduction|conclusion|note|about|overview|background)$/i;

/** "X is a statutory body that …" — a definition worth its own card. */
const DEFINITION_RE = /^([A-Z][A-Za-z0-9 ()'&/-]{3,70}?)\s+(?:is|are|was|were|refers to|means|stands for|is defined as)\s+(.{25,300}?[.!])/;

/**
 * A definition card is only useful if the term is a name, not a clause.
 * "The capital, Skopje, is the birthplace of…" matches the definition shape but
 * its subject is a fragment — the comma is the giveaway.
 */
function isNamedTerm(term) {
  if (/[,;:]/.test(term)) return false;
  const words = term.split(/\s+/);
  if (words.length > 8) return false;
  if (/^(It|This|That|These|Those|There|He|She|They|Which|What|Such|Both|One|Some|Many|Most)\b/i.test(term)) return false;
  // A bare "The …" opener is usually a sentence subject rather than a name.
  if (/^The\s/i.test(term) && words.length <= 2) return false;
  return true;
}

/**
 * Generate flashcard docs from articles.
 *
 * Four kinds of card, in descending reliability:
 *   1. Term → definition, when a source supplies a glossary (`keyTerms`)
 *   2. Section cards — a "## What is X?" heading and the text under it
 *   3. Definition cards — "X is a …" sentences found in the body
 *   4. One concept card per article — "Why in news: <title>"
 *
 * Only (1) and (4) existed before, and no scraper populates keyTerms, so every
 * article produced exactly one card. Sections and definitions are where the
 * real volume is: a typical Drishti article carries six to ten of them.
 */
export function generateFlashcards(articles) {
  const byFront = new Map();

  const add = (front, back, article, category) => {
    const f = clean(front);
    const b = clean(back);
    if (!f || f.length < 6 || f.length > 160) return;
    if (b.length < 30) return;
    const key = f.toLowerCase().replace(/[^a-z0-9]/g, '');
    if (byFront.has(key)) return;
    byFront.set(key, {
      id: hashId('fc', f),
      front: f,
      back: b.slice(0, 600),
      category,
      newspaper: article.newspaper || '',
      publishedDate: article.publishedDate || '',
    });
  };

  for (const article of articles) {
    const category = primaryCategory(article);
    const title = clean(article.title);

    // 1. Curated glossary, when a source provides one.
    for (const [term, definition] of Object.entries(article.keyTerms || {})) {
      add(term, definition, article, category);
    }

    // 2. Section cards. A heading that already reads as a question becomes the
    //    front verbatim; a plain one is qualified with the article topic so the
    //    card still makes sense out of context.
    for (const { heading, body } of sections(article.content)) {
      if (WEAK_HEADING.test(heading)) continue;
      // A question heading stands alone. A plain one is qualified with the
      // article topic so the card still makes sense out of context — unless it
      // already names that topic, which would read "X of Y — Y".
      const isQuestion = /\?$|^(what|why|how|who|when|where|which)\b/i.test(heading);
      const words = (s) => new Set(s.toLowerCase().match(/[a-z]{4,}/g) || []);
      const headingWords = words(heading);
      const shared = [...words(title)].filter((w) => headingWords.has(w)).length;
      const front = isQuestion
        ? heading.replace(/\?*$/, '?')
        : (shared >= 2 ? heading : `${heading} — ${title}`);
      add(front, body, article, category);
    }

    // 3. Definitions stated in the prose.
    const plain = (article.content || '').replace(/^#{2,3}\s+.*$/gm, '').replace(/^[•◦]\s*/gm, '');
    for (const sentence of plain.split(/(?<=[.!?])\s+/)) {
      const m = sentence.trim().match(DEFINITION_RE);
      if (!m) continue;
      const term = m[1].trim();
      if (!isNamedTerm(term)) continue;
      add(term, sentence.trim(), article, category);
    }

    // 4. The article itself.
    const summary = clean(article.summary);
    if (title && summary.length > 40) {
      add(`Why in news: ${title}`, summary, article, category);
    }
  }

  return [...byFront.values()];
}

// ─────────────────────────────────────────────────────────────────────────────
// Key facts (the `dailyFacts` collection behind "UPSC Must Know")
// ─────────────────────────────────────────────────────────────────────────────

/** A fact is worth memorising when it pins down a number, date, body or law. */
const FACT_SIGNAL = /(\b\d{4}\b|\b\d+(\.\d+)?\s*(%|per cent|crore|lakh|billion|million|km|GW|MW|tonnes?)\b|Article\s+\d+|Section\s+\d+|Schedule\b|Amendment\b|Convention\b|Treaty\b|Protocol\b|Mission\b|Yojana\b|Act,?\s+\d{4}|established|launched|headquarters|ranked|largest|first\b)/i;

/** Sentences that reference the news cycle rather than stating a durable fact. */
const NOT_A_FACT = /(recently|last week|yesterday|today|this week|has been in the news|why in news|according to the article)/i;

/**
 * Build `dailyFacts` docs — one per article, grouped by subject.
 *
 * The Must Know screen merges these with its built-in bank, so every article
 * ingested adds to what the screen can teach. Nothing wrote this collection
 * before, which is why the screen only ever showed its static content.
 */
export function generateKeyFacts(articles, { perArticle = 6 } = {}) {
  const out = [];

  for (const article of articles) {
    const category = primaryCategory(article);
    const title = clean(article.title);
    if (!title) continue;

    const seen = new Set();
    const facts = [];

    // Curated bullets first — they are already condensed.
    const candidates = [
      ...(article.keyPoints || []),
      ...(article.shortNotes || []),
      ...(article.content || '')
        .split('\n')
        .filter((l) => /^[•◦]\s/.test(l.trim()))
        .map((l) => l.replace(/^[•◦]\s*/, '')),
      ...(article.content || '')
        .replace(/^#{2,3}\s+.*$/gm, '')
        .split(/(?<=[.!?])\s+/),
    ];

    for (const raw of candidates) {
      const fact = clean(raw);
      if (fact.length < 45 || fact.length > 260) continue;
      if (!FACT_SIGNAL.test(fact)) continue;
      if (NOT_A_FACT.test(fact)) continue;
      const key = fact.toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 60);
      if (seen.has(key)) continue;
      seen.add(key);
      facts.push(fact);
      if (facts.length >= perArticle) break;
    }

    if (facts.length < 2) continue; // not worth a card

    out.push({
      id: hashId('kf', title),
      category,
      title,
      facts,
      publishedDate: article.publishedDate || '',
      newspaper: article.newspaper || '',
    });
  }

  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Government schemes
// ─────────────────────────────────────────────────────────────────────────────

// Patterns that reliably indicate a government scheme / mission / programme.
const SCHEME_PATTERNS = [
  /\b((?:Pradhan Mantri|PM[- ])[A-Z][\w'-]*(?:\s+[A-Z][\w'-]*){0,4})\b/g,
  /\b([A-Z][\w'-]*(?:\s+[A-Z][\w'-]*){0,4}\s+Yojana)\b/g,
  /\b([A-Z][\w'-]*(?:\s+[A-Z][\w'-]*){0,4}\s+Abhiyan)\b/g,
  /\b([A-Z][\w'-]*(?:\s+[A-Z][\w'-]*){0,3}\s+Mission)\b/g,
  /\b([A-Z][\w'-]*(?:\s+[A-Z][\w'-]*){0,3}\s+Scheme)\b/g,
];

const SECTOR_KEYWORDS = [
  ['Health', ['health', 'ayushman', 'medical', 'hospital', 'disease']],
  ['Agriculture', ['farmer', 'agri', 'crop', 'kisan', 'irrigation']],
  ['Education', ['education', 'school', 'student', 'skill', 'literacy']],
  ['Women & Child', ['women', 'child', 'girl', 'mahila', 'beti']],
  ['Rural', ['rural', 'gram', 'village', 'panchayat', 'mgnrega']],
  ['Financial', ['bank', 'loan', 'credit', 'insurance', 'pension', 'jan dhan']],
  ['Infrastructure', ['road', 'housing', 'awas', 'smart city', 'transport']],
  ['Energy', ['solar', 'energy', 'power', 'ujjwala', 'lpg', 'electricity']],
];

function guessSector(text) {
  const lower = (text || '').toLowerCase();
  for (const [sector, keys] of SECTOR_KEYWORDS) {
    if (keys.some((k) => lower.includes(k))) return sector;
  }
  return 'Governance';
}

function acronym(name) {
  const words = name.split(/\s+/).filter((w) => /^[A-Z]/.test(w) && w.length > 2);
  return words.length >= 2 ? words.map((w) => w[0]).join('') : '';
}

/**
 * The administering body, read out of the article text.
 *
 * Only ever reports a ministry the source actually names. Guessing one from the
 * sector would be worse than leaving it blank: "which ministry runs this" is
 * examinable, and a plausible-looking wrong answer is what a reader would
 * memorise.
 */
// Ministry names carry commas and conjunctions ("Ministry of Micro, Small and
// Medium Enterprises"), so the continuation allows ", ", " and ", " & " and a
// plain space. A lowercase word ends the match, which is what stops it running
// into the rest of the sentence.
const MINISTRY_RE =
  /\b(Ministry|Department)\s+of\s+([A-Z][A-Za-z&'-]*(?:(?:,\s+|\s+and\s+|\s+&\s+|\s+of\s+|\s+)[A-Z][A-Za-z&'-]*){0,6})/g;

function findMinistry(text) {
  if (!text) return '';
  MINISTRY_RE.lastIndex = 0;
  const counts = new Map();
  let m;
  while ((m = MINISTRY_RE.exec(text)) !== null) {
    const name = clean(`${m[1]} of ${m[2]}`)
        .replace(/[,\s]+(and|of|&)$/i, '')
        .replace(/[,\s]+$/, '');
    if (name.length > 80) continue;
    counts.set(name, (counts.get(name) ?? 0) + 1);
  }
  if (counts.size === 0) return '';
  // The most frequently named body wins; ties go to the longer, more specific
  // name ("Ministry of Health and Family Welfare" over "Ministry of Health").
  return [...counts.entries()].sort(
    (a, b) => b[1] - a[1] || b[0].length - a[0].length
  )[0][0];
}

/**
 * Which GS paper a sector belongs to. This is syllabus mapping, not a claim
 * about the scheme, so it is safe to state without the article saying it.
 */
const SECTOR_PAPER = {
  Health: 'GS-II — Issues relating to development and management of Social Sector/Services (Health)',
  Agriculture: 'GS-III — Issues related to direct and indirect farm subsidies, agricultural marketing',
  Education: 'GS-II — Issues relating to development and management of Social Sector/Services (Education)',
  'Women & Child': 'GS-I / GS-II — Role of women, and welfare schemes for vulnerable sections',
  Rural: 'GS-II — Welfare schemes for vulnerable sections and rural development',
  Financial: 'GS-III — Inclusive growth, mobilisation of resources and financial inclusion',
  Infrastructure: 'GS-III — Infrastructure: energy, ports, roads, airports and railways',
  Energy: 'GS-III — Infrastructure and energy; conservation and environmental impact',
  Governance: 'GS-II — Government policies and interventions for development in various sectors',
};

/**
 * A short note on why the scheme matters for the exam. Built only from the
 * sector mapping, the administering body and the launch year — all of which are
 * either syllabus facts or values read from the source. It deliberately makes no
 * claim about outcomes or scale.
 */
function schemeRelevance({ sector, ministry, year }) {
  const paper = SECTOR_PAPER[sector] || SECTOR_PAPER.Governance;
  const parts = [paper + '.'];
  if (ministry && year) {
    parts.push(`Administered by the ${ministry}; appeared in coverage from ${year}.`);
  } else if (ministry) {
    parts.push(`Administered by the ${ministry}.`);
  } else if (year) {
    parts.push(`Appeared in coverage from ${year}.`);
  }
  parts.push(
    'Expect questions pairing the scheme with its ministry, objective and target group.'
  );
  return parts.join(' ');
}

/**
 * A real quantity, date or legal reference — the kind of detail worth revising.
 * Unlike FACT_SIGNAL this does NOT treat "Yojana"/"Mission"/"launched" as
 * signals, because every candidate sentence already names the scheme.
 */
const SCHEME_FIGURE =
  /(\b\d{4}\b|\b\d+(?:\.\d+)?\s*(?:%|per ?cent|crore|lakh|billion|million|km|GW|MW|tonnes?|rupees?)\b|\bRs\.?\s*\d|\bArticle\s+\d+|\bSection\s+\d+|\b\d+\s+(?:trades|districts|states|villages|beneficiaries|artisans|families|years|days|months|tranches)\b)/i;

/**
 * Concrete, checkable sentences about the scheme, pulled from the article.
 *
 * Reuses the key-fact signal (figures, years, Articles, targets) so the bullets
 * are the kind of detail worth revising rather than narrative filler. Returns []
 * when the source has nothing specific — the app omits the section entirely
 * rather than showing an empty heading.
 */
function schemeFeatures(text, name, { limit = 4 } = {}) {
  if (!text || !name) return [];
  const lower = name.toLowerCase();
  const seen = new Set();
  const out = [];
  for (const raw of text.split(/(?<=[.!?])\s+/)) {
    const s = clean(raw);
    if (s.length < 40 || s.length > 240) continue;
    if (!s.toLowerCase().includes(lower)) continue;
    // SCHEME_FIGURE rather than FACT_SIGNAL: FACT_SIGNAL counts "Yojana" and
    // "Mission" as signals, which every one of these sentences contains by
    // definition, so it would promote "Cabinet has approved the X Yojana" to a
    // key feature. Require an actual figure, date or legal reference.
    if (!SCHEME_FIGURE.test(s) || NOT_A_FACT.test(s)) continue;
    const key = s.toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 60);
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(s);
    if (out.length >= limit) break;
  }
  return out;
}

/**
 * A fuller body for the detail sheet: the sentences around the scheme mention,
 * rather than the single sentence used on the card.
 */
function schemeDetail(text, name, { sentences = 3 } = {}) {
  if (!text || !name) return '';
  const all = text.split(/(?<=[.!?])\s+/).map(clean).filter(Boolean);
  const lower = name.toLowerCase();
  const at = all.findIndex((s) => s.toLowerCase().includes(lower));
  if (at === -1) return '';
  const picked = all.slice(at, at + sentences).join(' ');
  return picked.length > 900 ? picked.slice(0, 900).trim() : picked;
}

/**
 * Detect government schemes mentioned across articles and build `govtSchemes`
 * docs. Uses the explicit `governmentScheme` field when present, plus pattern
 * matching on title/content.
 */
/**
 * Tidy a detected scheme name.
 *
 * Pattern matching over article text picks up the same scheme in several
 * surface forms — with a leading article ("The Mobile Phone Manufacturing
 * Scheme"), or with the phrase accidentally doubled where the text repeated it
 * ("Gaganyaan Mission Gaganyaan Mission"). Left alone these become separate
 * entries and the Govt Schemes tab fills with near-duplicates.
 */
function tidySchemeName(raw) {
  let name = clean(raw).replace(/[.,;:]+$/, '').replace(/^(the|a|an)\s+/i, '');

  // Collapse an exactly-doubled phrase.
  const words = name.split(/\s+/);
  if (words.length % 2 === 0) {
    const half = words.length / 2;
    if (words.slice(0, half).join(' ').toLowerCase() === words.slice(half).join(' ').toLowerCase()) {
      name = words.slice(0, half).join(' ');
    }
  }

  // Trim a reporting verb that got swept into the match.
  name = name.replace(/^(PM|Government|Centre|Cabinet)\s+(Announces?|Launches?|Approves?|Unveils?)\s+/i, '');

  return name;
}

/** Key used to merge surface variants of one scheme. */
function schemeKey(name) {
  return name.toLowerCase().replace(/[^a-z0-9]/g, '');
}

/**
 * Names that describe a *category* of scheme rather than naming one. They match
 * the patterns perfectly and tell a reader nothing.
 */
const GENERIC_SCHEME = /^(centrally sponsored|central sector|authorised use|state sponsored|government|national|new|old|special|various|other|similar|such|this|that|above|following|flagship|umbrella)\s+(scheme|mission|programme|program|yojana)s?$/i;

export function generateSchemes(articles) {
  const byName = new Map();

  const add = (rawName, article) => {
    const name = tidySchemeName(rawName);
    if (!name || name.length < 6 || name.length > 90) return;
    if (GENERIC_SCHEME.test(name)) return;
    // Skip obvious false positives (single generic word before Scheme/Mission).
    const words = name.split(/\s+/);
    if (words.length < 2) return;

    const key = schemeKey(name);
    if (byName.has(key)) return;

    const context = `${article.title} ${article.summary}`;
    const body = `${article.title}\n${article.summary || ''}\n${article.content || ''}`;
    const sector = guessSector(context);
    const year = String(new Date(article.publishedDate || Date.now()).getFullYear());
    const ministry = findMinistry(body);

    byName.set(key, {
      id: hashId('gs', name),
      name,
      fullForm: acronym(name),
      description:
        findExampleSentence(article.content, name) ||
        clean(article.summary).slice(0, 220),
      // The detail sheet reads detailedDescription / keyFeatures /
      // upscRelevance. Leaving them unset is what made every scraper-derived
      // scheme open to a near-empty sheet.
      detailedDescription:
        schemeDetail(article.content, name) || clean(article.summary),
      keyFeatures: schemeFeatures(article.content, name),
      upscRelevance: schemeRelevance({ sector, ministry, year }),
      ministry,
      sector,
      year,
      iconName: '',
      colorHex: '',
    });
  };

  for (const article of articles) {
    if (article.governmentScheme) add(article.governmentScheme, article);

    const haystack = `${article.title}\n${article.content || ''}`;
    for (const pattern of SCHEME_PATTERNS) {
      let m;
      pattern.lastIndex = 0;
      while ((m = pattern.exec(haystack)) !== null) {
        const candidate = m[1];
        if (candidate && !STOPWORDS.has(candidate.split(/\s+/)[0])) {
          add(candidate, article);
        }
      }
    }
  }

  return [...byName.values()];
}

// ─────────────────────────────────────────────────────────────────────────────
// Daily current-affairs quiz
// ─────────────────────────────────────────────────────────────────────────────

function stableRank(seed, value) {
  return crypto.createHash('sha256').update(`${seed}|${value}`).digest('hex');
}

function orderedOptions(correct, distractors, seed) {
  const unique = [correct, ...distractors]
    .map(clean)
    .filter((value, index, all) => value && all.indexOf(value) === index)
    .slice(0, 4);
  if (unique.length !== 4) return null;
  unique.sort((a, b) => stableRank(seed, a).localeCompare(stableRank(seed, b)));
  return { options: unique, correctAnswerIndex: unique.indexOf(clean(correct)) };
}

/**
 * Generate a stable quiz for one publication date. The same articles always
 * produce the same IDs, question order and option order, so re-runs are safe.
 */
export function generateDailyQuiz(articles, dateStr, { limit = 10 } = {}) {
  const usable = [...articles]
    .filter((article) => clean(article.title))
    .sort((a, b) => clean(a.title).localeCompare(clean(b.title)));
  const candidates = [];
  const seenQuestions = new Set();

  const add = (question, correct, distractors, article, type, explanation) => {
    const q = clean(question);
    if (!q || seenQuestions.has(q.toLowerCase())) return;
    const arranged = orderedOptions(correct, distractors, `${dateStr}|${article.id}|${type}`);
    if (!arranged) return;
    seenQuestions.add(q.toLowerCase());
    candidates.push({
      id: hashId('dq', dateStr, article.id || article.title, type),
      question: q,
      options: arranged.options,
      correctAnswerIndex: arranged.correctAnswerIndex,
      explanation: clean(explanation).slice(0, 500),
      category: primaryCategory(article),
      difficulty: type === 'term' ? 'Medium' : 'Easy',
      articleRef: article.id || '',
      syllabusArea: clean(article.syllabusMapping || article.upscPaper || ''),
      source: 'daily_news',
      publishedDate: dateStr,
      sourceTitle: clean(article.title),
      sourceUrl: clean(article.sourceUrl || ''),
    });
  };

  // Strongest questions: key-term definitions with definitions from other
  // articles as plausible distractors.
  const terms = usable.flatMap((article) => Object.entries(article.keyTerms || {})
    .map(([term, definition]) => ({ article, term: clean(term), definition: clean(definition) }))
    .filter((item) => item.term.length > 2 && item.definition.length > 20));
  for (const item of terms) {
    const distractors = terms
      .filter((other) => other.term.toLowerCase() !== item.term.toLowerCase())
      .map((other) => other.definition);
    add(
      `In today’s current affairs, what does “${item.term}” mean?`,
      item.definition,
      distractors,
      item.article,
      'term',
      `${item.term}: ${item.definition} Source: ${item.article.title}`,
    );
  }

  // Article comprehension questions: identify the key finding attached to one
  // headline. Distractors come from other articles published the same day.
  const keyPointItems = usable
    .map((article) => ({ article, point: clean((article.keyPoints || [])[0] || (article.shortNotes || [])[0]) }))
    .filter((item) => item.point.length >= 25 && item.point.length <= 220);
  for (const item of keyPointItems) {
    const distractors = keyPointItems
      .filter((other) => other.article.id !== item.article.id)
      .map((other) => other.point);
    add(
      `Which statement is linked to “${clean(item.article.title)}”?`,
      item.point,
      distractors,
      item.article,
      'key-point',
      `${item.point} This was a key point in ${item.article.title}.`,
    );
  }

  // Category questions guarantee a useful fallback on sparse days.
  const categoryPool = [...new Set(usable.map(primaryCategory))];
  const defaultCategories = ['Polity', 'Economy', 'Environment', 'Science & Technology', 'International Relations', 'Social Issues'];
  for (const article of usable) {
    const correct = primaryCategory(article);
    const distractors = [...categoryPool, ...defaultCategories].filter((value) => value !== correct);
    add(
      `Which UPSC subject best matches “${clean(article.title)}”?`,
      correct,
      distractors,
      article,
      'category',
      `The article is classified under ${correct}${article.upscPaper ? ` (${article.upscPaper})` : ''}.`,
    );
  }

  candidates.sort((a, b) => stableRank(dateStr, a.id).localeCompare(stableRank(dateStr, b.id)));
  return candidates.slice(0, limit);
}

/** Convenience: run all library generators. */
export function generateAll(articles) {
  return {
    vocabulary: generateVocabulary(articles),
    flashcards: generateFlashcards(articles),
    schemes: generateSchemes(articles),
    keyFacts: generateKeyFacts(articles),
  };
}
