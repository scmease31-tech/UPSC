#!/usr/bin/env node
/**
 * Official UPSC question papers → the `pyqs` collection.
 *
 * Downloads Civil Services Examination papers straight from upsc.gov.in,
 * extracts the questions and uploads them with verified provenance, so the PYQ
 * tab carries what UPSC actually asked rather than practice approximations.
 *
 * Two facts shape this file:
 *
 *   1. The papers are published as **image-only scans** — 30 MB, 48 pages, zero
 *      text layer — so OCR is mandatory (see ocr.js).
 *   2. Every page carries the English and Hindi versions of each question, so
 *      Devanagari has to be stripped before parsing.
 *
 * UPSC does not publish answer keys alongside the papers, so questions land
 * with `answer: -1`. The app shows them as official-but-unkeyed, and where the
 * daily Drishti harvest has the same question WITH its key, PyqService prefers
 * the answered copy.
 *
 * Usage:
 *   node upsc-papers.js --list                 # show what is available
 *   node upsc-papers.js --exam CSP --year 2024 # ingest one paper
 *   node upsc-papers.js --exam CSP --latest 3  # the three most recent
 *   node upsc-papers.js --url <pdf> --year 2024 --dry-run
 */

import fs from 'fs';
import os from 'os';
import path from 'path';
import crypto from 'crypto';
import { fileURLToPath } from 'url';

import { initFirebase, uploadPyqs } from './uploader.js';
import { ocrAvailable, ocrPdf, hasLanguage } from './ocr.js';

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

// The bare domain serves a truncated page with the paper table missing; the
// www host serves the full listing. This tripped up the first implementation.
const LISTING_URL = 'https://www.upsc.gov.in/examinations/previous-question-papers';

// ─────────────────────────────────────────────────────────────────────────────
// Listing
// ─────────────────────────────────────────────────────────────────────────────

/** Two-digit or four-digit year in a UPSC filename → full year. */
function normaliseYear(raw) {
  const n = parseInt(raw, 10);
  if (Number.isNaN(n)) return 0;
  if (n >= 1990 && n <= 2100) return n;
  if (n >= 0 && n <= 99) return 2000 + n;
  return 0;
}

/**
 * Classify a UPSC question-paper URL.
 * @returns {{exam:string, year:number, paper:string, url:string}|null}
 */
export function classifyPaper(url) {
  const name = decodeURIComponent(url.split('/').pop() || '');
  const upper = name.toUpperCase();

  // Civil Services Preliminary — "QP_CSP_2026_..." or "QP-CSP-25-...".
  let m = upper.match(/QP[-_]CSP[-_](\d{2,4})[-_]/);
  if (m) {
    // "\b" will not fire between "II" and "_" because underscore is a word
    // character — match on "not followed by another numeral letter" instead.
    const paper = /PAPER[-_ ]?II(?![IV])/.test(upper) ? 'Prelims GS-II (CSAT)' : 'Prelims GS-I';
    return { exam: 'CSP', year: normaliseYear(m[1]), paper, url };
  }

  // Civil Services Mains — the exam token can trail the subject, e.g.
  // "ASSAMESE-LITERATURE-PAPER I-QP-CSM-25-010925.pdf".
  m = upper.match(/QP[-_]CSM[-_](\d{2,4})[-_]/);
  if (m) {
    const gs = upper.match(/GENERAL[-_ ]STUDIES[-_ ]PAPER[-_ ]?(I{1,3}V?)/);
    const essay = /\bESSAY\b/.test(upper);
    // Everything that is neither GS nor Essay is an optional-subject paper
    // (literature, anthropology, botany …). Those are only relevant to the
    // handful of candidates taking that optional, so they are excluded by
    // default rather than flooding the shared PYQ bank.
    const paper = essay ? 'Essay' : gs ? `GS-${gs[1]}` : 'Optional';
    return { exam: 'CSM', year: normaliseYear(m[1]), paper, url };
  }

  return null;
}

