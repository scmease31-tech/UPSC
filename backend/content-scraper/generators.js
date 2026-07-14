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
export function generateFlashcards(articles) {
  const byFront = new Map();

  for (const article of articles) {
    const category = primaryCategory(article);

    // 1. Term → definition cards (highest quality, straight from keyTerms)
    for (const [term, definition] of Object.entries(article.keyTerms || {})) {
      const front = clean(term);
      const back = clean(definition);
      if (!front || back.length < 15) continue;
      const key = front.toLowerCase();
      if (!byFront.has(key)) {
        byFront.set(key, {
          id: hashId('fc', front),
          front,
          back,
          category,
          newspaper: article.newspaper || '',
          publishedDate: article.publishedDate || '',
        });
      }
    }

    // 2. Concept card from the article itself
    const title = clean(article.title);
    const summary = clean(article.summary);
    if (title && summary.length > 40) {
      const front = `Why in news: ${title}`;
      const key = front.toLowerCase();
      if (!byFront.has(key)) {
        byFront.set(key, {
          id: hashId('fc', title),
          front,
          back: summary.slice(0, 400),
          category,
          newspaper: article.newspaper || '',
          publishedDate: article.publishedDate || '',
        });
      }
    }
  }

  return [...byFront.values()];
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
 * Detect government schemes mentioned across articles and build `govtSchemes`
 * docs. Uses the explicit `governmentScheme` field when present, plus pattern
 * matching on title/content.
 */
export function generateSchemes(articles) {
  const byName = new Map();

  const add = (rawName, article) => {
    const name = clean(rawName).replace(/[.,;:]+$/, '');
    if (!name || name.length < 6 || name.length > 90) return;
    // Skip obvious false positives (single generic word before Scheme/Mission).
    const words = name.split(/\s+/);
    if (words.length < 2) return;

    const key = name.toLowerCase();
    if (byName.has(key)) return;

    const context = `${article.title} ${article.summary}`;
    byName.set(key, {
      id: hashId('gs', name),
      name,
      fullForm: acronym(name),
      description:
        findExampleSentence(article.content, name) ||
        clean(article.summary).slice(0, 220),
      sector: guessSector(context),
      year: String(new Date(article.publishedDate || Date.now()).getFullYear()),
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

/**
 * Convenience: run all generators and return a keyed result.
 */
export function generateAll(articles) {
  return {
    vocabulary: generateVocabulary(articles),
    flashcards: generateFlashcards(articles),
    schemes: generateSchemes(articles),
  };
}
