#!/usr/bin/env node
/**
 * Inbox Ingest — the zero-setup "drop a newspaper in and it appears in the app"
 * path.
 *
 * You put a PDF (or a photo of a page) into the repository's `inbox/` folder —
 * from github.com, from the phone, from anywhere — and the
 * `newspaper-inbox` GitHub Action runs this script. It:
 *
 *   1. picks up every file in `inbox/`
 *   2. works out what it is from the filename (newspaper / editorial /
 *      vocabulary), defaulting to a newspaper named after the file
 *   3. extracts the text — falling back to OCR when the PDF is a scan
 *   4. uploads articles, flashcards, schemes and vocabulary to Firestore
 *   5. moves the file to `inbox/archive/<YYYY-MM>/` and appends a receipt to
 *      `inbox/PROCESSED.md`
 *
 * Runs locally too:
 *   node inbox-ingest.js --dry-run
 *   node inbox-ingest.js --dir path/to/folder --keep
 *
 * Credentials: FIREBASE_SERVICE_ACCOUNT_B64 or GOOGLE_APPLICATION_CREDENTIALS.
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

import { initFirebase } from './uploader.js';
import { ingestFile } from './pdf-ingest.js';
import { ocrAvailable, ocrImage } from './ocr.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(HERE, '..', '..');

const SUPPORTED = /\.(pdf|png|jpe?g|webp|tiff?)$/i;
const IGNORED = /^(readme|processed|\.gitkeep)/i;

function parseArgs() {
  const args = process.argv.slice(2);
  const opts = { dir: null, dryRun: false, keep: false, archive: false, ocrPages: 12 };
  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--dir': opts.dir = args[++i] || null; break;
      case '--dry-run': opts.dryRun = true; break;
      case '--keep': opts.keep = true; break;
      case '--archive': opts.archive = true; break;
      case '--ocr-pages': opts.ocrPages = parseInt(args[++i], 10) || 12; break;
    }
  }
  return opts;
}

/**
 * Work out what a dropped file is from its name.
 *
 * Unlike the stricter daily-ingest classifier, this NEVER returns null: the
 * whole point of the inbox is that you can drop anything in and it is handled.
 * An unrecognised PDF is treated as a newspaper titled after the file.
 */
export function classify(filename) {
  // Underscores and tildes are word characters to a regex, so "TOI_25_07" would
  // never match /\btoi\b/. Flatten every separator to a space first.
  const n = filename.toLowerCase().replace(/[_~.\-+]+/g, ' ');

  if (n.includes('vocab')) return { type: 'vocabulary', source: null, label: 'vocabulary' };

  // Question papers: "CSP 2024 GS Paper I.pdf", "UPSC Prelims 2023 PYQ.pdf",
  // "QP-CSM-23-GENERAL-STUDIES-PAPER-I.pdf". Routed to the PYQ parser so the
  // Previous Year Questions tab can be filled by uploading a paper.
  if (/\b(pyq|question paper|prelims|mains|csat)\b/.test(n) || /\bqp[- _]/.test(n) || /\bcs[pm]\b/.test(n)) {
    const yearMatch = n.match(/\b(19|20)\d{2}\b/) || n.match(/\bcs[pm][-_ ](\d{2})\b/);
    let year = yearMatch ? parseInt(yearMatch[0].replace(/\D/g, ''), 10) : 0;
    if (year > 0 && year < 100) year += 2000;

    const isPrelims = /\b(prelims|csat|csp)\b/.test(n);
    const gs = n.match(/\b(?:gs|general studies)[- ]?(?:paper[- ]?)?(i{1,3}v?|[1-4])\b/);
    const roman = { 1: 'I', 2: 'II', 3: 'III', 4: 'IV' };
    const paperNum = gs ? (roman[gs[1]] || gs[1].toUpperCase()) : '';

    return {
      type: 'questionpaper',
      source: 'UPSC',
      label: `question paper${year ? ` (${year})` : ''}`,
      exam: isPrelims ? 'CSP' : 'CSM',
      year,
      paper: isPrelims
        ? (/csat|paper[- ]?(ii|2)\b/.test(n) ? 'Prelims GS-II (CSAT)' : 'Prelims GS-I')
        : (/essay/.test(n) ? 'Essay' : paperNum ? `GS-${paperNum}` : 'Mains'),
    };
  }

  if (n.includes('editorial')) return { type: 'editorial', source: 'Editorials', label: 'editorials' };

  const papers = [
    [/the hindu|\bth +delhi\b|\bthe +hindu\b/, 'The Hindu'],
    [/indian express|\bie +delhi\b/, 'Indian Express'],
    [/times of india|\btoi\b/, 'Times of India'],
    [/business standard|\bbs +delhi\b/, 'Business Standard'],
    [/livemint|\bmint\b/, 'Mint'],
    [/economic times|\bet +delhi\b/, 'Economic Times'],
    [/hindustan times|\bht +delhi\b/, 'Hindustan Times'],
    [/\bpib\b|press information/, 'PIB'],
    [/yojana/, 'Yojana'],
    [/kurukshetra/, 'Kurukshetra'],
    [/down to earth|\bdte\b/, 'Down To Earth'],
  ];
  for (const [re, name] of papers) {
    if (re.test(n)) return { type: 'newspaper', source: name, label: name };
  }

  // Unknown file: use a tidied-up filename as the source label so the article
  // still shows a sensible provenance in the app.
  const pretty = path
    .basename(filename)
    .replace(SUPPORTED, '')
    .replace(/[_~]+/g, ' ')
    .replace(/\d{1,2}[-~._ /]\d{1,2}[-~._ /]\d{2,4}/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  return {
    type: 'newspaper',
    source: pretty.length >= 3 ? pretty.slice(0, 60) : 'Newspaper',
    label: 'newspaper (auto)',
  };
}

function collectFiles(dir) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return [];
  }
  return entries
    .filter((e) => e.isFile() && SUPPORTED.test(e.name) && !IGNORED.test(e.name))
    .map((e) => path.join(dir, e.name))
    .sort();
}

