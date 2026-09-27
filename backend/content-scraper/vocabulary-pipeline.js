import {
  CONTENT_SCHEMA_VERSION,
  articleMetadata,
  generateVocabulary,
  normalizeVocabularyWord,
  primaryCategory,
  vocabularyId,
} from './generators.js';
import {
  extractDailyVocabularyDetailed,
  rankVocabularyCandidates,
} from './vocab-extract.js';

export const DEFAULT_MAX_VOCAB_DATES = 30;
export const DEFAULT_VOCAB_PER_DATE = 12;

function isBlank(value) {
  if (value === undefined || value === null) return true;
  if (typeof value === 'string') return value.trim() === '';
  if (Array.isArray(value)) return value.length === 0 || value.every(isBlank);
  if (typeof value === 'object') return Object.keys(value).length === 0;
  return false;
}

export function toIsoDate(value) {
  let candidate = value;
  if (candidate && typeof candidate.toDate === 'function') candidate = candidate.toDate();
  if (candidate instanceof Date) {
    if (Number.isNaN(candidate.getTime())) return '';
    return candidate.toISOString().slice(0, 10);
  }
  const text = String(candidate ?? '').trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return '';
  const parsed = new Date(`${text}T00:00:00Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === text ? text : '';
}

function stableArticleKey(article) {
  return [
    toIsoDate(article?.publishedDate),
    String(article?.id || ''),
    String(article?.sourceUrl || ''),
    String(article?.title || ''),
  ].join('|');
}

/**
 * Produce a deterministic, inclusive, bounded date plan. Invalid/undated
 * records are intentionally omitted: they cannot form a resumable checkpoint.
 */
export function planVocabularyDates(articles, {
  from = '',
  to = '',
  maxDates = DEFAULT_MAX_VOCAB_DATES,
} = {}) {
  const groups = new Map();
  for (const article of articles || []) {
    const date = toIsoDate(article?.publishedDate);
    if (!date || (from && date < from) || (to && date > to)) continue;
    if (!groups.has(date)) groups.set(date, []);
    groups.get(date).push(article);
  }
  for (const group of groups.values()) {
    group.sort((a, b) => stableArticleKey(a).localeCompare(stableArticleKey(b)));
  }

  const allDates = [...groups.keys()].sort();
  const boundedMax = Number.isFinite(maxDates)
    ? Math.max(0, Math.trunc(maxDates))
    : allDates.length;
  const dates = allDates.slice(0, boundedMax);
  return {
    dates,
    groups,
    totalMatchingDates: allDates.length,
    hasMore: dates.length < allDates.length,
    nextFrom: dates.length < allDates.length ? allDates[dates.length] : '',
  };
}

function requireValue(args, index, flag) {
  const value = args[index + 1];
  if (!value || value.startsWith('--')) throw new Error(`${flag} requires a value`);
  return value;
}

export function parseVocabularyBackfillArgs(args = process.argv.slice(2)) {
  const options = {
    from: '',
    to: '',
    maxDates: DEFAULT_MAX_VOCAB_DATES,
    vocabOnly: false,
    dryRun: false,
    help: false,
  };

  for (let index = 0; index < args.length; index++) {
    const flag = args[index];
    switch (flag) {
      case '--from': options.from = requireValue(args, index, flag); index++; break;
      case '--to': options.to = requireValue(args, index, flag); index++; break;
      case '--max-dates': {
        const raw = requireValue(args, index, flag);
        index++;
        const parsed = Number(raw);
        if (!Number.isInteger(parsed) || parsed < 1) {
          throw new Error('--max-dates must be a positive integer');
        }
        options.maxDates = parsed;
        break;
      }
      case '--vocab-only': options.vocabOnly = true; break;
      case '--dry-run': options.dryRun = true; break;
      case '--help':
      case '-h': options.help = true; break;
      default: throw new Error(`Unknown argument: ${flag}`);
    }
  }

  if (options.from && !toIsoDate(options.from)) throw new Error('--from must be YYYY-MM-DD');
  if (options.to && !toIsoDate(options.to)) throw new Error('--to must be YYYY-MM-DD');
  if (options.from && options.to && options.from > options.to) {
    throw new Error('--from must be on or before --to');
  }
  return options;
}

/** Merge by normalized lexical identity without replacing populated values. */
export function mergeVocabularyDocuments(...collections) {
  const byWord = new Map();
  for (const doc of collections.flat()) {
    const normalizedWord = normalizeVocabularyWord(doc?.normalizedWord || doc?.word);
    if (!normalizedWord) continue;
    const incoming = {
      ...doc,
      id: doc.id || vocabularyId(normalizedWord),
      normalizedWord,
    };
    const existing = byWord.get(normalizedWord);
    if (!existing) {
      byWord.set(normalizedWord, incoming);
      continue;
    }
    const merged = { ...existing };
    for (const [field, value] of Object.entries(incoming)) {
      if (isBlank(merged[field]) && !isBlank(value)) merged[field] = value;
    }
    byWord.set(normalizedWord, merged);
  }
  return [...byWord.values()].sort((a, b) => a.normalizedWord.localeCompare(b.normalizedWord));
}

function buildExistingCandidateEnrichments(articles, existingByWord, pool) {
  const docs = [];
  for (const item of rankVocabularyCandidates(articles).slice(0, Math.max(0, pool))) {
    const normalizedWord = normalizeVocabularyWord(item.word);
    const stored = existingByWord.get(normalizedWord);
    if (!stored) continue;
    const metadata = articleMetadata(item.article || {});
    const category = primaryCategory(item.article || {});
    const patchableMetadata = Object.entries(metadata).some(
      ([field, value]) => isBlank(stored[field]) && !isBlank(value)
    );
    const patchableCategory = /^(general|current affairs)?$/i.test(String(stored.category || '').trim()) &&
      !/^(general|current affairs)?$/i.test(category);
    if (Number(stored.schemaVersion || 0) >= CONTENT_SCHEMA_VERSION &&
        !patchableMetadata && !patchableCategory) {
      continue;
    }

    const preferred = { ...stored };
    for (const [field, value] of Object.entries(metadata)) {
      if (isBlank(preferred[field]) && !isBlank(value)) preferred[field] = value;
    }
    if (patchableCategory) preferred.category = category;
    docs.push({
      ...preferred,
      id: stored.id || vocabularyId(normalizedWord),
      schemaVersion: CONTENT_SCHEMA_VERSION,
      word: stored.word || (item.word.charAt(0).toUpperCase() + item.word.slice(1)),
      normalizedWord,
      upscUsage: stored.upscUsage || `Seen in ${metadata.newspaper || "today's"} coverage of ${category}${
        metadata.publishedDate ? ` on ${metadata.publishedDate}` : ''
      }.`,
    });
  }
  return docs;
}

function normalizeExistingState(existingByWord) {
  for (const [key, value] of [...existingByWord.entries()]) {
    const normalized = normalizeVocabularyWord(value?.normalizedWord || value?.word || key);
    if (!normalized) continue;
    if (!existingByWord.has(normalized)) existingByWord.set(normalized, value);
  }
  return existingByWord;
}

function updateExistingState(existingByWord, docs) {
  for (const doc of docs) {
    const key = normalizeVocabularyWord(doc.normalizedWord || doc.word);
    if (!key) continue;
    const held = existingByWord.get(key);
    existingByWord.set(key, held ? mergeVocabularyDocuments(held, doc)[0] : { ...doc });
  }
}

function uploadErrorCount(stats) {
  return Number(stats?.errors || 0);
}

/** Process and durably write one publication date. */
export async function processVocabularyDate({
  date,
  articles,
  existingByWord = new Map(),
  generatedVocabulary = null,
  limit = DEFAULT_VOCAB_PER_DATE,
  pool = 40,
  dryRun = false,
  extract = extractDailyVocabularyDetailed,
  upload,
  lookup,
  lookupOptions = {},
  failOnLookupErrors = false,
  log = console.log,
} = {}) {
  if (typeof upload !== 'function') throw new TypeError('upload must be a function');
  normalizeExistingState(existingByWord);
  const generated = generatedVocabulary || generateVocabulary(articles);
  const excludeWords = new Set(existingByWord.keys());
  const extractedResult = await extract(articles, {
    limit,
    pool,
    excludeWords,
    ...(lookup ? { lookup } : {}),
    lookupOptions,
    log,
  });
  const extracted = Array.isArray(extractedResult)
    ? { docs: extractedResult, stats: {} }
    : extractedResult;
  const extractionStats = {
    candidateCount: 0,
    excludedCount: 0,
    lookupCount: 0,
    attemptCount: 0,
    successCount: 0,
    missCount: 0,
    errorCount: 0,
    ...(extracted?.stats || {}),
  };

  if (failOnLookupErrors && extractionStats.errorCount > 0) {
    const error = new Error(
      `Vocabulary lookup failed for ${extractionStats.errorCount} candidate(s) on ${date}; date not completed`
    );
    error.code = 'VOCAB_LOOKUP_INCOMPLETE';
    error.date = date;
    error.stats = extractionStats;
    throw error;
  }

  const existingEnrichments = buildExistingCandidateEnrichments(articles, existingByWord, pool);
  const docs = mergeVocabularyDocuments(generated, existingEnrichments, extracted?.docs || [])
    .map((doc) => {
      const stored = existingByWord.get(normalizeVocabularyWord(doc.normalizedWord || doc.word));
      return stored?.id ? { ...doc, id: stored.id } : doc;
    });
  const uploadStats = docs.length
    ? await upload(docs, dryRun)
    : { uploaded: 0, skipped: 0, errors: 0 };
  if (uploadErrorCount(uploadStats) > 0) {
    const error = new Error(`Vocabulary upload failed on ${date}; date not completed`);
    error.code = 'VOCAB_UPLOAD_INCOMPLETE';
    error.date = date;
    error.stats = uploadStats;
    throw error;
  }

  updateExistingState(existingByWord, docs);
  log(
    `[VocabDate] date=${date} articles=${articles.length} docs=${docs.length} ` +
    `candidates=${extractionStats.candidateCount} lookups=${extractionStats.lookupCount} ` +
    `success=${extractionStats.successCount} errors=${extractionStats.errorCount} status=complete`
  );
  return { date, docs, extractionStats, uploadStats };
}

/**
 * Resumable historical runner. Every date is extracted and uploaded before the
 * next date begins; failures carry the failed date and never report it complete.
 */
export async function runHistoricalVocabulary({
  articles,
  from = '',
  to = '',
  maxDates = DEFAULT_MAX_VOCAB_DATES,
  limit = DEFAULT_VOCAB_PER_DATE,
  pool = 40,
  dryRun = false,
  existingByWord = new Map(),
  extract = extractDailyVocabularyDetailed,
  upload,
  lookup,
  lookupOptions = {},
  failOnLookupErrors = true,
  log = console.log,
} = {}) {
  const plan = planVocabularyDates(articles, { from, to, maxDates });
  log(
    `[VocabBackfill] dates=${plan.dates.length}/${plan.totalMatchingDates} ` +
    `from=${from || '*'} to=${to || '*'} maxDates=${maxDates} dryRun=${dryRun}`
  );

  const completedDates = [];
  const results = [];
  for (const date of plan.dates) {
    try {
      const result = await processVocabularyDate({
        date,
        articles: plan.groups.get(date),
        existingByWord,
        limit,
        pool,
        dryRun,
        extract,
        upload,
        lookup,
        lookupOptions,
        failOnLookupErrors,
        log,
      });
      results.push(result);
      completedDates.push(date);
    } catch (error) {
      error.completedDates = [...completedDates];
      error.nextFrom = date;
      throw error;
    }
  }

  const totals = results.reduce((sum, result) => ({
    docs: sum.docs + result.docs.length,
    lookups: sum.lookups + result.extractionStats.lookupCount,
    successes: sum.successes + result.extractionStats.successCount,
    lookupErrors: sum.lookupErrors + result.extractionStats.errorCount,
    uploaded: sum.uploaded + Number(result.uploadStats.uploaded || result.uploadStats.created || 0),
    skipped: sum.skipped + Number(result.uploadStats.skipped || result.uploadStats.unchanged || 0),
  }), { docs: 0, lookups: 0, successes: 0, lookupErrors: 0, uploaded: 0, skipped: 0 });

  log(
    `[VocabBackfill] completed=${completedDates.length} docs=${totals.docs} ` +
    `lookups=${totals.lookups} success=${totals.successes} errors=${totals.lookupErrors}`
  );
  if (plan.hasMore) log(`[VocabBackfill] resume with --from ${plan.nextFrom}`);
  return { ...plan, completedDates, results, totals };
}
