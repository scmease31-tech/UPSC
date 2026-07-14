#!/usr/bin/env node
/**
 * Daily Batch Ingest
 *
 * Scans a folder (default: ~/Downloads) AND its immediate subfolders (e.g.
 * ~/Downloads/News) for the day's UPSC PDFs, infers each file's type from its
 * name, and uploads them all to Firestore in one run. This is the "one command
 * / one double-click" daily workflow.
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

/**
 * Collect matching UPSC PDF jobs from a folder AND its immediate subfolders,
 * so files kept in e.g. Downloads\News are found without needing --dir.
 */
function collectJobs(baseDir, { respectDate, now, windowMs }) {
  const dirs = [baseDir];
  try {
    for (const entry of fs.readdirSync(baseDir, { withFileTypes: true })) {
      if (entry.isDirectory() && !entry.name.startsWith('.')) {
        dirs.push(path.join(baseDir, entry.name));
      }
    }
  } catch { /* ignore unreadable base dir */ }

  const jobs = [];
  const seen = new Set();
  for (const d of dirs) {
    let entries;
    try { entries = fs.readdirSync(d); } catch { continue; }
    for (const f of entries) {
      if (!f.toLowerCase().endsWith('.pdf')) continue;
      const full = path.join(d, f);
      if (seen.has(full)) continue;
      let stat;
      try { stat = fs.statSync(full); } catch { continue; }
      if (!stat.isFile()) continue;
      if (respectDate && now - stat.mtimeMs > windowMs) continue;
      const cls = classify(f);
      if (!cls) continue; // skip unrelated PDFs
      seen.add(full);
      jobs.push({ file: full, ...cls });
    }
  }
  return jobs;
}

async function main() {
  const opts = parseArgs();
  const baseDir = opts.dir || path.join(os.homedir(), 'Downloads');

  if (!fs.existsSync(baseDir)) {
    console.error(`Folder not found: ${baseDir}`);
    process.exit(1);
  }

  const now = Date.now();
  const windowMs = opts.since * 24 * 60 * 60 * 1000;

  // Scan the folder and its immediate subfolders (e.g. Downloads\News).
  let jobs = collectJobs(baseDir, { respectDate: !opts.all, now, windowMs });

  // If nothing matched the recency window but there ARE UPSC PDFs in the
  // folder(s), use them anyway (uploads are de-duplicated). This keeps the
  // double-click reliable even when the files are a few days old.
  let usedDateFallback = false;
  if (jobs.length === 0 && !opts.all) {
    const anyJobs = collectJobs(baseDir, { respectDate: false, now, windowMs });
    if (anyJobs.length > 0) { jobs = anyJobs; usedDateFallback = true; }
  }

  console.log('='.repeat(64));
  console.log(`  UPSC Daily PDF Ingest`);
  console.log(`  Folder: ${baseDir}  (incl. subfolders)`);
  console.log(`  Filter: ${opts.all || usedDateFallback ? 'all files' : `modified in last ${opts.since} day(s)`}`);
  console.log(`  Mode:   ${opts.dryRun ? 'DRY RUN (no upload)' : 'LIVE'}`);
  console.log('='.repeat(64));

  if (usedDateFallback) {
    console.log(`\n(Nothing modified in the last ${opts.since} day(s); using all UPSC PDFs found instead.)`);
  }

  if (jobs.length === 0) {
    console.log('\nNo matching UPSC PDFs found.');
    console.log('Looked in the folder above and its subfolders (e.g. "News").');
    console.log('Make sure the files are named like');
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
      results.push(await ingestFile({
        ...j,
        dryRun: opts.dryRun,
        // Newspapers extract full article text; editorials are schemes-only by
        // default (editorial compilation PDFs interleave multiple papers, so
        // their article segmentation is unreliable). Pass --articles to force.
        articles: opts.articles || j.type === 'newspaper',
      }));
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
