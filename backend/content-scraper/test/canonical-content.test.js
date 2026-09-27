import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

import { runBackfill } from '../backfill.js';
import {
  nextCheckpoint,
  runCheckpointedVocabulary,
} from '../resume-vocabulary-backfill.js';
import {
  CONTENT_SCHEMA_VERSION,
  flashcardId,
  generateFlashcards,
  generateKeyFacts,
  generateSchemes,
  generateVocabulary,
} from '../generators.js';
import {
  extractDailyVocabularyDetailed,
  lookupDictionaryWord,
  rankVocabularyCandidates,
} from '../vocab-extract.js';
import {
  parseVocabularyBackfillArgs,
  planVocabularyDates,
  processVocabularyDate,
  runHistoricalVocabulary,
} from '../vocabulary-pipeline.js';
import {
  canonicalEnrichmentPatch,
  FLASHCARD_ENRICHMENT_FIELDS,
  persistDerivedLibraries,
  schemeEnrichmentPatch,
  upsertVocabularyFromIndex,
  vocabularyEnrichmentPatch,
} from '../uploader.js';

const article = {
  id: 'article-2026-10-01-a',
  title: 'Editorial rhetoric and public reasoning',
  summary: 'A detailed editorial examines difficult language used in public institutions and constitutional debate.',
  content: [
    '## Editorial vocabulary',
    'The perspicacious observer identified obfuscatory rhetoric in a carefully reasoned constitutional discussion.',
    'Persistent intransigence complicated reconciliation while circumlocution obscured the central argument.',
  ].join('\n'),
  keyTerms: {
    'Constitutional morality': 'A principle requiring public institutions to act consistently with constitutional values.',
  },
  categoryTags: ['Science and Technology'],
  upscPaper: 'GS-II',
  sourceUrl: 'https://example.test/editorial',
  newspaper: 'Test Daily',
  publishedDate: '2026-10-01',
};

function dictionaryEntry(word = 'word') {
  return {
    partOfSpeech: 'adjective',
    meaning: `A sufficiently detailed dictionary definition for ${word}.`,
    synonyms: ['clear-sighted'],
    antonyms: ['unperceptive'],
  };
}

test('candidate ranking excludes ordinary words and is deterministic', () => {
  const first = rankVocabularyCandidates([article]);
  const repeat = rankVocabularyCandidates([article]);
  assert.deepEqual(first.map((item) => item.word), repeat.map((item) => item.word));
  assert.ok(first.some((item) => item.word === 'perspicacious'));
  assert.ok(first.some((item) => item.word === 'obfuscatory'));
  assert.ok(!first.some((item) => item.word === 'constitutional'));
});

test('extractor applies pool, exclusion, and limit before injected lookups', async () => {
  const ranked = rankVocabularyCandidates([article]);
  assert.ok(ranked.length >= 3);
  const excluded = ranked[0].word;
  const calls = [];
  const { docs, stats } = await extractDailyVocabularyDetailed([article], {
    limit: 1,
    pool: 3,
    concurrency: 1,
    excludeWords: new Set([excluded.toUpperCase()]),
    lookup: async (word) => {
      calls.push(word);
      return dictionaryEntry(word);
    },
    log: () => {},
  });

  assert.equal(docs.length, 1);
  assert.equal(stats.candidateCount, 3);
  assert.equal(stats.excludedCount, 1);
  assert.equal(stats.lookupCount, 1);
  assert.ok(!calls.includes(excluded), 'existing words must be excluded before lookup');
  assert.equal(docs[0].articleRef, article.id);
  assert.equal(docs[0].sourceUrl, article.sourceUrl);
  assert.equal(docs[0].upscPaper, article.upscPaper);
  assert.equal(docs[0].schemaVersion, CONTENT_SCHEMA_VERSION);
});

test('dictionary lookup retries bounded transient failures with observable backoff', async () => {
  const responses = [
    { ok: false, status: 500 },
    { ok: false, status: 429 },
    {
      ok: true,
      status: 200,
      json: async () => [{
        meanings: [{
          partOfSpeech: 'noun',
          synonyms: ['clarity'],
          definitions: [{ definition: 'A detailed definition returned after bounded retries.' }],
        }],
      }],
    },
  ];
  const sleeps = [];
  const statuses = [];
  const result = await lookupDictionaryWord('perspicacious', {
    fetchImpl: async () => responses.shift(),
    retries: 2,
    baseDelayMs: 10,
    maxDelayMs: 100,
    jitterRatio: 0,
    sleep: async (ms) => sleeps.push(ms),
    onStatus: (status) => statuses.push(status.status),
  });

  assert.equal(result.status, 'success');
  assert.equal(result.attempts, 3);
  assert.deepEqual(sleeps, [10, 20]);
  assert.deepEqual(statuses, ['retry', 'retry', 'success']);
});