/** Photos of a page are OCR'd straight to text and ingested as a newspaper. */
async function ingestImage(file, cls, { dryRun }) {
  const base = path.basename(file);
  if (!ocrAvailable()) {
    console.warn(`  [skip] ${base}: image upload needs tesseract-ocr, which is unavailable here.`);
    return { file: base, error: 'no-ocr' };
  }
  console.log(`  [ocr ] ${base}: reading image…`);
  const text = ocrImage(file);
  if (!text || text.length < 200) {
    console.warn(`  [skip] ${base}: OCR produced too little text (${text.length} chars).`);
    return { file: base, error: 'ocr-empty' };
  }

  // Reuse the PDF path by staging the text as a .txt sidecar is not possible —
  // instead write a minimal single-page PDF-free route: hand the text straight
  // to the article parser through pdf-ingest's exported helper.
  const { ingestText } = await import('./pdf-ingest.js');
  return ingestText({
    text,
    name: base,
    type: cls.type,
    source: cls.source,
    dryRun,
    articles: true,
  });
}

/** A dropped question paper becomes Previous Year Questions in the app. */
async function ingestQuestionPaper(job, { dryRun, maxPages }) {
  const base = path.basename(job.file);
  const year = job.year || new Date().getUTCFullYear();
  if (!job.year) {
    console.warn(`  [warn] ${base}: no year in the filename — filing under ${year}.`);
  }
  console.log(`  [pyq ] ${base}: ${job.exam} ${year} ${job.paper}`);

  const { ingestPaperFile } = await import('./upsc-papers.js');
  const r = await ingestPaperFile(
    job.file,
    { exam: job.exam, year, paper: job.paper, url: '' },
    { dryRun, maxPages },
  );
  return { file: base, type: 'questionpaper', pyqs: r.stats, parsed: r.parsed };
}

