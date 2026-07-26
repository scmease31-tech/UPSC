#!/usr/bin/env node
/**
 * Bring every stored article up to the current standard, and re-derive all the
 * study content that hangs off them.
 *
 * The pipeline improved in stages, so Firestore holds articles at three
 * different quality levels: flat text from the earliest runs, semi-structured
 * text from the newspaper ingests, and fully structured bodies from the current
 * per-article Drishti scraper. This walks the whole collection and levels them
 * up, then rebuilds vocabulary / PYQs / schemes / flashcards from the result.
 *
 * Per article, best available route:
 *   1. Has its own source page  → re-fetch and re-parse (structure, artwork,
 *      syllabus tags and the article's PYQ block, all authoritative)
 *   2. Otherwise                → impose structure on the stored text, and look
 *      for an openly-licensed image if it has none
 *
 * Safe to re-run: articles already at the current standard are skipped, and
 * every derived collection de-duplicates on write.
 *
 * Usage:
 *   node repair-articles.js                 # everything
 *   node repair-articles.js --dry-run       # report only
 *   node repair-articles.js --limit 20      # first 20 needing work
 *   node repair-articles.js --no-refetch    # skip network re-fetch
 *   node repair-articles.js --no-images     # skip image lookup
 */

import { getFirestore, FieldValue } from 'firebase-admin/firestore';

import {
  initFirebase,
  uploadVocabulary,
  uploadFlashcards,
  uploadSchemes,
  uploadPyqs,
} from './uploader.js';
import { generateFlashcards, generateSchemes } from './generators.js';
import { extractDailyVocabulary } from './vocab-extract.js';
import { parseDrishtiArticle, parsePyqBlock } from './scrapers.js';
import { restructure, isStructured } from './restructure.js';
import { findTopicImage } from './image-finder.js';

function parseArgs() {
  const a = process.argv.slice(2);
  const o = { dryRun: false, limit: 0, refetch: true, images: true, force: false, vocabPerBatch: 12 };
  for (let i = 0; i < a.length; i++) {
    switch (a[i]) {
      case '--dry-run': o.dryRun = true; break;
      // Re-process articles that already look current. Needed when the
      // structuring rules themselves improve, since those articles would
      // otherwise be skipped forever.
      case '--force': o.force = true; break;
      case '--limit': o.limit = parseInt(a[++i], 10) || 0; break;
      case '--no-refetch': o.refetch = false; break;
      case '--no-images': o.images = false; break;
    }
  }
  return o;
}

/** Per-article page we can re-read, as opposed to a daily index page. */
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
        const i = cursor++;
        try { results[i] = await worker(items[i], i); } catch (e) { results[i] = { error: e.message }; }
      }
    }),
  );
  return results;
}