test('dictionary 404 is a final miss and never retries', async () => {
  let calls = 0;
  const result = await lookupDictionaryWord('notaword', {
    fetchImpl: async () => {
      calls++;
      return { ok: false, status: 404 };
    },
    retries: 4,
    sleep: async () => assert.fail('404 must not back off'),
  });
  assert.equal(result.status, 'not_found');
  assert.equal(result.attempts, 1);
  assert.equal(calls, 1);
});

test('date planning is inclusive, deterministic, bounded, and resumable', () => {
  const articles = [
    { id: 'z', publishedDate: '2026-10-03' },
    { id: 'b', publishedDate: '2026-10-02' },
    { id: 'a', publishedDate: '2026-10-02' },
    { id: 'old', publishedDate: '2026-10-01' },
    { id: 'bad', publishedDate: 'not-a-date' },
  ];
  const plan = planVocabularyDates(articles, {
    from: '2026-10-02',
    to: '2026-10-03',
    maxDates: 1,
  });
  assert.deepEqual(plan.dates, ['2026-10-02']);
  assert.deepEqual(plan.groups.get('2026-10-02').map((item) => item.id), ['a', 'b']);
  assert.equal(plan.hasMore, true);
  assert.equal(plan.nextFrom, '2026-10-03');
});

test('backfill argument parsing supports all bounded vocabulary controls', () => {
  assert.deepEqual(
    parseVocabularyBackfillArgs([
      '--from', '2026-09-16', '--to', '2026-10-15', '--max-dates', '7',
      '--vocab-only', '--dry-run',
    ]),
    {
      from: '2026-09-16',
      to: '2026-10-15',
      maxDates: 7,
      vocabOnly: true,
      dryRun: true,
      help: false,
    },
  );
  assert.throws(() => parseVocabularyBackfillArgs(['--max-dates', '0']), /positive integer/);
  assert.throws(
    () => parseVocabularyBackfillArgs(['--from', '2026-10-02', '--to', '2026-10-01']),
    /on or before/,
  );
});

test('historical vocabulary alternates extraction and immediate upload per date', async () => {
  const events = [];
  const articles = ['2026-10-01', '2026-10-02', '2026-10-03'].map((date) => ({
    id: `article-${date}`,
    title: date,
    content: '',
    keyTerms: {},
    publishedDate: date,
  }));
  const result = await runHistoricalVocabulary({
    articles,
    maxDates: 2,
    existingByWord: new Map(),
    extract: async (group) => {
      const date = group[0].publishedDate;
      events.push(`extract:${date}`);
      return {
        docs: [{
          id: `v-${date}`,
          word: `Lexeme ${date}`,
          normalizedWord: `lexeme ${date}`,
          meaning: 'A valid injected definition for an incremental test.',
        }],
        stats: { candidateCount: 1, lookupCount: 1, successCount: 1, errorCount: 0 },
      };
    },
    upload: async (docs) => {
      const date = docs[0].word.slice(-10);
      events.push(`upload:${date}`);
      return { uploaded: docs.length, skipped: 0, errors: 0 };
    },
    log: () => {},
  });

  assert.deepEqual(events, [
    'extract:2026-10-01', 'upload:2026-10-01',
    'extract:2026-10-02', 'upload:2026-10-02',
  ]);
  assert.deepEqual(result.completedDates, ['2026-10-01', '2026-10-02']);
  assert.equal(result.nextFrom, '2026-10-03');
});

