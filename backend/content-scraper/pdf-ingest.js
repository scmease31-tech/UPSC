#!/usr/bin/env node
/**
 * PDF Content Ingest
 *
 * Extracts text from a PDF **locally** and uploads structured study content to
 * Firestore. The PDF text is never printed in full — only summary counts — so
 * this is safe to run on large newspaper PDFs.
 *
 * Supported types:
 *   --type vocabulary   Daily vocabulary PDFs  → `vocabulary` collection
 *   --type newspaper    Full newspaper (IE/TH) → `articles` (+ derived content)
 *   --type editorial    Editorial compilations → `articles` (+ derived content)
 *
 * Usage:
 *   node pdf-ingest.js "path/to/Daily Vocabulary 13-07-2026.pdf" --type vocabulary
 *   node pdf-ingest.js "path/to/IE Delhi 13-07-2026.pdf" --type newspaper --source "Indian Express"
 *   node pdf-ingest.js "path/to/editorials.pdf" --type editorial --dry-run
 *
 * Credentials: set FIREBASE_SERVICE_ACCOUNT_B64 or GOOGLE_APPLICATION_CREDENTIALS
 * (path to the Firebase Admin service-account JSON).
 */

import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { pathToFileURL } from 'url';
// Import the library file directly to skip pdf-parse's debug wrapper, which
// otherwise tries to read a bundled test PDF and crashes under ESM.
import pdfParse from 'pdf-parse/lib/pdf-parse.js';

import {
  initFirebase,
  uploadArticles,
  uploadVocabulary,
  uploadFlashcards,
  uploadSchemes,
} from './uploader.js';
import { generateAll, generateSchemes } from './generators.js';

// ─────────────────────────────────────────────────────────────────────────────
// Args
// ─────────────────────────────────────────────────────────────────────────────

function parseArgs() {
  const args = process.argv.slice(2);
  const opts = { file: null, type: 'vocabulary', source: null, date: null, dryRun: false, dump: null, json: null, articles: false };

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--type': opts.type = (args[++i] || '').toLowerCase(); break;
      case '--source': opts.source = args[++i] || null; break;
      case '--date': opts.date = args[++i] || null; break;
      case '--dry-run': opts.dryRun = true; break;
      case '--dump': opts.dump = args[++i] || null; break;
      case '--json': opts.json = args[++i] || null; break;
      case '--articles': opts.articles = true; break;
      default: if (!args[i].startsWith('--')) opts.file = args[i];
    }
  }
  return opts;
}

/** Pull a YYYY-MM-DD date out of a filename like "IE Delhi 13~07~2026.pdf". */
function dateFromName(name) {
  const m = name.match(/(\d{1,2})[-~._ /](\d{1,2})[-~._ /](\d{2,4})/);
  if (m) {
    const d = m[1].padStart(2, '0');
    const mo = m[2].padStart(2, '0');
    let y = m[3];
    if (y.length === 2) y = `20${y}`;
    return `${y}-${mo}-${d}`;
  }
  return null;
}