/** Every CSE question paper currently published on upsc.gov.in. */
export async function listPapers() {
  const res = await fetch(LISTING_URL, {
    headers: { 'User-Agent': UA, Accept: 'text/html' },
  });
  if (!res.ok) throw new Error(`Listing fetch failed: HTTP ${res.status}`);
  const html = await res.text();

  const urls = [...new Set(
    [...html.matchAll(/href="([^"]*\.pdf[^"]*)"/gi)].map((m) => m[1]),
  )].map((u) => (u.startsWith('http') ? u : `https://www.upsc.gov.in${u}`));

  return urls
    .map(classifyPaper)
    .filter((p) => p && p.year > 0)
    .sort((a, b) => b.year - a.year || a.paper.localeCompare(b.paper));
}

// ─────────────────────────────────────────────────────────────────────────────
// Parsing
// ─────────────────────────────────────────────────────────────────────────────

const DEVANAGARI = /[ऀ-ॿ]/;

/**
 * Common English function words. Every UPSC paper prints each question in both
 * Hindi and English; Tesseract in `-l eng` mode transliterates the Devanagari
 * into meaningless Latin ("faaneat", "TTAT AEQA"), which no Devanagari filter
 * can catch. Counting function words separates real English from that noise
 * reliably, because the transliteration essentially never produces them.
 */
const STOPWORD_RE = /\b(the|of|and|in|to|is|are|for|with|on|as|by|that|it|its|has|have|been|be|from|this|these|their|which|what|how|why|an|a|or|not|do|does)\b/gi;

function isEnglishLine(line) {
  const words = line.split(/\s+/).filter(Boolean);
  if (words.length < 3) return false;

  // Distinct function words, not repeats — transliterated Devanagari throws off
  // single-token matches like a stray "a" or "A".
  const stops = new Set((line.match(STOPWORD_RE) || []).map((w) => w.toLowerCase()));
  if (stops.size < 2) return false;

  // Most tokens should look like real words. Transliteration output is full of
  // vowel-less fragments ("gf", "sfaa-a", "aq.") that fail this.
  return wordLikeRatio(words) >= 0.6;
}

function wordLikeRatio(words) {
  const wordLike = words.filter((w) => {
    // Strip surrounding punctuation first, or "India." and "(the" would count
    // as junk and drag the ratio down on perfectly ordinary prose.
    const bare = w.replace(/^[^A-Za-z]+|[^A-Za-z]+$/g, '');
    return bare.length >= 2 && /^[A-Za-z][A-Za-z'-]*$/.test(bare) && /[aeiou]/i.test(bare);
  });
  return wordLike.length / words.length;
}

/**
 * Looser test for a line that *continues* a question already in progress.
 *
 * Question tails are often short ("self-governance in India. 15") and carry too
 * few function words for the strict test, which would otherwise fragment the
 * question and lose it entirely. Safe to be lenient here because [looksClean]
 * still gates whatever is finally emitted.
 */
function isEnglishContinuation(line) {
  const words = line.split(/\s+/).filter(Boolean);
  if (words.length === 0) return false;
  if (wordLikeRatio(words) < 0.75) return false;
  if (words.length <= 10) return true;
  const stops = new Set((line.match(STOPWORD_RE) || []).map((w) => w.toLowerCase()));
  return stops.size >= 1;
}

/**
 * Final gate before a question is published.
 *
 * OCR of a bilingual scan will always leak some transliterated Devanagari, and
 * a study app showing "fret & gon va atfae" as a UPSC question is worse than
 * showing fewer questions. Anything that does not read as clean English prose
 * is dropped rather than cleaned up heuristically.
 */
function looksClean(question) {
  const words = question.split(/\s+/).filter(Boolean);
  if (words.length < 8) return false;
  if (wordLikeRatio(words) < 0.85) return false;
  // Three consecutive junk tokens is the signature of a transliterated run.
  let junkRun = 0;
  for (const w of words) {
    const junk = !/^[A-Za-z][A-Za-z'-]*[.,;:?!"']?$/.test(w) || (w.length > 1 && !/[aeiou]/i.test(w));
    junkRun = junk ? junkRun + 1 : 0;
    if (junkRun >= 3) return false;
  }
  return true;
}

/** Boilerplate that reads as English but is not a question. */
const INSTRUCTION_RE = /(question[- ]cum[- ]answer|qca\b|marks carried by|medium authorized|admission certificate|word limit|are compulsory|printed both in hindi|struck off|space for rough work|do not open|attempting questions|instructions|maximum marks|time allowed|answers must be written|left blank)/i;

/**
 * Clean OCR output: keep the English half, drop page furniture.
 */
function cleanPaperText(raw) {
  return raw
    .split(/\r?\n/)
    .map((l) => l.replace(/\s+/g, ' ').trim())
    .filter((l) => l.length > 0)
    .filter((l) => !DEVANAGARI.test(l))
    .filter((l) => !/^(space for rough work|do not open|this booklet|test booklet|serial no)/i.test(l))
    .join('\n');
}

/** Fix the handful of OCR confusions that break question/option detection. */
function repairOcr(text) {
  return text
    // "(a)" often comes back as "(@)", "(0)", "(¢)", "(4)".
    .replace(/\(\s*@\s*\)/g, '(a)')
    .replace(/\(\s*[¢c]\s*\)/gi, '(c)')
    .replace(/\(\s*[bh6]\s*\)/g, '(b)')
    .replace(/\(\s*[d4]\s*\)/g, '(d)')
    .replace(/[“”]/g, '"')
    .replace(/[‘’]/g, "'");
}

function hashId(...parts) {
  return `upsc_${crypto.createHash('md5').update(parts.join('|').toLowerCase()).digest('hex').slice(0, 16)}`;
}

/**
 * Split cleaned paper text into numbered question blocks.
 *
 * Only accepts a number that continues the sequence, which is what keeps stray
 * numbered statements inside a question ("1. …  2. …") from being mistaken for
 * new questions.
 */
function questionBlocks(text) {
  const lines = text.split('\n');
  const starts = [];
  let expected = 1;

  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^(\d{1,3})[.)]\s+(.{4,})/);
    if (!m) continue;
    const n = parseInt(m[1], 10);
    if (n !== expected) continue;
    starts.push({ index: i, number: n });
    expected++;
  }

  return starts.map((s, k) => ({
    number: s.number,
    text: lines.slice(s.index, starts[k + 1]?.index ?? lines.length).join('\n'),
  }));
}

