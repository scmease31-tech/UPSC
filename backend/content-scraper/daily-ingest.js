#!/usr/bin/env node
/**
 * Daily Batch Ingest
 *
 * Scans a folder (default: ~/Downloads) for the day's UPSC PDFs, infers each
 * file's type from its name, and uploads them all to Firestore in one run.
 * This is the "one command / one double-click" daily workflow.
 *
 * Recognised filenames:
 *   *vocab*                         -> vocabulary
 *   *editorial*                     -> editorial (schemes)
 *   *the hindu* / *TH Delhi*        -> newspaper "The Hindu" (schemes)
 *   *indian express* / *IE Delhi*   -> newspaper "Indian Express" (schemes)
 *   *times of india* / *TOI*        -> newspaper "Times of India" (schemes)
 *   *business standard*             -> newspaper "Business Standard" (schemes)
 *   *mint* / *livemint*             -> newspaper "Mint" (schemes)
 *
 * Usage:
 *   node daily-ingest.js                  # ~/Downloads, files from last 3 days
 *   node daily-ingest.js --dir "D:\pdfs"  # a specific folder
 *   node daily-ingest.js --since 7        # widen the recency window (days)
 *   node daily-ingest.js --all            # ignore the date filter
 *   node daily-ingest.js --dry-run        # parse only, do not upload
 *
 * Credentials: set GOOGLE_APPLICATION_CREDENTIALS (or FIREBASE_SERVICE_ACCOUNT_B64).
 * The daily-upload.bat wrapper auto-detects the Firebase key for you.
 */

import fs from 'fs';
import path from 'path';
import os from 'os';
import { initFirebase } from './uploader.js';
import { ingestFile } from './pdf-ingest.js';

function parseArgs() {
  const args = process.argv.slice(2);
  const opts = { dir: null, since: 3, all: false, dryRun: false, articles: false };
  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--dir': opts.dir = args[++i] || null; break;
      case '--since': opts.since = parseInt(args[++i], 10) || 3; break;
      case '--all': opts.all = true; break;
      case '--dry-run': opts.dryRun = true; break;
      case '--articles': opts.articles = true; break;
    }
  }
  return opts;
}

/** Infer ingest type + source from a filename. Returns null for non-UPSC PDFs. */
function classify(name) {
  const n = name.toLowerCase();
  if (n.includes('vocab')) return { type: 'vocabulary' };
  if (n.includes('editorial')) return { type: 'editorial', source: 'Editorials' };
  if (n.includes('the hindu') || /\bth[ _~.-]*delhi\b/.test(n)) return { type: 'newspaper', source: 'The Hindu' };
  if (n.includes('indian express') || /\bie[ _~.-]*delhi\b/.test(n)) return { type: 'newspaper', source: 'Indian Express' };
  if (n.includes('times of india') || /\btoi\b/.test(n)) return { type: 'newspaper', source: 'Times of India' };
  if (n.includes('business standard')) return { type: 'newspaper', source: 'Business Standard' };
  if (n.includes('livemint') || /\bmint\b/.test(n)) return { type: 'newspaper', source: 'Mint' };
  if (n.includes('economic times')) return { type: 'newspaper', source: 'Economic Times' };
  return null;
}

function fmt(stats) {
  if (!stats || typeof stats.uploaded !== 'number') return '-';
  return `+${stats.uploaded} added, ${stats.skipped} existing`;
}

async function main() {
  const opts = parseArgs();
  const dir = opts.dir || path.join(os.homedir(), 'Downloads');

  if (!fs.existsSync(dir)) {
    console.error(`Folder not found: ${dir}`);
    process.exit(1);
  }

  const now = Date.now();
  const windowMs = opts.since * 24 * 60 * 60 * 1000;

  const jobs = [];
  for (const f of fs.readdirSync(dir)) {
    if (!f.toLowerCase().endsWith('.pdf')) continue;
    const full = path.join(dir, f);
    let stat;
    try { stat = fs.statSync(full); } catch { continue; }
    if (!stat.isFile()) continue;
    if (!opts.all && now - stat.mtimeMs > windowMs) continue;
    const cls = classify(f);
    if (!cls) continue; // skip unrelated PDFs
    jobs.push({ file: full, ...cls });
  }

  console.log('='.repeat(64));
  console.log(`  UPSC Daily PDF Ingest`);
  console.log(`  Folder: ${dir}`);
  console.log(`  Filter: ${opts.all ? 'all files' : `modified in last ${opts.since} day(s)`}`);
  console.log(`  Mode:   ${opts.dryRun ? 'DRY RUN (no upload)' : 'LIVE'}`);
  console.log('='.repeat(64));

  if (jobs.length === 0) {
    console.log('\nNo matching UPSC PDFs found.');
    console.log('Make sure the files are in the folder above and named like');
    console.log('"Daily Vocabulary ...", "... Editorials ...", "IE Delhi ...", "TH Delhi ...".');
    return;
  }

  console.log(`\nFound ${jobs.length} PDF(s):`);
  for (const j of jobs) {
    console.log(`  - ${path.basename(j.file)}  ->  ${j.type}${j.source ? ` (${j.source})` : ''}`);
  }
  console.log('');

  if (!opts.dryRun) initFirebase();

  const results = [];
  for (const j of jobs) {
    try {
      results.push(await ingestFile({ ...j, dryRun: opts.dryRun, articles: opts.articles }));
    } catch (e) {
      console.error(`  [err] ${path.basename(j.file)}: ${e.message}`);
      results.push({ file: path.basename(j.file), type: j.type, error: e.message });
    }
  }

  console.log('\n' + '='.repeat(64));
  console.log('  Summary');
  console.log('='.repeat(64));
  for (const r of results) {
    if (r.error) { console.log(`  ${r.file}: ERROR (${r.error})`); continue; }
    if (r.vocabulary) console.log(`  ${r.file}: vocabulary ${fmt(r.vocabulary)}`);
    else if (r.schemes) console.log(`  ${r.file}: schemes ${fmt(r.schemes)}`);
    else console.log(`  ${r.file}: processed`);
  }
  console.log('='.repeat(64));
  console.log(opts.dryRun ? 'Dry run complete (nothing uploaded).' : 'Upload complete. Open the app to see the new content.');
}

main().catch((e) => {
  console.error('Fatal error:', e);
  process.exit(1);
});