test('historical runner stops on a failed date and reports the exact resume point', async () => {
  const dates = ['2026-10-01', '2026-10-02', '2026-10-03'];
  let uploads = 0;
  await assert.rejects(
    runHistoricalVocabulary({
      articles: dates.map((date) => ({ id: date, title: date, publishedDate: date, keyTerms: {} })),
      maxDates: 3,
      extract: async (group) => ({
        docs: [{ id: `v-${group[0].id}`, word: group[0].id, meaning: 'injected meaning' }],
        stats: { errorCount: 0 },
      }),
      upload: async () => ({ uploaded: 1, skipped: 0, errors: ++uploads === 2 ? 1 : 0 }),
      log: () => {},
    }),
    (error) => {
      assert.equal(error.nextFrom, '2026-10-02');
      assert.deepEqual(error.completedDates, ['2026-10-01']);
      return true;
    },
  );
  assert.equal(uploads, 2);
});

test('a rerun with shared lexical state performs no duplicate lookup or write', async () => {
  const existingByWord = new Map();
  let extractionCalls = 0;
  let uploads = 0;
  const extract = async (_articles, { excludeWords }) => {
    extractionCalls++;
    if (excludeWords.has('perspicacious')) return { docs: [], stats: { errorCount: 0 } };
    return {
      docs: [{
        id: 'v-test',
        schemaVersion: 2,
        word: 'Perspicacious',
        normalizedWord: 'perspicacious',
        meaning: 'A perceptive and discerning quality.',
        category: 'Science & Technology',
        articleRef: article.id,
        sourceUrl: article.sourceUrl,
        upscPaper: article.upscPaper,
        publishedDate: article.publishedDate,
        newspaper: article.newspaper,
      }],
      stats: { lookupCount: 1, successCount: 1, errorCount: 0 },
    };
  };
  const options = {
    date: '2026-10-01',
    articles: [{ ...article, keyTerms: {} }],
    existingByWord,
    extract,
    upload: async (docs) => {
      uploads++;
      return { uploaded: docs.length, skipped: 0, errors: 0 };
    },
    log: () => {},
  };
  await processVocabularyDate(options);
  await processVocabularyDate(options);
  assert.equal(extractionCalls, 2);
  assert.equal(uploads, 1);
});

test('vocabulary enrichment improves placeholders but preserves curated values', () => {
  const incoming = {
    schemaVersion: 2,
    word: 'Perspicacious',
    meaning: 'Having a ready insight into things and strong discernment.',
    partOfSpeech: 'adjective',
    category: 'Ethics',
    example: 'The perspicacious officer identified the hidden conflict of interest.',
    articleRef: 'article-1',
  };
  const weak = vocabularyEnrichmentPatch({
    schemaVersion: 1,
    word: 'Perspicacious',
    meaning: 'insightful',
    partOfSpeech: 'word',
    category: 'General',
    example: 'short example',
  }, incoming);
  assert.equal(weak.meaning, incoming.meaning);
  assert.equal(weak.partOfSpeech, 'adjective');
  assert.equal(weak.category, 'Ethics');
  assert.equal(weak.example, incoming.example);
  assert.equal(weak.schemaVersion, 2);

  const curated = vocabularyEnrichmentPatch({
    meaning: 'A hand-curated definition that must remain authoritative.',
    partOfSpeech: 'adjective',
    category: 'Essay',
  }, incoming);
  assert.ok(!('meaning' in curated));
  assert.ok(!('partOfSpeech' in curated));
  assert.ok(!('category' in curated));
});

test('flashcard fill enrichment never overwrites curated front or back', () => {
  const patch = canonicalEnrichmentPatch({
    schemaVersion: 1,
    front: 'Curated question?',
    back: 'Curated answer with sufficient detail.',
    category: 'Polity',
  }, {
    schemaVersion: 2,
    front: 'Generated question?',
    back: 'Generated answer that must not replace the curated value.',
    category: 'Economy',
    articleRef: 'article-1',
    kind: 'section',
  }, FLASHCARD_ENRICHMENT_FIELDS);
  assert.equal(patch.schemaVersion, 2);
  assert.equal(patch.articleRef, 'article-1');
  assert.equal(patch.kind, 'section');
  assert.ok(!('front' in patch));
  assert.ok(!('back' in patch));
  assert.ok(!('category' in patch));
});

