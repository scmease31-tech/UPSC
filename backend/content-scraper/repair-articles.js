#!/usr/bin/env node
/** Repair stored articles, then re-derive every canonical dependent library. */

import { getFirestore, FieldValue } from 'firebase-admin/firestore';

import {
  initFirebase,
  loadVocabularyIndex,
  persistDerivedLibraries,
  uploadPyqs,
  upsertVocabularyFromIndex,
} from './uploader.js';
import { generateAll } from './generators.js';
import { runHistoricalVocabulary, toIsoDate } from './vocabulary-pipeline.js';
import { parseDrishtiArticle, parsePyqBlock } from './scrapers.js';
import { restructure, isStructured } from './restructure.js';
import { findTopicImage } from './image-finder.js';

function parseArgs() {
  const args = process.argv.slice(2);
  const options = {
    dryRun: false,
    limit: 0,
    refetch: true,
    images: true,
    force: false,
    vocabPerBatch: 20,
    vocabFrom: '',
    vocabTo: '',
    vocabMaxDates: 30,
  };
  for (let index = 0; index < args.length; index++) {
    switch (args[index]) {
      case '--dry-run': options.dryRun = true; break;
      case '--force': options.force = true; break;
      case '--limit': options.limit = parseInt(args[++index], 10) || 0; break;
      case '--no-refetch': options.refetch = false; break;
      case '--no-images': options.images = false; break;
      case '--from': options.vocabFrom = args[++index] || ''; break;
      case '--to': options.vocabTo = args[++index] || ''; break;
      case '--max-dates': options.vocabMaxDates = parseInt(args[++index], 10) || 30; break;
    }
  }
  if (options.vocabFrom && !toIsoDate(options.vocabFrom)) throw new Error('--from must be YYYY-MM-DD');
  if (options.vocabTo && !toIsoDate(options.vocabTo)) throw new Error('--to must be YYYY-MM-DD');
  if (options.vocabFrom && options.vocabTo && options.vocabFrom > options.vocabTo) {
    throw new Error('--from must be on or before --to');
  }
  return options;
}

function refetchableUrl(article) {
  const url = (article.sourceUrl || '').split(' | ')[0].trim();
  return /drishtiias\.com\/daily-updates\/daily-news-(analysis|editorials)\/.+/.test(url) ? url : null;
}

async function mapLimit(items, limit, worker) {
  const results = new Array(items.length);
  let cursor = 0;
  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, async () => {
      while (cursor < items.length) {
        const index = cursor++;
        try {
          results[index] = await worker(items[index], index);
        } catch (error) {
          results[index] = { error: error.message };
        }
      }
    }),
  );
  return results;
}