/**
 * Parse a Prelims paper into MCQ documents.
 * @param {string} rawText  OCR output for the whole paper.
 */
export function parsePrelimsPaper(rawText, { year, paper = 'Prelims GS-I', url = '' }) {
  const lines = repairOcr(cleanPaperText(rawText)).split('\n');
  const out = [];

  // Driven by the option block, not the question number.
  //
  // UPSC stems routinely contain their own numbered statement lists ("1. …
  // 2. …"), so tracking a running question number picks up those statements as
  // new questions. The "(a)…(d)" group, by contrast, appears exactly once per
  // question and is unambiguous.
  const optionStarts = [];
  for (let i = 0; i < lines.length; i++) {
    if (/^\(a\)/i.test(lines[i].trim())) optionStarts.push(i);
  }

  let stemFrom = 0;
  for (let k = 0; k < optionStarts.length; k++) {
    const optLine = optionStarts[k];

    const stem = lines
      .slice(stemFrom, optLine)
      .join(' ')
      .replace(/^\s*\d{1,3}[.)]\s*/, '')
      .replace(/\s+/g, ' ')
      .trim();

    // Options end where the next question's stem begins.
    let optEnd = lines.length;
    for (let i = optLine; i < lines.length; i++) {
      if (/^\(d\)/i.test(lines[i].trim())) { optEnd = i + 1; break; }
    }
    stemFrom = optEnd;

    if (stem.length < 25) continue;

    const options = [];
    const optRe = /\(([a-d])\)\s*([\s\S]*?)(?=\n\([a-d]\)|$)/gi;
    let m;
    const optText = lines.slice(optLine, optEnd).join('\n');
    while ((m = optRe.exec(optText)) !== null) {
      const idx = m[1].toLowerCase().charCodeAt(0) - 97;
      const value = m[2].replace(/\s+/g, ' ').trim();
      if (idx >= 0 && idx < 4 && value && !options[idx]) options[idx] = value.slice(0, 300);
    }
    const filled = options.filter(Boolean);
    if (filled.length !== 4) continue;

    out.push({
      id: hashId('prelims', year, stem.slice(0, 120)),
      type: 'prelims',
      year,
      paper,
      subject: guessSubject(stem),
      marks: 0,
      question: stem.slice(0, 900),
      options: filled,
      // UPSC publishes papers without keys; the app labels these clearly and a
      // matching Drishti harvest supplies the answer when one exists.
      answer: -1,
      explanation: '',
      approach: '',
      source: 'UPSC',
      sourceUrl: url,
      official: true,
    });
  }

  return out;
}