test('generated vocabulary, flashcards, and Must Know facts carry canonical metadata', () => {
  const factual = {
    ...article,
    keyPoints: [
      'Article 51 of the Constitution directs the State to promote international peace and security.',
      'The Constitutional framework entered into force in 1950 after adoption by the Constituent Assembly.',
    ],
  };
  const vocabulary = generateVocabulary([factual]);
  const flashcards = generateFlashcards([factual]);
  const facts = generateKeyFacts([factual]);
  assert.ok(vocabulary.length > 0);
  assert.ok(flashcards.length > 0);
  assert.ok(facts.length > 0);

  for (const doc of [...vocabulary, ...flashcards, ...facts]) {
    assert.equal(doc.schemaVersion, 2);
    assert.equal(doc.articleRef, article.id);
    assert.equal(doc.sourceUrl, article.sourceUrl);
    assert.equal(doc.upscPaper, article.upscPaper);
    assert.equal(doc.publishedDate, article.publishedDate);
    assert.equal(doc.newspaper, article.newspaper);
  }
  for (const card of flashcards) {
    assert.ok(['term', 'section', 'definition', 'why_in_news'].includes(card.kind));
    assert.equal(card.category, 'Science & Technology');
  }

  const why = flashcards.find((card) => card.kind === 'why_in_news');
  const legacyHash = crypto.createHash('md5').update(why.front.toLowerCase()).digest('hex').slice(0, 16);
  assert.equal(why.id, `fc_${legacyHash}`);
  assert.equal(flashcardId(why.front), why.id);
});

test('shared persistence contract always uploads historical keyFacts', async () => {
  const calls = [];
  const derived = {
    flashcards: [{ id: 'fc-1' }],
    schemes: [{ id: 'gs-1' }],
    keyFacts: [{ id: 'kf-1' }],
  };
  const result = await persistDerivedLibraries(derived, {
    dryRun: true,
    uploadFlashcardsFn: async (docs) => { calls.push(['flashcards', docs]); return { uploaded: 1, skipped: 0, errors: 0 }; },
    uploadSchemesFn: async (docs) => { calls.push(['schemes', docs]); return { uploaded: 1, skipped: 0, errors: 0 }; },
    uploadKeyFactsFn: async (docs) => { calls.push(['keyFacts', docs]); return { uploaded: 1, skipped: 0, errors: 0 }; },
  });
  assert.deepEqual(calls.map(([name]) => name), ['flashcards', 'schemes', 'keyFacts']);
  assert.equal(calls[2][1][0].id, 'kf-1');
  assert.equal(result.keyFacts.uploaded, 1);
});

test('backfill passes generated keyFacts through the canonical persistence seam', async () => {
  const generated = {
    vocabulary: [],
    flashcards: [{ id: 'fc' }],
    schemes: [{ id: 'gs' }],
    keyFacts: [{ id: 'kf', facts: ['one', 'two'] }],
  };
  let persisted = null;
  await runBackfill({
    options: { from: '', to: '', maxDates: 1, vocabOnly: false, dryRun: true },
    firestore: {
      collection: () => ({
        get: async () => ({ docs: [{ id: article.id, data: () => article }] }),
      }),
    },
    generate: () => generated,
    persist: async (value) => {
      persisted = value;
      return {
        flashcards: { errors: 0 }, schemes: { errors: 0 }, keyFacts: { errors: 0 },
      };
    },
    loadExistingVocabulary: async () => new Map(),
    runVocabulary: async () => ({ completedDates: [], totals: {}, hasMore: false }),
    log: () => {},
  });
  assert.equal(persisted.keyFacts[0].id, 'kf');
});

const firstSchemeArticle = {
  id: 'scheme-source-a',
  title: 'PM Shilp Scheme details for artisan support',
  summary: 'PM Shilp Scheme supports traditional artisans with training and credit.',
  newspaper: 'Policy Daily',
  sourceUrl: 'https://news.example.test/a',
  publishedDate: '2025-08-10',
  categoryTags: ['Economy'],
  governmentScheme: 'PM Shilp Scheme',
  content: [
    'PM Shilp Scheme was launched in 2021 by the Ministry of Skill Development and Entrepreneurship.',
    '## Objective',
    'The objective of PM Shilp Scheme is to improve artisan skills and access to formal markets.',
    '## Beneficiaries',
    'Traditional artisans and craftspeople registered under PM Shilp Scheme.',
    '## Eligibility',
    'Applicants to PM Shilp Scheme must be practising artisans aged at least 18 years.',
    '## Funding Pattern',
    'PM Shilp Scheme is fully funded by the Union Government with an outlay of 500 crore rupees.',
    '## Implementation',
    'PM Shilp Scheme is implemented by the Ministry of Skill Development and Entrepreneurship.',
    'Official details for PM Shilp Scheme are at https://pmshilp.gov.in/guidelines.',
  ].join('\n'),
};