async function main() {
  const options = parseArgs();
  console.log('='.repeat(66));
  console.log('  Article repair + canonical content re-derivation');
  console.log(`  Mode: ${options.dryRun ? 'DRY RUN' : 'LIVE'}`);
  console.log('='.repeat(66));

  initFirebase();
  const db = getFirestore();
  const snapshot = await db.collection('articles').get();
  const articles = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
  console.log(`\nLoaded ${articles.length} article(s).`);

  let needsWork = options.force
    ? articles
    : articles.filter((article) =>
      !isStructured(article.content) || !article.imageUrl || /&(#\d+|[a-z]+);/i.test(article.content || '')
    );
  console.log(`${needsWork.length} need structuring, artwork or cleanup${options.force ? ' (forced: all)' : ''}.`);
  if (options.limit) needsWork = needsWork.slice(0, options.limit);

  const repairStats = { refetched: 0, restructured: 0, imaged: 0, unchanged: 0 };
  const updates = await mapLimit(needsWork, 4, async (article) => {
    const patch = {};
    const url = options.refetch ? refetchableUrl(article) : null;
    if (url) {
      try {
        const fresh = await parseDrishtiArticle(url, article.publishedDate || '', article.title || '');
        if (fresh && isStructured(fresh.content) && fresh.content.length > 200) {
          patch.content = fresh.content;
          patch.summary = fresh.summary || article.summary;
          patch.keyPoints = fresh.keyPoints?.length ? fresh.keyPoints : (article.keyPoints || []);
          patch.shortNotes = fresh.shortNotes?.length ? fresh.shortNotes : (article.shortNotes || []);
          if (fresh.imageUrl) patch.imageUrl = fresh.imageUrl;
          if (fresh.upscPaper) patch.upscPaper = fresh.upscPaper;
          if (fresh.syllabusMapping) patch.syllabusMapping = fresh.syllabusMapping;
          if (fresh.categoryTags?.length) patch.categoryTags = fresh.categoryTags;
          if (fresh.sourcePaper) patch.sourcePaper = fresh.sourcePaper;
          if (fresh.relatedTopics?.length) patch.relatedTopics = fresh.relatedTopics;
          article._pyqs = fresh._pyqs || [];
          repairStats.refetched++;
        }
      } catch {
        // Fall through to the offline route.
      }
    }

    if (!patch.content) {
      const original = article.content || '';
      const rebuilt = restructure(original, { title: article.title });
      const gainedParagraphs = rebuilt.split('\n\n').length > original.split('\n\n').length;
      const changed = rebuilt !== original;
      if (rebuilt.length > 120 && changed &&
          (isStructured(rebuilt) || gainedParagraphs || rebuilt.length < original.length)) {
        patch.content = rebuilt;
        repairStats.restructured++;
      }
    }

    if (options.images && !article.imageUrl && !patch.imageUrl) {
      const hit = await findTopicImage(
        article.title || '',
        article.categoryTags || [],
        article.relatedTopics || [],
      );
      if (hit) {
        patch.imageUrl = hit.url;
        patch.imageCredit = hit.credit;
        patch.imageCreditUrl = hit.creditUrl;
        repairStats.imaged++;
      }
    }

    if (Object.keys(patch).length === 0) {
      repairStats.unchanged++;
      return null;
    }
    Object.assign(article, patch);
    return { id: article.id, patch };
  });

  const writes = updates.filter(Boolean);
  console.log(
    `\nRepairs: re-fetched ${repairStats.refetched}, restructured ${repairStats.restructured}, ` +
    `artwork added ${repairStats.imaged}, unchanged ${repairStats.unchanged}`
  );
  if (!options.dryRun && writes.length) {
    for (let offset = 0; offset < writes.length; offset += 400) {
      const batch = db.batch();
      for (const write of writes.slice(offset, offset + 400)) {
        batch.update(db.collection('articles').doc(write.id), {
          ...write.patch,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    console.log(`Wrote ${writes.length} article update(s).`);
  }

  console.log('\nDeriving study content from all articles…');
  const pyqs = [];
  const seenPyq = new Set();
  for (const article of articles) {
    const found = [
      ...(article._pyqs || []),
      ...parsePyqBlock(article.content || '', {
        subject: (article.categoryTags || []).find(Boolean) || 'General',
        gsPaper: article.upscPaper || '',
        sourceUrl: article.sourceUrl || '',
        topic: article.title || '',
      }),
    ];
    for (const question of found) {
      if (seenPyq.has(question.id)) continue;
      seenPyq.add(question.id);
      pyqs.push(question);
    }
    delete article._pyqs;
  }

  const derived = generateAll(articles);
  console.log(
    `Derived: pyqs=${pyqs.length} flashcards=${derived.flashcards.length} ` +
    `schemes=${derived.schemes.length} keyFacts=${derived.keyFacts.length}`
  );

  const pyqStats = await uploadPyqs(pyqs, options.dryRun);
  const existingByWord = await loadVocabularyIndex({ dryRun: options.dryRun });
  const vocabulary = await runHistoricalVocabulary({
    articles,
    from: options.vocabFrom,
    to: options.vocabTo,
    maxDates: options.vocabMaxDates,
    limit: options.vocabPerBatch,
    dryRun: options.dryRun,
    existingByWord,
    upload: (docs, isDryRun) =>
      upsertVocabularyFromIndex(docs, isDryRun, existingByWord),
  });
  const libraries = await persistDerivedLibraries(derived, { dryRun: options.dryRun });

  console.log(`\n${'='.repeat(66)}`);
  console.log(
    `Done: pyqs(+${pyqStats.uploaded}/~${pyqStats.skipped}) ` +
    `vocabulary(+${vocabulary.totals.uploaded}/~${vocabulary.totals.skipped}) ` +
    `flashcards(+${libraries.flashcards.uploaded}/~${libraries.flashcards.skipped}) ` +
    `schemes(+${libraries.schemes.uploaded}/~${libraries.schemes.skipped}) ` +
    `keyFacts(+${libraries.keyFacts.uploaded}/~${libraries.keyFacts.skipped})`
  );
  if (vocabulary.hasMore) console.log(`Resume vocabulary with --from ${vocabulary.nextFrom}`);
  console.log('='.repeat(66));
}

main()
  .catch((error) => {
    console.error(`Fatal error${error.date ? ` on ${error.date}` : ''}: ${error.message}`);
    if (error.nextFrom) console.error(`Resume vocabulary with --from ${error.nextFrom}`);
    process.exitCode = 1;
  });