/**
 * Parse a Mains/Essay paper into question documents.
 *
 * Question numbers do not survive OCR on these scans (they sit in their own
 * narrow column and are usually dropped), so questions are delimited by the
 * thing that is always printed and always recognised: the mark allocation at
 * the end of each question — 10, 15, 20 for GS; 125/150 for Essay.
 */
export function parseMainsPaper(rawText, { year, paper = 'Mains', url = '' }) {
  const lines = repairOcr(cleanPaperText(rawText)).split('\n');
  const out = [];

  let rejected = 0;
  let buffer = [];
  const flush = (marks) => {
    const question = buffer
      .join(' ')
      .replace(/^\s*\d{1,3}[.)]\s*/, '')
      .replace(/\(\s*answer in \d+ words\s*\)/gi, '')
      .replace(/\s*\(?\b(?:10|15|20|25|125|150|250)\b\s*(?:marks?)?\)?\s*$/i, '')
      .replace(/\s+/g, ' ')
      .trim();
    buffer = [];

    if (question.length < 40) return;
    if (INSTRUCTION_RE.test(question)) return;
    if (/\(a\)/i.test(question)) return; // an MCQ leaked in from a prelims paper
    if (!looksClean(question)) { rejected++; return; }

    out.push({
      id: hashId('mains', year, question.slice(0, 120)),
      type: 'mains',
      year,
      paper,
      subject: guessSubject(question),
      marks,
      question: question.slice(0, 900),
      options: [],
      answer: -1,
      explanation: '',
      approach: '',
      source: 'UPSC',
      sourceUrl: url,
      official: true,
    });
  };

  const MARKS_TAIL = /(?:^|\s)\(?(10|15|20|25|125|150|250)\s*(?:marks?)?\)?\s*$/i;

  for (const line of lines) {
    const trailing = line.match(MARKS_TAIL);

    // Once a question is open, take its shorter tail lines too. A line ending
    // in the mark allocation is always the question's last line — accept it
    // regardless of how it scores, since the marks token itself drags a short
    // tail like "public administration. 15" below the prose threshold.
    const keep = buffer.length > 0
      ? (trailing !== null || isEnglishContinuation(line))
      : isEnglishLine(line);

    if (!keep) {
      // A bare marks value on its own line closes the current question.
      const solo = line.match(/^\(?\s*(10|15|20|25|125|150|250)\s*(?:marks?)?\)?\s*$/i);
      if (solo && buffer.length) flush(parseInt(solo[1], 10));
      continue;
    }

    buffer.push(line);
    if (trailing) flush(parseInt(trailing[1], 10));

    // Runaway guard: never let one unterminated block swallow the paper.
    if (buffer.length > 12) buffer = buffer.slice(-6);
  }

  if (rejected) {
    console.log(`        (${rejected} block(s) dropped: OCR text too noisy to publish)`);
  }
  return out;
}

/** Rough subject tagging so the PYQ tab's facets stay useful. */
const SUBJECT_HINTS = [
  ['Polity', /constitution|parliament|judiciar|fundamental right|article \d|amendment|governor|president|panchayat|election/i],
  ['Economy', /econom|fiscal|monetary|inflation|gdp|bank|tax|budget|trade|investment|rupee|market/i],
  ['Environment', /environment|climate|biodiversity|forest|wildlife|pollution|ecosystem|conservation|carbon/i],
  ['Science & Technology', /technolog|space|satellite|vaccine|dna|quantum|semiconductor|artificial intelligence|nuclear|biotech/i],
  ['History', /dynasty|empire|ancient|medieval|freedom struggle|movement of \d{4}|inscription|temple|buddhis|jain|mughal|colonial/i],
  ['Geography', /river|monsoon|latitude|plateau|glacier|soil|ocean|cyclone|earthquake|mineral|mountain/i],
  ['International Relations', /bilateral|united nations|treaty|summit|foreign policy|diplomat|world trade|international organi/i],
  ['Social Issues', /education|health|poverty|women|tribal|caste|census|employment|migration|nutrition/i],
  ['Security', /security|defence|terroris|cyber|border|armed forces|insurgen/i],
  ['Ethics', /ethic|integrity|probity|moral|values|emotional intelligence/i],
];