const secondSchemeArticle = {
  id: 'scheme-source-b',
  title: 'PM Shilp Scheme expands training benefits',
  summary: 'The scheme adds toolkits and training support for craftspeople.',
  newspaper: 'Another Daily',
  sourceUrl: 'https://news.example.test/b',
  publishedDate: '2026-02-03',
  categoryTags: ['Economy'],
  governmentScheme: 'PM Shilp Scheme',
  content: [
    '## Benefits',
    'PM Shilp Scheme provides a toolkit incentive of 15000 rupees to eligible artisans.',
    'PM Shilp Scheme provides certified training and concessional credit to enrolled craftspeople.',
    '## Beneficiaries',
    'Women artisans and craftspeople in rural districts are beneficiaries of PM Shilp Scheme.',
  ].join('\n'),
};

test('scheme extraction uses explicit fields and aggregates all matching sources', () => {
  const [scheme] = generateSchemes([firstSchemeArticle, secondSchemeArticle]);
  assert.ok(scheme);
  assert.equal(scheme.schemaVersion, 2);
  assert.match(scheme.objective, /objective of PM Shilp Scheme/i);
  assert.ok(scheme.beneficiaries.some((value) => /Traditional artisans/i.test(value)));
  assert.ok(scheme.beneficiaries.some((value) => /Women artisans/i.test(value)));
  assert.ok(scheme.eligibility.some((value) => /aged at least 18/i.test(value)));
  assert.ok(scheme.benefits.some((value) => /toolkit incentive/i.test(value)));
  assert.match(scheme.funding, /outlay of 500 crore/i);
  assert.match(scheme.implementation, /implemented by the Ministry/i);
  assert.equal(scheme.launchYear, '2021');
  assert.equal(scheme.coverageYear, '2026');
  assert.equal(scheme.year, '2026');
  assert.equal(scheme.officialUrl, 'https://pmshilp.gov.in/guidelines');
  assert.equal(scheme.sources.length, 2);
  assert.ok(scheme.sources.every((source) => source.official === false));
});

test('scheme aggregation is order-independent and does not infer launch year or official URL', () => {
  const forward = generateSchemes([firstSchemeArticle, secondSchemeArticle]);
  const reverse = generateSchemes([secondSchemeArticle, firstSchemeArticle]);
  assert.deepEqual(forward, reverse);

  const [thin] = generateSchemes([{
    ...firstSchemeArticle,
    id: 'thin-source',
    sourceUrl: 'https://example.com/not-official',
    content: 'PM Shilp Scheme was discussed in the 2020 policy review without launch details.',
    publishedDate: '2026-03-04',
  }]);
  assert.equal(thin.launchYear, '');
  assert.equal(thin.officialUrl, '');
});

test('scheme list/source merge is additive, deduplicated, and idempotent', () => {
  const existing = {
    schemaVersion: 1,
    objective: 'A curated objective that must remain.',
    beneficiaries: ['Traditional artisans'],
    sources: [{ articleId: 'a', title: 'A', url: '', publisher: '', publishedDate: '', official: false }],
  };
  const incoming = {
    schemaVersion: 2,
    objective: 'Generated objective that must not replace curation.',
    beneficiaries: ['Traditional artisans', 'Women artisans'],
    sources: [
      { articleId: 'a', title: 'A duplicate', url: '', publisher: '', publishedDate: '', official: false },
      { articleId: 'b', title: 'B', url: '', publisher: '', publishedDate: '', official: false },
    ],
  };
  const patch = schemeEnrichmentPatch(existing, incoming);
  assert.ok(!('objective' in patch));
  assert.equal(patch.schemaVersion, 2);
  assert.deepEqual(patch.beneficiaries, ['Traditional artisans', 'Women artisans']);
  assert.equal(patch.sources.length, 2);

  const filled = { ...existing, ...patch };
  assert.deepEqual(schemeEnrichmentPatch(filled, incoming), {});
});

