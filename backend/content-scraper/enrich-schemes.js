#!/usr/bin/env node
/**
 * Backfill scheme detail onto the `govtSchemes` documents already in Firestore.
 *
 * Why this exists separately from backfill.js: uploadToCollection SKIPS any doc
 * whose id already exists, which is correct for "derive new content" but means a
 * document can never gain a field it was first written without. Scheme ids are
 * hashed from the name alone, so every scheme created before generateSchemes
 * produced detailedDescription / keyFeatures / upscRelevance / ministry keeps its
 * original thin shape permanently — and the app's detail sheet stays near-empty
 * no matter how often the scraper runs.
 *
 * This re-derives schemes from the full article history and fills ONLY the fields
 * an existing doc is missing. Non-empty values are never overwritten, so curated
 * text survives and a second run is a no-op.
 *
 * Usage:
 *   node enrich-schemes.js            # fill + create
 *   node enrich-schemes.js --dry-run  # report what would change
 *
 * Credentials: GOOGLE_APPLICATION_CREDENTIALS or FIREBASE_SERVICE_ACCOUNT_B64.
 */

import { getFirestore } from 'firebase-admin/firestore';
import { initFirebase, enrichSchemes, SCHEME_DETAIL_FIELDS, isBlank } from './uploader.js';
import { generateSchemes } from './generators.js';

const dryRun = process.argv.includes('--dry-run');

initFirebase();
const db = getFirestore();

const articleSnap = await db.collection('articles').get();
const articles = articleSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
console.log(`Loaded ${articles.length} articles.`);

// Report the CURRENT state first, so the log says plainly what was wrong.
const existingSnap = await db.collection('govtSchemes').get();
console.log(`\nExisting govtSchemes docs: ${existingSnap.size}`);
const missingCounts = Object.fromEntries(SCHEME_DETAIL_FIELDS.map((f) => [f, 0]));
for (const doc of existingSnap.docs) {
  const data = doc.data();
  for (const field of SCHEME_DETAIL_FIELDS) {
    if (isBlank(data[field])) missingCounts[field]++;
  }
}
console.log('Docs missing each detail field:');
for (const [field, n] of Object.entries(missingCounts)) {
  console.log(`  ${field.padEnd(22)} ${n}/${existingSnap.size}`);
}

const schemes = generateSchemes(articles);
console.log(`\nDerived ${schemes.length} schemes from the article history.`);
const withFeatures = schemes.filter((s) => !isBlank(s.keyFeatures)).length;
const withMinistry = schemes.filter((s) => !isBlank(s.ministry)).length;
console.log(`  with keyFeatures: ${withFeatures}`);
console.log(`  with ministry:    ${withMinistry}`);

const stats = await enrichSchemes(schemes, dryRun);
console.log(
  `\nDone${dryRun ? ' (dry run)' : ''}: created=${stats.created} ` +
    `enriched=${stats.enriched} unchanged=${stats.unchanged} errors=${stats.errors}`
);
process.exit(stats.errors > 0 ? 1 : 0);