function guessSubject(text) {
  for (const [subject, re] of SUBJECT_HINTS) {
    if (re.test(text)) return subject;
  }
  return 'General';
}

// ─────────────────────────────────────────────────────────────────────────────
// Ingest
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Ingest a question paper that is already on disk (uploaded through `inbox/`).
 *
 * Prefers the PDF's own text layer, which most coaching compilations and
 * digitally-produced papers have — question numbers survive intact there, so
 * parsing is far more complete than on UPSC's own scans. Falls back to OCR.
 *
 * @param {string} file  Path to the PDF.
 * @param {{exam?:string, year:number, paper?:string, url?:string}} meta
 */
export async function ingestPaperFile(file, meta, { dryRun = false, maxPages = 60, json = null } = {}) {
  const { default: pdfParse } = await import('pdf-parse/lib/pdf-parse.js');
  const buffer = fs.readFileSync(file);
  const parsed = await pdfParse(buffer);
  const pages = parsed.numpages || 1;
  const alnumPerPage = (parsed.text || '').replace(/[^A-Za-z0-9]/g, '').length / pages;

  let text = parsed.text || '';
  if (alnumPerPage < 400) {
    if (!ocrAvailable()) {
      throw new Error('Scanned paper and no OCR tools available (need poppler-utils + tesseract-ocr).');
    }
    console.log(`        no usable text layer (~${Math.round(alnumPerPage)} chars/page) — running OCR…`);
    const lang = hasLanguage('hin') ? 'eng+hin' : 'eng';
    text = ocrPdf(file, { maxPages, lang });
  } else {
    console.log(`        using embedded text layer (~${Math.round(alnumPerPage)} chars/page)`);
  }

  const exam = meta.exam || (/prelim|csat/i.test(meta.paper || '') ? 'CSP' : 'CSM');
  const docs = exam === 'CSP'
    ? parsePrelimsPaper(text, { year: meta.year, paper: meta.paper || 'Prelims GS-I', url: meta.url || '' })
    : parseMainsPaper(text, { year: meta.year, paper: meta.paper || 'Mains', url: meta.url || '' });

  console.log(`        parsed ${docs.length} question(s)`);

  if (json) {
    fs.writeFileSync(json, JSON.stringify(docs, null, 2), 'utf-8');
    return { parsed: docs.length, stats: { uploaded: 0, skipped: 0, errors: 0 } };
  }

  const stats = await uploadPyqs(docs, dryRun);
  return { parsed: docs.length, stats };
}