test('existing lexical document ids are retained during key-term enrichment', async () => {
  const existingByWord = new Map([[
    'constitutional morality',
    {
      id: 'legacy-vocabulary-id',
      word: 'Constitutional morality',
      meaning: '',
      schemaVersion: 1,
    },
  ]]);
  let uploaded = null;
  await processVocabularyDate({
    date: article.publishedDate,
    articles: [article],
    existingByWord,
    extract: async (_articles, { excludeWords }) => {
      assert.ok(excludeWords.has('constitutional morality'));
      return { docs: [], stats: { errorCount: 0 } };
    },
    upload: async (docs) => {
      uploaded = docs;
      return { uploaded: 1, skipped: 0, errors: 0 };
    },
    log: () => {},
  });
  assert.equal(uploaded.length, 1);
  assert.equal(uploaded[0].id, 'legacy-vocabulary-id');
  assert.match(uploaded[0].meaning, /principle requiring public institutions/i);
});


test('Wiktionary definitions are converted from structured HTML to plain text', async () => {
  let requestedUrl = '';
  const result = await lookupDictionaryWord('perspicacious', {
    fetchImpl: async (url) => {
      requestedUrl = url;
      return {
        ok: true,
        status: 200,
        json: async () => ({
          en: [{
            partOfSpeech: 'Adjective',
            definitions: [{
              definition: 'Of acute <a href="/wiki/discernment">discernment</a>; having keen &amp; perceptive insight.',
            }],
          }],
        }),
      };
    },
    retries: 0,
  });

  assert.match(requestedUrl, /en\.wiktionary\.org\/api\/rest_v1\/page\/definition/);
  assert.equal(result.status, 'success');
  assert.equal(result.entry.partOfSpeech, 'Adjective');
  assert.equal(
    result.entry.meaning,
    'Of acute discernment; having keen & perceptive insight.'
  );
  assert.ok(!/[<>]/.test(result.entry.meaning));
});


test('indexed vocabulary writer creates and enriches with zero Firestore reads', async () => {
  const existing = new Map([
    ['resilience', {
      id: 'legacy-resilience',
      word: 'Resilience',
      normalizedWord: 'resilience',
      meaning: 'The ability to recover.',
      sourceUrl: '',
      schemaVersion: 1,
    }],
  ]);
  const stats = await upsertVocabularyFromIndex([
    {
      id: 'ignored-new-id',
      word: 'Resilience',
      normalizedWord: 'resilience',
      meaning: 'Generated meaning must not replace curation.',
      sourceUrl: 'https://example.com/resilience',
      schemaVersion: 2,
    },
    {
      id: 'v-perspicacious',
      word: 'Perspicacious',
      normalizedWord: 'perspicacious',
      meaning: 'Having keen insight.',
      schemaVersion: 2,
    },
  ], true, existing);

  assert.equal(stats.created, 1);
  assert.equal(stats.enriched, 1);
  assert.equal(stats.errors, 0);
  assert.equal(existing.get('resilience').id, 'legacy-resilience');
  assert.equal(existing.get('resilience').meaning, 'The ability to recover.');
  assert.equal(existing.get('resilience').sourceUrl, 'https://example.com/resilience');
  assert.equal(existing.get('perspicacious').id, 'v-perspicacious');
});


test('vocabulary continuation checkpoint records the exact resume boundary', () => {
  assert.deepEqual(
    nextCheckpoint({
      hasMore: true,
      nextFrom: '2026-09-01',
      completedDates: ['2026-08-18'],
      totals: { docs: 12, uploaded: 11, skipped: 1 },
    }, '2026-09-15'),
    {
      nextFrom: '2026-09-01',
      to: '2026-09-15',
      completed: false,
      completedDates: 1,
      vocabularyDocs: 12,
      uploaded: 11,
      skipped: 1,
    },
  );
});

test('completed vocabulary continuation is a no-op on later schedules', async () => {
  let backfillCalls = 0;
  let writes = 0;
  const result = await runCheckpointedVocabulary({
    firestore: {
      collection: () => ({
        doc: () => ({
          get: async () => ({
            exists: true,
            data: () => ({ completed: true, to: '2026-09-15' }),
          }),
          set: async () => { writes++; },
        }),
      }),
    },
    options: { from: '', to: '2026-09-15', maxDates: 30, dryRun: false },
    run: async () => { backfillCalls++; },
    log: () => {},
  });
  assert.equal(result.skippedAsComplete, true);
  assert.equal(backfillCalls, 0);
  assert.equal(writes, 0);
});