function todayIST() {
  const now = new Date(Date.now() + 5.5 * 60 * 60 * 1000);
  return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}-${String(now.getUTCDate()).padStart(2, '0')}`;
}

function clean(s) {
  return (s || '').replace(/\u00a0/g, ' ').replace(/[ \t]+/g, ' ').trim();
}

/** Fix common PDF text artifacts: ligatures, smart quotes, replacement chars. */
function normalizeText(t) {
  return String(t || '')
    .replace(/\uFB00/g, 'ff').replace(/\uFB01/g, 'fi').replace(/\uFB02/g, 'fl')
    .replace(/\uFB03/g, 'ffi').replace(/\uFB04/g, 'ffl')
    .replace(/[\u2018\u2019\u02BC]/g, "'")
    .replace(/[\u201C\u201D]/g, '"')
    .replace(/[\u2013\u2014]/g, '-')
    .replace(/\u2026/g, '...')
    .replace(/\uFFFD/g, '')
    .replace(/\u00a0/g, ' ');
}

function hashId(prefix, ...parts) {
  return `${prefix}_${crypto.createHash('md5').update(parts.join('|').toLowerCase()).digest('hex').slice(0, 16)}`;
}

// ─────────────────────────────────────────────────────────────────────────────
// Vocabulary parser
// ─────────────────────────────────────────────────────────────────────────────

const POS = /(noun|verb|adjective|adverb|pronoun|preposition|conjunction|phrase|idiom)/i;
const DEVANAGARI = /[\u0900-\u097F]/;

function stripBullet(s) {
  return clean(String(s).replace(/^[\u25cf\u2022\u2605\u25aa\u25e6*\-\s]+/, ''));
}

/**
 * Entry point: try the structured "Daily Vocabulary" (The Hindu / Telegram)
 * layout first; fall back to a generic line parser for other formats.
 */
function parseVocabulary(text, dateStr) {
  const structured = parseHinduVocab(text, dateStr);
  if (structured.length >= 3) return structured;
  return parseGenericVocab(text, dateStr);
}

/**
 * Parse the "Daily Vocabulary" PDF format. After pdf-parse flattens the
 * multi-column layout, each main word looks like:
 *
 *   <n> Word (pronunciation)
 *   ★Meaning: <meaning, may wrap>
 *   ANTONYMS
 *   ●<antonym> ...            (short bullets)
 *   ●<example sentence ...>   (long bullet, may wrap over plain lines)
 *   EXAMPLE
 *   (<hindi translation>)
 *   ●<synonym> ...            (short bullets)
 *
 * Also parses the trailing One-word Substitute / Phrasal Verb / Idiom sections.
 */
function parseHinduVocab(text, dateStr) {
  let lines = text.split(/\r?\n/).map((l) => clean(l.replace(/\u00a0/g, ' ')));

  // Drop the promotional footer (Telegram channel link etc.) so it can't leak
  // into the last entry's meaning.
  const footerIdx = lines.findIndex((l) =>
    /test your vocabulary|join this channel|https?:\/\/t\.me|carefully chosen words from the hindu/i.test(l)
  );
  if (footerIdx > 0) lines = lines.slice(0, footerIdx);

  const lower = lines.map((l) => l.toLowerCase());
  const out = [];

  const oneWordIdx = lower.findIndex((l) => l.includes('one-word substitute') || l.includes('one word substitute'));
  const phrasalIdx = lower.findIndex((l) => l.includes('phrasal verb'));
  const idiomIdx = lower.findIndex((l) => l.includes('idiom'));
  const firstSection = [oneWordIdx, phrasalIdx, idiomIdx].filter((i) => i >= 0).sort((a, b) => a - b)[0];
  const mainEnd = firstSection === undefined ? lines.length : firstSection;

  // ── Main words (with ★Meaning) ──────────────────────────────────────────
  const anchor = /^(\d+)\s+([A-Za-z][A-Za-z'’\-]+)\s*\(([^)]+)\)\s*$/;
  const anchorIdxs = [];
  for (let i = 0; i < mainEnd; i++) if (anchor.test(lines[i])) anchorIdxs.push(i);

  for (let a = 0; a < anchorIdxs.length; a++) {
    const start = anchorIdxs[a];
    const end = a + 1 < anchorIdxs.length ? anchorIdxs[a + 1] : mainEnd;
    const word = clean(lines[start].match(anchor)[2]);
    const blob = lines.slice(start + 1, end);

    let meaning = '';
    let example = '';
    const antonyms = [];
    const synonyms = [];
    let state = 'meaning';
    let inMeaning = false;

    for (const line of blob) {
      if (!line) continue;
      const up = line.toUpperCase();

      const meanM = line.match(/★?\s*Meaning\s*[:：]\s*(.*)$/i);
      if (meanM) { meaning = clean(meanM[1]); inMeaning = true; continue; }

      if (up === 'ANTONYMS' || up === 'ANTONYM') { state = 'ant'; inMeaning = false; continue; }
      if (up === 'SYNONYMS' || up === 'SYNONYM' || up === 'EXAMPLE') { state = 'syn'; inMeaning = false; continue; }

      const isBullet = /^[\u25cf\u2022\u25aa\u25e6]/.test(line);
      if (isBullet) {
        inMeaning = false;
        const val = stripBullet(line);
        if (!val || DEVANAGARI.test(val)) continue;
        if (state === 'ant') {
          // Antonyms are 1-3 words; a 4+ word bullet is the start of the example sentence.
          if (val.split(/\s+/).length >= 4) { example = val; state = 'exampleWrap'; }
          else antonyms.push(val);
        } else if (state === 'syn') {
          synonyms.push(val);
        } else if (state === 'exampleWrap') {
          synonyms.push(val);
        }
        continue;
      }

      if (DEVANAGARI.test(line)) { inMeaning = false; continue; }
      if (inMeaning) { meaning = clean(meaning + ' ' + line); continue; }
      if (state === 'exampleWrap') { example = clean(example + ' ' + line); continue; }
    }

    meaning = clean(meaning.replace(/^[:：\-\s]+/, ''));
    if (word && meaning.length >= 8) {
      out.push({
        id: hashId('v', word),
        word,
        partOfSpeech: word.includes(' ') ? 'phrase' : 'noun',
        meaning,
        example,
        synonyms: synonyms.slice(0, 6),
        antonyms: antonyms.slice(0, 6),
        category: 'Vocabulary',
        upscUsage: `Advanced word from The Hindu vocabulary (${dateStr}) — useful for Essay & answer writing.`,
      });
    }
  }

  // ── Term : definition sections ──────────────────────────────────────────
  const sectionEnd = (startIdx) =>
    [oneWordIdx, phrasalIdx, idiomIdx, lines.length]
      .filter((i) => i > startIdx)
      .sort((a, b) => a - b)[0];

  if (oneWordIdx >= 0) parseTermDefSection(lines.slice(oneWordIdx + 1, sectionEnd(oneWordIdx)), 'One-word Substitute', dateStr, out);
  if (phrasalIdx >= 0) parseTermDefSection(lines.slice(phrasalIdx + 1, sectionEnd(phrasalIdx)), 'Phrasal Verb', dateStr, out);
  if (idiomIdx >= 0) parseTermDefSection(lines.slice(idiomIdx + 1, sectionEnd(idiomIdx)), 'Idiom', dateStr, out);

  // De-dupe by word.
  const byWord = new Map();
  for (const e of out) {
    const k = e.word.toLowerCase();
    if (e.word && !byWord.has(k)) byWord.set(k, e);
  }
  return [...byWord.values()];
}

/**
 * Parse a "N Term: meaning" / "N Term – meaning" section (one-word
 * substitutes, phrasal verbs, idioms) with optional "Example:" follow-ups.
 */
function parseTermDefSection(lines, category, dateStr, out) {
  // Colon, or a dash surrounded by spaces (so "White-collar" is not split).
  const entryRe = /^(\d+)\s+(.+?)\s*(?:[:：]|\s[–—-]\s)\s*(.+)$/;
  // Same, but the definition continues on the next line (label ends with ":").
  const headerOnlyRe = /^(\d+)\s+(.+?)\s*[:：]\s*$/;
  const pos = category === 'Phrasal Verb' ? 'phrasal verb' : category === 'Idiom' ? 'idiom' : 'phrase';
  let cur = null;

  const newEntry = (word, meaning) => ({
    id: hashId('v', word),
    word: clean(word).replace(/\s*\([^)]*\)\s*$/, ''),
    partOfSpeech: pos,
    meaning: clean(meaning),
    example: '',
    synonyms: [],
    antonyms: [],
    category,
    upscUsage: `${category} from daily vocabulary (${dateStr}).`,
    _inExample: false,
  });

  const flush = () => {
    if (cur && cur.word && cur.meaning && cur.meaning.length >= 5) {
      delete cur._inExample;
      cur.meaning = cur.meaning.slice(0, 400);
      cur.example = cur.example.slice(0, 400);
      out.push(cur);
    }
    cur = null;
  };

  for (const raw of lines) {
    const line = clean(raw);
    if (!line) continue;

    const exM = line.match(/^Example\s*[:：]\s*(.+)$/i);
    if (exM) {
      if (cur) { cur.example = clean((cur.example ? cur.example + ' ' : '') + exM[1]); cur._inExample = true; }
      continue;
    }

    const m = line.match(entryRe);
    if (m) {
      flush();
      cur = newEntry(m[2], m[3]);
      continue;
    }

    const h = line.match(headerOnlyRe);
    if (h) {
      flush();
      cur = newEntry(h[2], ''); // definition arrives on following line(s)
      continue;
    }

    if (cur) {
      if (DEVANAGARI.test(line) || /^[A-Z]{2,}$/.test(line)) continue; // skip Hindi + ALL-CAPS group headers
      if (cur._inExample) cur.example = clean(cur.example + ' ' + line);
      else cur.meaning = clean((cur.meaning ? cur.meaning + ' ' : '') + line);
    }
  }
  flush();
}

/**
 * Generic fallback parser for other vocabulary layouts:
 *   "1. Word (noun) : meaning"   "Word - meaning"   "Word : meaning"
 */
function parseGenericVocab(text, dateStr) {
  const lines = text.split(/\r?\n/).map(clean).filter(Boolean);
  const entries = [];
  let current = null;

  const headword = /^(?:\d+[.)]\s*)?([A-Za-z][A-Za-z'’\- ]{1,34}?)\s*(?:\(([^)]*)\))?\s*[:\-–—]\s*(.+)$/;

  const flush = () => {
    if (current && current.word && current.meaning && current.meaning.length >= 8) {
      entries.push(current);
    }
    current = null;
  };

  for (const line of lines) {
    const syn = line.match(/^synonyms?\s*[:\-]\s*(.+)$/i);
    const ant = line.match(/^antonyms?\s*[:\-]\s*(.+)$/i);
    const ex = line.match(/^(?:example|sentence|usage)\s*[:\-]\s*(.+)$/i);
    const mean = line.match(/^meaning\s*[:\-]\s*(.+)$/i);

    if (current && syn) { current.synonyms = splitList(syn[1]); continue; }
    if (current && ant) { current.antonyms = splitList(ant[1]); continue; }
    if (current && ex) { current.example = clean(ex[1]); continue; }
    if (current && mean && !current.meaning) { current.meaning = clean(mean[1]); continue; }

    const m = line.match(headword);
    if (m) {
      const word = clean(m[1]);
      const posRaw = m[2] || '';
      const rest = clean(m[3]);
      // Reject headers/non-words (all-caps banners, very long "words", etc.)
      if (word.length < 3 || word.split(' ').length > 4 || /^[A-Z ]+$/.test(word) && word.length > 12) {
        continue;
      }
      flush();
      const posMatch = (posRaw + ' ' + rest).match(POS);
      current = {
        id: hashId('v', word),
        word,
        partOfSpeech: posMatch ? posMatch[1].toLowerCase() : (word.includes(' ') ? 'phrase' : 'noun'),
        meaning: rest.replace(POS, '').replace(/^[):\-\s]+/, '').trim() || rest,
        example: '',
        synonyms: [],
        antonyms: [],
        category: 'Vocabulary',
        upscUsage: `Daily vocabulary for essay & answer writing (${dateStr}).`,
      };
    } else if (current && !current.example && line.length > 20 && /[a-z]/.test(line)) {
      // A plain follow-on line becomes the usage example if we don't have one.
      current.example = clean(line);
    }
  }
  flush();

  // De-dupe by word.
  const byWord = new Map();
  for (const e of entries) {
    const k = e.word.toLowerCase();
    if (!byWord.has(k)) byWord.set(k, e);
  }
  return [...byWord.values()];
}

function splitList(s) {
  return clean(s)
    .split(/[,;/]|\band\b/i)
    .map((x) => clean(x).replace(/[.]+$/, ''))
    .filter((x) => x && x.length > 1)
    .slice(0, 8);
}

// ─────────────────────────────────────────────────────────────────────────────
// Article parser (newspapers + editorials)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Best-effort split of raw PDF text into article-like blocks using headline
 * heuristics. Short Title-Case / ALL-CAPS lines with no terminal punctuation
 * act as boundaries; everything until the next boundary is the body.
 */
function parseArticles(text, source, dateStr, minBody) {
  const rawLines = text.split(/\r?\n/).map((l) => l.replace(/\u00a0/g, ' ').replace(/[ \t]+/g, ' ').trimEnd());
  const blocks = [];
  let title = null;
  let body = [];

  const isHeadline = (l) => {
    const t = l.trim();
    if (t.length < 8 || t.length > 100) return false;
    if (/[.:;,]$/.test(t)) return false;
    const words = t.split(/\s+/);
    if (words.length < 2 || words.length > 14) return false;
    // Mostly capitalised words, or an ALL-CAPS banner.
    const capWords = words.filter((w) => /^[A-Z0-9]/.test(w)).length;
    const allCaps = /^[A-Z0-9 &'’.\-]+$/.test(t) && /[A-Z]{3,}/.test(t);
    return allCaps || capWords / words.length >= 0.6;
  };

  const push = () => {
    const text = clean(body.join(' '));
    if (title && text.length >= minBody) {
      blocks.push({ title: clean(title), body: text });
    }
    title = null;
    body = [];
  };

  for (const line of rawLines) {
    if (isHeadline(line)) {
      push();
      title = line.trim();
    } else if (line.trim()) {
      body.push(line);
    }
  }
  push();

  return blocks.map((b) => {
    const keyPoints = b.body
      .split(/(?<=[.!?])\s+/)
      .filter((s) => s.length > 40 && s.length < 220)
      .slice(0, 6)
      .map(clean);
    return {
      id: hashId('art', b.title, dateStr),
      title: b.title,
      summary: b.body.slice(0, 300).replace(/\s+\S*$/, '') + '…',
      content: b.body.slice(0, 6000),
      keyPoints,
      examRelevance: 'Both',
      categoryTags: ['Current Affairs'],
      imageUrl: '',
      publishedDate: dateStr,
      isTopNews: false,
      shortNotes: keyPoints.slice(0, 5),
      newspaper: source,
      upscPaper: '',
      relatedTopics: [],
      keyTerms: {},
    };
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Ingest a single PDF: extract text, parse by type, and upload to Firestore.
 * Reusable by both the CLI (main) and the daily batch runner. When uploading
 * (dryRun=false), the caller must have called initFirebase() first.
 *
 * @returns {Promise<Object>} Summary of what was parsed/uploaded.
 */
export async function ingestFile({
  file,
  type = 'vocabulary',
  source = null,
  date = null,
  dryRun = false,
  articles = false,
  dump = null,
  json = null,
}) {
  const base = path.basename(file);
  const dateStr = date || dateFromName(base) || todayIST();

  const buffer = fs.readFileSync(file);
  const parsed = await pdfParse(buffer);
  const pages = parsed.numpages || 0;
  const fullText = normalizeText(parsed.text || '');
  const chars = fullText.length;
  console.log(`  [read] ${base}: ${chars} chars, ${pages} page(s), type=${type}, date=${dateStr}`);

  if (dump) {
    fs.writeFileSync(dump, fullText, 'utf-8');
    console.log(`  [dump] wrote raw text to ${dump}`);
    return { file: base, type, dumped: true };
  }

  if (chars < 50) {
    console.warn(`  [warn] ${base}: almost no text (likely scanned images; needs OCR). Skipping.`);
    return { file: base, type, error: 'no-text' };
  }

  if (type === 'vocabulary') {
    const vocab = parseVocabulary(fullText, dateStr);
    console.log(`  [parse] ${vocab.length} vocabulary word(s)`);
    if (json) {
      fs.writeFileSync(json, JSON.stringify(vocab, null, 2), 'utf-8');
      console.log(`  [json] wrote parsed docs to ${json}`);
      return { file: base, type, parsed: vocab.length };
    }
    const s = await uploadVocabulary(vocab, dryRun);
    console.log(`  [done] vocabulary: +${s.uploaded} added, ${s.skipped} existing, ${s.errors} errors`);
    return { file: base, type, vocabulary: s };
  }

  if (type === 'newspaper' || type === 'editorial') {
    const src = source || (type === 'editorial' ? 'Editorials' : base.replace(/\.pdf$/i, ''));

    // Government schemes are reliably detectable even from multi-column layouts,
    // because scheme names are distinctive proper nouns. Run detection over the
    // whole document as a single pseudo-article.
    const pseudo = [{
      title: src,
      summary: '',
      content: fullText,
      publishedDate: dateStr,
      categoryTags: ['Current Affairs'],
      keyTerms: {},
    }];
    const schemes = generateSchemes(pseudo);
    console.log(`  [parse] ${schemes.length} government scheme(s)`);

    // Article/flashcard reconstruction from these layouts is unreliable
    // (columns get interleaved), so it is opt-in via `articles`.
    let articleDocs = [];
    if (articles) {
      const minBody = type === 'editorial' ? 400 : 250;
      articleDocs = parseArticles(fullText, src, dateStr, minBody);
      console.log(`  [parse] ${articleDocs.length} article block(s) [articles opt-in]`);
    }

    if (json) {
      fs.writeFileSync(json, JSON.stringify({ schemes, articles: articleDocs }, null, 2), 'utf-8');
      console.log(`  [json] wrote parsed docs to ${json}`);
      return { file: base, type, schemes: schemes.length, articles: articleDocs.length };
    }

    const sStats = await uploadSchemes(schemes, dryRun);
    let aStats = { uploaded: 0, skipped: 0, errors: 0 };
    let fStats = { uploaded: 0, skipped: 0, errors: 0 };
    if (articles && articleDocs.length) {
      aStats = await uploadArticles(articleDocs, dryRun);
      const derived = generateAll(articleDocs);
      fStats = await uploadFlashcards(derived.flashcards, dryRun);
    }
    console.log(`  [done] schemes: +${sStats.uploaded} added, ${sStats.skipped} existing, ${sStats.errors} errors`);
    return { file: base, type, schemes: sStats, articles: aStats, flashcards: fStats };
  }

  throw new Error(`Unknown type "${type}". Use vocabulary | newspaper | editorial.`);
}

async function main() {
  const opts = parseArgs();

  if (!opts.file) {
    console.log(`
Usage: node pdf-ingest.js <file.pdf> --type <vocabulary|newspaper|editorial> [options]

Options:
  --type      vocabulary | newspaper | editorial   (default: vocabulary)
  --source    Source label (e.g. "The Hindu")      (newspaper/editorial)
  --date      YYYY-MM-DD                            (default: from filename or today)
  --dry-run   Parse only; do not upload
  --articles  (newspaper/editorial) also extract article fragments (best-effort)
  --json PATH Write parsed docs to a JSON file instead of uploading (no creds)

Tip: to upload all of today's PDFs at once, use daily-ingest.js instead.
`);
    process.exit(1);
  }

  if (!fs.existsSync(opts.file)) {
    console.error(`File not found: ${opts.file}`);
    process.exit(1);
  }

  if (!opts.dryRun && !opts.json && !opts.dump) initFirebase();

  try {
    await ingestFile(opts);
  } catch (e) {
    console.error('Fatal error:', e.message);
    process.exit(1);
  }
}

// Run the CLI only when this file is executed directly, not when imported.
if (import.meta.url === pathToFileURL(process.argv[1] || '').href) {
  main();
}