async function downloadPdf(url) {
  const res = await fetch(url, { headers: { 'User-Agent': UA } });
  if (!res.ok) throw new Error(`Download failed: HTTP ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'upsc-qp-')), 'paper.pdf');
  fs.writeFileSync(file, buf);
  return { file, bytes: buf.length };
}

/**
 * Download, OCR and ingest one paper.
 * @returns {Promise<{parsed:number, stats:object}>}
 */
export async function ingestPaper(meta, { dryRun = false, maxPages = 60, json = null } = {}) {
  const label = `${meta.exam} ${meta.year} ${meta.paper}`;
  console.log(`\n[Paper] ${label}`);
  console.log(`        ${meta.url}`);

  if (!ocrAvailable()) {
    throw new Error(
      'OCR tools unavailable. UPSC papers are image-only scans; install poppler-utils and tesseract-ocr.',
    );
  }

  const { file, bytes } = await downloadPdf(meta.url);
  console.log(`        downloaded ${(bytes / 1048576).toFixed(1)} MB — running OCR (this takes a few minutes)…`);

  // Recognising the Hindi half AS Hindi is what makes these papers parseable:
  // in English-only mode Tesseract transliterates Devanagari into Latin gibberish
  // that no filter can separate from real question text. With the Hindi pack
  // loaded it comes back as Devanagari and is stripped by codepoint.
  const lang = hasLanguage('hin') ? 'eng+hin' : 'eng';
  if (lang === 'eng') {
    console.warn('        [warn] Hindi language pack missing — bilingual pages will parse poorly. Install tesseract-ocr-hin.');
  }

  let text;
  try {
    text = ocrPdf(file, { maxPages, lang });
  } finally {
    try { fs.rmSync(path.dirname(file), { recursive: true, force: true }); } catch { /* best effort */ }
  }
  console.log(`        OCR produced ${text.length} chars`);

  const docs = meta.exam === 'CSP'
    ? parsePrelimsPaper(text, meta)
    : parseMainsPaper(text, meta);

  console.log(`        parsed ${docs.length} question(s)`);

  if (json) {
    fs.writeFileSync(json, JSON.stringify(docs, null, 2), 'utf-8');
    console.log(`        wrote ${json}`);
    return { parsed: docs.length, stats: { uploaded: 0, skipped: 0, errors: 0 } };
  }

  const stats = await uploadPyqs(docs, dryRun);
  console.log(`        uploaded +${stats.uploaded}, existing ${stats.skipped}, errors ${stats.errors}`);
  return { parsed: docs.length, stats };
}

// ─────────────────────────────────────────────────────────────────────────────
// CLI
// ─────────────────────────────────────────────────────────────────────────────

function parseArgs() {
  const args = process.argv.slice(2);
  const o = { list: false, exam: 'CSP', year: null, latest: 0, url: null, dryRun: false, json: null, maxPages: 60, includeOptional: false };
  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--list': o.list = true; break;
      case '--include-optional': o.includeOptional = true; break;
      case '--exam': o.exam = (args[++i] || 'CSP').toUpperCase(); break;
      case '--year': o.year = parseInt(args[++i], 10) || null; break;
      case '--latest': o.latest = parseInt(args[++i], 10) || 1; break;
      case '--url': o.url = args[++i] || null; break;
      case '--dry-run': o.dryRun = true; break;
      case '--json': o.json = args[++i] || null; break;
      case '--max-pages': o.maxPages = parseInt(args[++i], 10) || 60; break;
    }
  }
  return o;
}

async function main() {
  const o = parseArgs();

  if (o.list) {
    const all = await listPapers();
    const papers = o.includeOptional ? all : all.filter((p) => p.paper !== 'Optional');
    console.log(`\n${papers.length} Civil Services GS/Essay paper(s) published on upsc.gov.in`
      + `${o.includeOptional ? '' : ` (${all.length - papers.length} optional-subject papers hidden; --include-optional to show)`}:\n`);
    for (const p of papers) {
      console.log(`  ${p.exam}  ${p.year}  ${p.paper.padEnd(22)}  ${p.url.split('/').pop()}`);
    }
    return;
  }

  let targets = [];
  if (o.url) {
    targets = [{ ...(classifyPaper(o.url) || {}), url: o.url, year: o.year || 0, exam: o.exam, paper: o.exam === 'CSP' ? 'Prelims GS-I' : 'Mains' }];
    if (!targets[0].year) throw new Error('Pass --year with --url');
  } else {
    const all = await listPapers();
    targets = all.filter((p) => p.exam === o.exam);
    if (!o.includeOptional) targets = targets.filter((p) => p.paper !== 'Optional');
    if (o.year) targets = targets.filter((p) => p.year === o.year);
    if (o.latest) targets = targets.slice(0, o.latest);
  }

  if (targets.length === 0) {
    console.log('No matching papers. Run with --list to see what is available.');
    return;
  }

  if (!o.dryRun && !o.json) initFirebase();

  let parsed = 0;
  let uploaded = 0;
  for (const t of targets) {
    try {
      const r = await ingestPaper(t, { dryRun: o.dryRun, json: o.json, maxPages: o.maxPages });
      parsed += r.parsed;
      uploaded += r.stats.uploaded;
    } catch (e) {
      console.error(`  [err] ${t.url}: ${e.message}`);
    }
  }

  console.log(`\nDone: parsed ${parsed} question(s), uploaded ${uploaded}.`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  main().catch((e) => {
    console.error('Fatal error:', e.message);
    process.exit(1);
  });
}