async function main() {
  const opts = parseArgs();
  const inboxDir = opts.dir ? path.resolve(opts.dir) : path.join(REPO_ROOT, 'inbox');

  console.log('='.repeat(66));
  console.log('  UPSC Inbox Ingest');
  console.log(`  Folder: ${inboxDir}`);
  console.log(`  Mode:   ${opts.dryRun ? 'DRY RUN (nothing uploaded)' : 'LIVE'}`);
  console.log(`  OCR:    ${ocrAvailable() ? 'available' : 'NOT available (scanned PDFs will be skipped)'}`);
  console.log('='.repeat(66));

  if (!fs.existsSync(inboxDir)) {
    console.log(`\nNothing to do — ${inboxDir} does not exist.`);
    return;
  }

  const files = collectFiles(inboxDir);
  if (files.length === 0) {
    console.log('\nInbox is empty. Drop a PDF into it and push — that is the whole workflow.');
    return;
  }

  console.log(`\nFound ${files.length} file(s):`);
  const jobs = files.map((f) => ({ file: f, ...classify(path.basename(f)) }));
  for (const j of jobs) {
    console.log(`  - ${path.basename(j.file)}  ->  ${j.label}${j.source ? ` (${j.source})` : ''}`);
  }
  console.log('');

  if (!opts.dryRun) initFirebase();

  const results = [];
  for (const job of jobs) {
    const base = path.basename(job.file);
    try {
      const isImage = !/\.pdf$/i.test(base);
      const result = job.type === 'questionpaper'
        ? await ingestQuestionPaper(job, { dryRun: opts.dryRun, maxPages: opts.ocrPages })
        : isImage
        ? await ingestImage(job.file, job, { dryRun: opts.dryRun })
        : await ingestFile({
            file: job.file,
            type: job.type,
            source: job.source,
            dryRun: opts.dryRun,
            // Newspapers and editorials dropped here are meant to become
            // readable articles, so always attempt article extraction.
            articles: job.type !== 'vocabulary',
            ocr: true,
            ocrMaxPages: opts.ocrPages,
          });
      results.push({ ...result, file: base, job });
    } catch (e) {
      console.error(`  [err] ${base}: ${e.message}`);
      results.push({ file: base, error: e.message, job });
    }
  }

  // ── Clear processed files and write a receipt ──
  // Newspaper PDFs run to tens of megabytes and git never forgets, so the
  // default is to remove the file once its content is safely in Firestore.
  // Pass --archive to keep a copy under inbox/archive/ instead.
  if (!opts.dryRun && !opts.keep) {
    for (const r of results) {
      if (r.error) continue; // leave failures in the inbox so they can be retried
      if (opts.archive) archive(inboxDir, r.job.file);
      else fs.rmSync(r.job.file, { force: true });
    }
    writeReceipt(inboxDir, results);
  }

  console.log('\n' + '='.repeat(66));
  console.log('  Summary');
  console.log('='.repeat(66));
  for (const r of results) {
    console.log(`  ${r.file}: ${describe(r)}`);
  }
  console.log('='.repeat(66));
  console.log(
    opts.dryRun
      ? 'Dry run complete (nothing uploaded).'
      : 'Done. Pull to refresh in the app — the new content is already there.',
  );
}

function describe(r) {
  if (r.error) return `ERROR (${r.error})`;
  const bits = [];
  if (r.pyqs && typeof r.pyqs.uploaded === 'number') bits.push(`PYQs +${r.pyqs.uploaded} (parsed ${r.parsed})`);
  if (r.vocabulary && typeof r.vocabulary.uploaded === 'number') bits.push(`vocabulary +${r.vocabulary.uploaded}`);
  if (r.articles && typeof r.articles.uploaded === 'number') bits.push(`articles +${r.articles.uploaded}`);
  if (r.flashcards && typeof r.flashcards.uploaded === 'number') bits.push(`flashcards +${r.flashcards.uploaded}`);
  if (r.schemes && typeof r.schemes.uploaded === 'number') bits.push(`schemes +${r.schemes.uploaded}`);
  return bits.length ? bits.join(', ') : 'processed (nothing new)';
}

function archive(inboxDir, file) {
  const now = new Date();
  const bucket = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`;
  const destDir = path.join(inboxDir, 'archive', bucket);
  fs.mkdirSync(destDir, { recursive: true });
  const dest = path.join(destDir, path.basename(file));
  try {
    fs.renameSync(file, dest);
  } catch {
    // Cross-device or permission issue: copy then unlink.
    fs.copyFileSync(file, dest);
    fs.unlinkSync(file);
  }
}

function writeReceipt(inboxDir, results) {
  const receipt = path.join(inboxDir, 'PROCESSED.md');
  const stamp = new Date().toISOString().replace('T', ' ').slice(0, 16);
  const lines = results.map((r) => `| ${stamp} | ${r.file} | ${describe(r)} |`);

  let existing = '';
  try {
    existing = fs.readFileSync(receipt, 'utf-8');
  } catch { /* first run */ }

  if (!existing) {
    existing = '# Processed uploads\n\nEvery file dropped into `inbox/` ends up here.\n\n| When (UTC) | File | Result |\n| --- | --- | --- |\n';
  }
  fs.writeFileSync(receipt, `${existing.trimEnd()}\n${lines.join('\n')}\n`, 'utf-8');
}

// Only run when invoked directly, so `classify` stays importable by tests.
if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  main().catch((e) => {
    console.error('Fatal error:', e);
    process.exit(1);
  });
}