async function main() {
  const opts = parseArgs();

  console.log('='.repeat(66));
  console.log('  Article repair + full content re-derivation');
  console.log(`  Mode: ${opts.dryRun ? 'DRY RUN' : 'LIVE'}`);
  console.log('='.repeat(66));

  initFirebase();
  const db = getFirestore();

  const snap = await db.collection('articles').get();
  const articles = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  console.log(`\nLoaded ${articles.length} article(s).`);

  let needsWork = opts.force
    ? articles
    : articles.filter((a) => !isStructured(a.content) || !a.imageUrl || /&(#\d+|[a-z]+);/i.test(a.content || ''));
  console.log(`${needsWork.length} need structuring, artwork or cleanup${opts.force ? ' (forced: all)' : ''}.`);
  if (opts.limit) needsWork = needsWork.slice(0, opts.limit);

  const stats = { refetched: 0, restructured: 0, imaged: 0, unchanged: 0, failed: 0 };

  // ── 1. Level up each article ──
  const updates = await mapLimit(needsWork, 4, async (a) => {
    const patch = {};

    const url = opts.refetch ? refetchableUrl(a) : null;
    if (url) {
      try {
        const fresh = await parseDrishtiArticle(url, a.publishedDate || '', a.title || '');
        if (fresh && isStructured(fresh.content) && fresh.content.length > 200) {
          patch.content = fresh.content;
          patch.summary = fresh.summary || a.summary;
          patch.keyPoints = fresh.keyPoints?.length ? fresh.keyPoints : (a.keyPoints || []);
          patch.shortNotes = fresh.shortNotes?.length ? fresh.shortNotes : (a.shortNotes || []);
          if (fresh.imageUrl) patch.imageUrl = fresh.imageUrl;
          if (fresh.upscPaper) patch.upscPaper = fresh.upscPaper;
          if (fresh.syllabusMapping) patch.syllabusMapping = fresh.syllabusMapping;
          if (fresh.categoryTags?.length) patch.categoryTags = fresh.categoryTags;
          if (fresh.sourcePaper) patch.sourcePaper = fresh.sourcePaper;
          if (fresh.relatedTopics?.length) patch.relatedTopics = fresh.relatedTopics;
          a._pyqs = fresh._pyqs || [];
          stats.refetched++;
        }
      } catch { /* fall through to the offline route */ }
    }

    // Offline route: structure whatever text we already hold. Runs even on
    // already-structured bodies, because it is idempotent and also decodes
    // stray HTML entities and prunes empty headings.
    if (!patch.content) {
      const original = a.content || '';
      const rebuilt = restructure(original, { title: a.title });
      // Accept it when it found real sections, or — for newspaper prose, which
      // genuinely has no sections — when it at least broke a single run of text
      // into paragraphs. Also accept any change that shortens the text, which
      // means junk or a duplicated headline was removed.
      const gainedParagraphs = rebuilt.split('\n\n').length > original.split('\n\n').length;
      const changed = rebuilt !== original;
      if (rebuilt.length > 120 && changed && (isStructured(rebuilt) || gainedParagraphs || rebuilt.length < original.length)) {
        patch.content = rebuilt;
        stats.restructured++;
      }
    }

    // Artwork for anything still without it.
    if (opts.images && !a.imageUrl && !patch.imageUrl) {
      const hit = await findTopicImage(a.title || '', a.categoryTags || [], a.relatedTopics || []);
      if (hit) {
        patch.imageUrl = hit.url;
        patch.imageCredit = hit.credit;
        patch.imageCreditUrl = hit.creditUrl;
        stats.imaged++;
      }
    }

    if (Object.keys(patch).length === 0) { stats.unchanged++; return null; }

    // Keep the in-memory copy current so derivation below sees the new text.
    Object.assign(a, patch);
    return { id: a.id, patch };
  });

  const writes = updates.filter(Boolean);
  console.log(
    `\nRepairs: re-fetched ${stats.refetched}, restructured ${stats.restructured}, `
    + `artwork added ${stats.imaged}, unchanged ${stats.unchanged}`,
  );

  if (!opts.dryRun && writes.length) {
    for (let i = 0; i < writes.length; i += 400) {
      const batch = db.batch();
      for (const w of writes.slice(i, i + 400)) {
        batch.update(db.collection('articles').doc(w.id), {
          ...w.patch,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    console.log(`Wrote ${writes.length} article update(s).`);
  }

  // ── 2. Re-derive every dependent collection from the FULL history ──
  console.log('\nDeriving study content from all articles…');

  // PYQs: from the freshly-fetched blocks plus anything embedded in stored text.
  const pyqs = [];
  const seenPyq = new Set();
  for (const a of articles) {
    const found = [
      ...(a._pyqs || []),
      ...parsePyqBlock(a.content || '', {
        subject: (a.categoryTags || []).find(Boolean) || 'General',
        gsPaper: a.upscPaper || '',
        sourceUrl: a.sourceUrl || '',
        topic: a.title || '',
      }),
    ];
    for (const q of found) {
      if (seenPyq.has(q.id)) continue;
      seenPyq.add(q.id);
      pyqs.push(q);
    }
    delete a._pyqs;
  }

  const flashcards = generateFlashcards(articles);
  const schemes = generateSchemes(articles);

  // Vocabulary is defined against a network dictionary, so mine it in dated
  // batches rather than from 196 articles at once — that keeps each day's list
  // drawn from that day's reading, which is the point of the feature.
  const byDate = new Map();
  for (const a of articles) {
    const d = a.publishedDate || 'undated';
    if (!byDate.has(d)) byDate.set(d, []);
    byDate.get(d).push(a);
  }
  const vocabulary = [];
  const seenWord = new Set();
  for (const [, group] of [...byDate.entries()].sort((x, y) => y[0].localeCompare(x[0]))) {
    const words = await extractDailyVocabulary(group, { limit: opts.vocabPerBatch, log: () => {} });
    for (const w of words) {
      const k = w.word.toLowerCase();
      if (seenWord.has(k)) continue;
      seenWord.add(k);
      vocabulary.push(w);
    }
  }

  console.log(
    `Derived: pyqs=${pyqs.length} vocabulary=${vocabulary.length} `
    + `flashcards=${flashcards.length} schemes=${schemes.length}`,
  );

  const p = await uploadPyqs(pyqs, opts.dryRun);
  const v = await uploadVocabulary(vocabulary, opts.dryRun);
  const f = await uploadFlashcards(flashcards, opts.dryRun);
  const s = await uploadSchemes(schemes, opts.dryRun);

  console.log('\n' + '='.repeat(66));
  console.log(
    `Done: pyqs(+${p.uploaded}/~${p.skipped}) vocabulary(+${v.uploaded}/~${v.skipped}) `
    + `flashcards(+${f.uploaded}/~${f.skipped}) schemes(+${s.uploaded}/~${s.skipped})`,
  );
  console.log('='.repeat(66));
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('Fatal error:', e);
    process.exit(1);
  });
