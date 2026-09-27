#!/usr/bin/env node
/** UPSC daily content scraper and canonical study-library updater. */

import { scrapeDrishti, scrapeInsights } from './scrapers.js';
import { deduplicateAndMerge } from './deduplicator.js';
import { enrichImages } from './image-finder.js';
import {
  initFirebase,
  loadVocabularyIndex,
  persistDerivedLibraries,
  rebuildRoundups,
  uploadArticles,
  uploadDailyQuiz,
  uploadPyqs,
  upsertVocabularyFromIndex,
} from './uploader.js';
import { generateAll, generateDailyQuiz } from './generators.js';
import { processVocabularyDate } from './vocabulary-pipeline.js';

function getDateStr(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function parseArgs() {
  const args = process.argv.slice(2);
  const options = { dates: [], dryRun: false };
  for (let index = 0; index < args.length; index++) {
    switch (args[index]) {
      case '--dry-run': options.dryRun = true; break;
      case '--date':
        if (args[index + 1]) options.dates.push(args[++index]);
        break;
      case '--days': {
        const days = parseInt(args[++index], 10) || 1;
        const now = new Date();
        for (let offset = 0; offset < days; offset++) {
          const date = new Date(now);
          date.setDate(now.getDate() - offset);
          options.dates.push(getDateStr(date));
        }
        break;
      }
      case '--today':
      default:
        break;
    }
  }
  if (options.dates.length === 0) {
    const istNow = new Date(Date.now() + (5.5 * 60 * 60 * 1000));
    options.dates.push(getDateStr(istNow));
  }
  options.dates = [...new Set(options.dates)];
  return options;
}

async function scrapeForDate(dateStr, dryRun, vocabularyState) {
  console.log(`\n${'═'.repeat(60)}`);
  console.log(`  Scraping content for: ${dateStr}`);
  console.log(`${'═'.repeat(60)}\n`);

  const [drishtiArticles, insightsArticles] = await Promise.all([
    scrapeDrishti(dateStr).catch((error) => {
      console.error(`[Drishti] Error: ${error.message}`);
      return [];
    }),
    scrapeInsights(dateStr).catch((error) => {
      console.error(`[Insights] Error: ${error.message}`);
      return [];
    }),
  ]);

  if (drishtiArticles.length === 0 && insightsArticles.length === 0) {
    console.log(`[Info] No new source articles found for ${dateStr} (may be Sunday/holiday).`);
    return rebuildRoundups(dateStr, dryRun);
  }

  console.log('\n[Dedup] Merging overlapping content...');
  const mergedArticles = deduplicateAndMerge(drishtiArticles, insightsArticles);
  for (let index = 0; index < Math.min(3, mergedArticles.length); index++) {
    mergedArticles[index].isTopNews = true;
  }
  await enrichImages(mergedArticles);

  const pyqs = [];
  const seenPyq = new Set();
  for (const article of mergedArticles) {
    for (const question of article._pyqs || []) {
      if (seenPyq.has(question.id)) continue;
      seenPyq.add(question.id);
      pyqs.push(question);
    }
    delete article._pyqs;
  }

  console.log(`\n[Upload] Uploading ${mergedArticles.length} articles to Firestore...`);
  const articleStats = await uploadArticles(mergedArticles, dryRun);
  if (pyqs.length) console.log(`\n[Upload] ${pyqs.length} previous-year question(s) harvested...`);
  const pyqStats = await uploadPyqs(pyqs, dryRun);

  console.log('\n[Generate] Deriving canonical vocabulary, flashcards, schemes, and facts...');
  const derived = generateAll(mergedArticles);
  const vocabularyResult = await processVocabularyDate({
    date: dateStr,
    articles: mergedArticles,
    existingByWord: vocabularyState,
    generatedVocabulary: derived.vocabulary,
    limit: 12,
    dryRun,
    upload: (docs, isDryRun) =>
      upsertVocabularyFromIndex(docs, isDryRun, vocabularyState),
    // Daily publication remains best-effort, but exhausted transient lookups
    // are counted in the aggregate so automation is visibly red and rerunnable.
    failOnLookupErrors: false,
  });
  const vocabStats = {
    ...vocabularyResult.uploadStats,
    errors: Number(vocabularyResult.uploadStats.errors || 0) +
      Number(vocabularyResult.extractionStats.errorCount || 0),
  };

  const libraryStats = await persistDerivedLibraries(derived, { dryRun });
  const flashStats = libraryStats.flashcards;
  const schemeStats = libraryStats.schemes;
  const factStats = libraryStats.keyFacts;

  console.log(
    `[Generate] vocabulary=${vocabularyResult.docs.length} ` +
    `flashcards=${derived.flashcards.length} schemes=${derived.schemes.length} ` +
    `keyFacts=${derived.keyFacts.length}`
  );

  const dailyQuiz = generateDailyQuiz(mergedArticles, dateStr, { limit: 10 });
  console.log(`[Generate] dailyQuiz=${dailyQuiz.length}`);
  const dailyQuizStats = await uploadDailyQuiz(dateStr, dailyQuiz, dryRun);
  const roundupStats = await rebuildRoundups(dateStr, dryRun);

  console.log(
    `\n[Done] ${dateStr}: ` +
    `articles(+${articleStats.uploaded}/~${articleStats.skipped}${articleStats.upgraded ? `/^${articleStats.upgraded}` : ''}) ` +
    `pyqs(+${pyqStats.uploaded}/~${pyqStats.skipped}) ` +
    `vocab(+${vocabStats.uploaded}/~${vocabStats.skipped}) ` +
    `flashcards(+${flashStats.uploaded}/~${flashStats.skipped}) ` +
    `schemes(+${schemeStats.uploaded}/~${schemeStats.skipped}) ` +
    `facts(+${factStats.uploaded}/~${factStats.skipped}) ` +
    `dailyQuiz(+${dailyQuizStats.uploaded}) roundups(+${roundupStats.uploaded})`
  );

  return {
    uploaded: articleStats.uploaded + pyqStats.uploaded + vocabStats.uploaded +
      flashStats.uploaded + schemeStats.uploaded + factStats.uploaded +
      dailyQuizStats.uploaded + roundupStats.uploaded,
    skipped: articleStats.skipped + pyqStats.skipped + vocabStats.skipped +
      flashStats.skipped + schemeStats.skipped + factStats.skipped +
      dailyQuizStats.skipped + roundupStats.skipped,
    errors: articleStats.errors + pyqStats.errors + vocabStats.errors +
      flashStats.errors + schemeStats.errors + factStats.errors +
      dailyQuizStats.errors + roundupStats.errors,
  };
}

async function main() {
  const options = parseArgs();
  console.log('╔══════════════════════════════════════════════════════════╗');
  console.log('║        UPSC Daily Content Scraper v2.0                  ║');
  console.log('║  Sources: Drishti IAS + Insights on India               ║');
  console.log('╚══════════════════════════════════════════════════════════╝');
  console.log(`Mode: ${options.dryRun ? 'DRY RUN (no upload)' : 'LIVE'}`);
  console.log(`Dates: ${options.dates.join(', ')}`);

  let vocabularyState = new Map();
  if (!options.dryRun) {
    initFirebase();
    vocabularyState = await loadVocabularyIndex();
  }

  const totalStats = { uploaded: 0, skipped: 0, errors: 0 };
  for (const dateStr of options.dates) {
    const stats = await scrapeForDate(dateStr, options.dryRun, vocabularyState);
    totalStats.uploaded += stats.uploaded;
    totalStats.skipped += stats.skipped;
    totalStats.errors += stats.errors;
  }

  console.log(`\n${'═'.repeat(60)}`);
  console.log(`TOTAL: Uploaded=${totalStats.uploaded} Skipped=${totalStats.skipped} Errors=${totalStats.errors}`);
  console.log('═'.repeat(60));
  if (totalStats.errors > 0) process.exitCode = 1;
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exitCode = 1;
});
