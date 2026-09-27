#!/usr/bin/env node
/**
 * Resumable canonical study-library backfill.
 *
 * Vocabulary is processed one publication date at a time and each completed
 * date is written immediately. Use --from with the resume date printed by the
 * previous chunk. Existing lexical words are loaded before dictionary calls.
 *
 * Usage:
 *   node backfill.js --max-dates 30
 *   node backfill.js --from 2026-09-16 --to 2026-10-15 --max-dates 15
 *   node backfill.js --from 2026-09-16 --vocab-only --dry-run
 */

import { pathToFileURL } from 'url';

import { generateAll } from './generators.js';
import {
  initFirebase,
  loadVocabularyIndex,
  persistDerivedLibraries,
  upsertVocabularyFromIndex,
} from './uploader.js';
import {
  parseVocabularyBackfillArgs,
  runHistoricalVocabulary,
} from './vocabulary-pipeline.js';

function usage() {
  return `
Usage: node backfill.js [options]

Options:
  --from YYYY-MM-DD   Inclusive first publication date
  --to YYYY-MM-DD     Inclusive last publication date
  --max-dates N       Maximum dates in this run (default 30)
  --vocab-only        Skip flashcard, scheme and Must Know derivation
  --dry-run           Read and derive, but do not write
  --help              Show this help
`;
}

function countErrors(stats) {
  if (!stats || typeof stats !== 'object') return 0;
  return Object.values(stats).reduce((total, value) => {
    if (value && typeof value === 'object' && 'errors' in value) {
      return total + Number(value.errors || 0);
    }
    return total;
  }, 0);
}

export async function runBackfill({
  options,
  firestore,
  log = console.log,
  generate = generateAll,
  persist = persistDerivedLibraries,
  loadExistingVocabulary = loadVocabularyIndex,
  runVocabulary = runHistoricalVocabulary,
  uploadVocabularyFn = upsertVocabularyFromIndex,
} = {}) {
  const snapshot = await firestore.collection('articles').get();
  const articles = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
  log(`Loaded ${articles.length} articles from Firestore.`);

  let libraryStats = null;
  if (!options.vocabOnly) {
    const derived = generate(articles);
    log(
      `Derived canonical libraries: flashcards=${derived.flashcards.length} ` +
      `schemes=${derived.schemes.length} keyFacts=${derived.keyFacts.length}`
    );
    libraryStats = await persist(derived, { dryRun: options.dryRun });
    const libraryErrors = countErrors(libraryStats);
    if (libraryErrors > 0) {
      throw new Error(`Canonical library backfill had ${libraryErrors} upload error(s)`);
    }
  }

  const existingByWord = await loadExistingVocabulary({ dryRun: options.dryRun });
  const vocabulary = await runVocabulary({
    articles,
    from: options.from,
    to: options.to,
    maxDates: options.maxDates,
    dryRun: options.dryRun,
    existingByWord,
    upload: (docs, dryRun) =>
      uploadVocabularyFn(docs, dryRun, existingByWord),
    log,
  });

  return { articles: articles.length, libraryStats, vocabulary };
}

async function main() {
  let options;
  try {
    options = parseVocabularyBackfillArgs();
  } catch (error) {
    console.error(`Argument error: ${error.message}`);
    console.error(usage());
    process.exitCode = 2;
    return;
  }
  if (options.help) {
    console.log(usage());
    return;
  }

  console.log('='.repeat(68));
  console.log('  Canonical study-library backfill');
  console.log(`  Mode: ${options.dryRun ? 'DRY RUN' : 'LIVE'}`);
  console.log(
    `  Vocabulary range: ${options.from || '*'}..${options.to || '*'} ` +
    `(max ${options.maxDates} dates)`
  );
  console.log(`  Libraries: ${options.vocabOnly ? 'vocabulary only' : 'all canonical libraries'}`);
  console.log('='.repeat(68));

  const firestore = initFirebase();
  const result = await runBackfill({ options, firestore });
  const totals = result.vocabulary.totals;
  console.log(
    `\nDone: dates=${result.vocabulary.completedDates.length} vocabularyDocs=${totals.docs} ` +
    `uploaded=${totals.uploaded} skipped=${totals.skipped}`
  );
  if (result.vocabulary.hasMore) {
    console.log(`Resume the next chunk with --from ${result.vocabulary.nextFrom}`);
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) {
  main().catch((error) => {
    console.error(`Fatal error${error.date ? ` on ${error.date}` : ''}: ${error.message}`);
    if (error.completedDates?.length) {
      console.error(`Completed dates: ${error.completedDates.join(', ')}`);
    }
    if (error.nextFrom) console.error(`Resume with --from ${error.nextFrom}`);
    process.exitCode = 1;
  });
}
