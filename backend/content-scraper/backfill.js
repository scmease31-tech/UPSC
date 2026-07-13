#!/usr/bin/env node
/**
 * Backfill derived study content from the articles already in Firestore.
 *
 * The daily scraper only derives vocabulary/flashcards/schemes from the articles
 * it scrapes in that run. This script (re)derives them from the FULL article
 * history, so existing articles also contribute flashcards, vocabulary and
 * schemes. Dedup-safe: existing docs are skipped.
 *
 * Usage:
 *   node backfill.js            # derive + upload
 *   node backfill.js --dry-run  # show what would be created
 *
 * Credentials: GOOGLE_APPLICATION_CREDENTIALS or FIREBASE_SERVICE_ACCOUNT_B64.
 */

import { getFirestore } from 'firebase-admin/firestore';
import { initFirebase, uploadVocabulary, uploadFlashcards, uploadSchemes } from './uploader.js';
import { generateAll } from './generators.js';

const dryRun = process.argv.includes('--dry-run');

initFirebase();
const db = getFirestore();

const snap = await db.collection('articles').get();
const articles = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
console.log(`Loaded ${articles.length} articles from Firestore.`);

const derived = generateAll(articles);
console.log(
  `Derived: vocabulary=${derived.vocabulary.length} ` +
  `flashcards=${derived.flashcards.length} schemes=${derived.schemes.length}`
);

const v = await uploadVocabulary(derived.vocabulary, dryRun);
const f = await uploadFlashcards(derived.flashcards, dryRun);
const s = await uploadSchemes(derived.schemes, dryRun);

console.log(
  `\nDone: vocabulary(+${v.uploaded}/~${v.skipped}) ` +
  `flashcards(+${f.uploaded}/~${f.skipped}) ` +
  `schemes(+${s.uploaded}/~${s.skipped})`
);
process.exit(0);
