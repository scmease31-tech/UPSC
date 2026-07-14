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
  deleteBySourceDate,
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

// Many newspaper/editorial PDFs DROP the f-ligatures (ff, fi, fl, ffi, ffl)
// entirely during text extraction — e.g. "inflation" -> "ination",
// "first" -> "rst", "official" -> "ocial", "affirmation" -> "armation".
// We repair this by starting from a list of REAL words that contain those
// clusters, computing the broken form each collapses to, and mapping it back.
// This is safe: we only replace a whole token that exactly equals a known
// broken form. Broken forms shorter than 3 chars, forms that are real English
// words (see LIG_BLOCK), and ambiguous forms (two words collapse to the same
// thing) are all excluded, so real text can never be corrupted.
const LIG_WORDS = [
  // ── fl / infl- / refl- / confl- / -flu- ─────────────────────────────────
  'inflation','inflationary','deflation','reflation','inflection','inflected',
  'reflect','reflects','reflected','reflecting','reflection','reflections',
  'conflict','conflicts','conflicting','flaws','flagged','flagging','unflagging',
  'flexible','flexibility','inflexible','fleet','fleets','flourish','flourished','flourishing',
  'flooding','flooded','floods','inflow','outflow','overflow','overflowing',
  'fluid','fluids','fluent','fluently','fluency','affluent',
  'influence','influences','influenced','influential','influx','flux','reflux',
  // ── fi / fig / fin / fir / fis / fix / -fic- / -fied / -fication ─────────
  'first','firsthand','fifth','fifteen','fifteenth','fifty','fifties',
  'field','fields','battlefield','midfield','figure','figures','figured','figuring','figment',
  'fight','fights','fighting','fighter','fighters',
  'final','finals','finally','finalize','finalized','finalised','finalising',
  'finding','findings','finish','finished','finishing','finishes','unfinished',
  'finger','fingers','fingerprint','fiction','fictional','nonfiction','fiscal','fiscally',
  'fibre','fibres','fiber','fierce','fiercely','fiery','filter','filters','filtered','filtration',
  'finite','infinite','infinity','definite','definitely','definition','definitions','indefinite','indefinitely',
  'defiance','defiant','defiantly','fixed','fixes','fixing','fixture','fixtures',
  'financial','financially','finance','finances','financed','financing','refinance',
  'confident','confidence','confidential','confidentiality','confidently',
  'deficit','deficits','proficient','proficiency','coefficient','coefficients',
  'certificate','certificates','certification','certified','artificial','artificially',
  'sacrifice','sacrifices','sacrificed','sacrificing','magnificent','magnificence',
  'scientific','scientifically','pacific','terrific','horrific','horrifying','terrified','horrified',
  'unified','unify','unification','testified','testifies','testify','satisfied','dissatisfied','satisfies','gratified',
  'notification','notifications','notified','notify','notifies',
  'classification','classifications','classified','ratification','ratified','ratify',
  'justification','justified','justify','justifies','identification','identified','identify','identifies',
  'qualification','qualifications','qualified','qualify','modification','modifications','modified','modify',
  'verification','verified','verify','verifies','amplification','amplified','amplify',
  'simplification','simplified','simplify','diversified','diversification','intensified','intensify',
  'clarified','clarifies','clarification','clarifications',
  'profit','profits','profitable','profitability','profited','nonprofit',
  // ── ff / a-ff / e-ff / o-ff / su-ff / -ffi- ──────────────────────────────
  'affirmation','affirmations','reaffirmation','affirmative','affair','affairs',
  'affect','affects','affected','affecting','unaffected','affliction','afflicted',
  'afford','affordable','affordability','affiliate','affiliated','affiliation',
  'offer','offers','offered','offering','offerings','offset','offshore','offspring','offside',
  'offence','offense','offensive','suffer','suffered','suffering','suffers','suffice',
  'sufficient','sufficiently','insufficient','buffer','buffers','buffered',
  'differ','differed','differing','different','difference','differences','differently','differentiate',
  'diffuse','diffusion','traffic','scaffold','scaffolding','coffee','proffer',
  'effect','effects','effected','effective','effectively','effectiveness','ineffective','efficacy',
  'effort','efforts','effortless','effortlessly','efficient','efficiency','efficiently','inefficient',
  'office','offices','official','officials','officially','officer','officers','unofficial',
  'difficult','difficulty','difficulties',
  'confirm','confirms','confirmed','confirming','confirmation',
  'significant','significantly','significance','insignificant',
  'specific','specifically','specifics','specification','specifications',
  'benefit','benefits','benefited','benefiting','beneficial','beneficiary','beneficiaries',
  'staffer','staffers','rifle','rifles','prefix','suffix','suffixes',
  // ── extra high-frequency news / legal / economy words ────────────────────
  'ceasefire','gunfire','wildfire','backfire','crossfire','bonfire','misfire',
  'unfit','fitness','outfit','outfits','fitted','fitting',
  'confine','confinement','define','defined','defines','defining','definable',
  'refine','refined','refinery','refineries','refining',
  'reshuffle','reshuffled','reshuffles','shuffle','shuffled',
  'affidavit','affidavits','plaintiff','plaintiffs','sheriff',
];
// Real English words a broken form could collide with — never map these back.
const LIG_BLOCK = new Set([
  'arm','arms','armed','arming','re','ame','ag','ags','our','ours','at','ash','are','ares',
  'led','it','its','in','ins','ne','le','les','sh','ed','ow','ows','oat','ort','ore',
  'prole','proles','rearm','utter','tracking','lament','owing','owed','seminal','seminals',
]);
// Build brokenForm -> correctWord, skipping short/blocked/ambiguous forms.
const _LIG_MAP = (() => {
  const map = new Map();
  const ambiguous = new Set();
  for (const w of LIG_WORDS) {
    const broken = w.replace(/ffl|ffi|ff|fi|fl/g, '');
    if (broken === w || broken.length < 3 || LIG_BLOCK.has(broken)) continue;
    if (map.has(broken) && map.get(broken) !== w) { ambiguous.add(broken); continue; }
    map.set(broken, w);
  }
  for (const a of ambiguous) map.delete(a);
  return map;
})();

/** Restore the original word's casing (all-caps, Title, or lower) onto a fix. */
function applyCase(fix, sample) {
  if (sample.length > 1 && sample === sample.toUpperCase()) return fix.toUpperCase();
  if (/^[A-Z]/.test(sample)) return fix[0].toUpperCase() + fix.slice(1);
  return fix;
}

function repairDroppedLigatures(text) {
  return String(text).replace(/\b([A-Za-z]{3,})\b/g, (word) => {
    const fix = _LIG_MAP.get(word.toLowerCase());
    return fix ? applyCase(fix, word) : word;
  });
}

/** Fix common PDF text artifacts: ligatures, smart quotes, replacement chars. */
function normalizeText(t) {
  const normalized = String(t || '')
    // Strip zero-width / soft-hyphen artifacts.
    .replace(/[\u00AD\u200B\u200C\u200D\u2060\uFEFF]/g, '')
    // This font extracts DROPPED f-ligatures (ff/fi/fl/ffi/ffl) as stray C0/C1
    // control bytes sitting mid-word, e.g. "in<0x8f>ation", "a<0x81>rm",
    // "clari<0x8d>ed". Remove them so the word collapses to its dropped form
    // ("ination"), which repairDroppedLigatures then restores ("inflation").
    // Tab/newline/CR are preserved.
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u0080-\u009F]/g, '')
    .replace(/\uFB00/g, 'ff').replace(/\uFB01/g, 'fi').replace(/\uFB02/g, 'fl')
    .replace(/\uFB03/g, 'ffi').replace(/\uFB04/g, 'ffl')
    .replace(/[\u2018\u2019\u02BC]/g, "'")
    .replace(/[\u201C\u201D]/g, '"')
    .replace(/[\u2013\u2014]/g, '-')
    .replace(/\u2026/g, '...')
    .replace(/\uFFFD/g, '')
    .replace(/\u00a0/g, ' ');
  // De-hyphenate line-break splits BEFORE repairing ligatures, so a word split
  // as "Tribu-\nnal" becomes "Tribunal" (not "Tribu"+"nal" -> "Tribufinal").
  return repairDroppedLigatures(deHyphenate(normalized));
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

/** Join words hyphenated across a line break: "determina-\ntion" -> "determination". */
function deHyphenate(text) {
  return String(text || '').replace(/([A-Za-z])[-‐]\n([a-z])/g, '$1$2');
}

const NEWS_AGENCY_RE = /^(the hindu bureau|the hindu|special correspondent|staff reporter|staff reporters|press trust of india|agence france-presse|associated press|our bureau|reuters|bloomberg|pti|ani|ians)$/i;

/** A byline is a person's name (e.g. "T.C.A. Sharad Raghavan") or a news agency. */
function looksLikeByline(s) {
  if (NEWS_AGENCY_RE.test(s)) return true;
  if (s.length < 5 || s.length > 32) return false;
  const toks = s.split(/\s+/);
  if (toks.length < 2 || toks.length > 4) return false;
  return toks.every((t) => /^[A-Z][a-z'’.-]+$/.test(t) || /^(?:[A-Z]\.){1,3}$/.test(t));
}

/** A dateline is an ALL-CAPS place (e.g. "NEW DELHI", "WASHINGTON"). */
function looksLikeDateline(s) {
  if (s.length < 3 || s.length > 26) return false;
  if (!/^[A-Z][A-Z .'’-]+$/.test(s)) return false;
  if (/^(CM|YK|IN BRIEF|NEWS|WORLD|SPORT|SPORTS|BUSINESS|EDITORIAL|OPINION|PAGE|FULL|CONTINUED|CITY|AND|THE)/.test(s)) return false;
  return true;
}

/** Masthead / navigation / boilerplate lines to drop. */
function isNewspaperBoilerplate(l) {
  if (!l) return true;
  if (l === '»') return true;
  if (/^»?\s*PAGE\s*\d+/i.test(l)) return true;
  if (/(CONTINUED ON|FULL REPORT ON|www\.|to subscribe|missed call|scan QR|city edition|regd\.|RNI No\.|^Vol\.|^No\.\s*\d+|printed at|^\d+\s*Pages|^Chennai$|^Bengaluru$|^Hyderabad$)/i.test(l)) return true;
  if (/^[A-Z]{2,3}$/.test(l)) return true; // print registration marks: CM, YK, AND-NDE
  return false;
}

/**
 * Reject "titles" that are really page furniture: running page IDs, date/city
 * headers, section timetables, e-mail footers, disclaimers, etc.
 */
function isJunkTitle(t) {
  if (!t) return true;
  const s = t.trim();
  if (/^[a-z]/.test(s)) return true;                                     // starts mid-sentence -> fragment, not a headline
  if (/e\d{6,}/i.test(s)) return true;                                   // running page id, e.g. e2145468
  if (/\b\d{1,2}\s+(Mon|Tues|Wednes|Thurs|Fri|Satur|Sun)day\b/i.test(s)) return true;
  if (/\b(Mon|Tues|Wednes|Thurs|Fri|Satur|Sun)day,?\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)/i.test(s)) return true;
  if (/(DISCLAIMER|Readers are requested|City Timings|Classifieds?|Advertisement|Daily page|To subscribe|missed call|scan QR)/i.test(s)) return true;
  if (/[\w.+-]+@[\w.-]+\.[a-z]{2,}/i.test(s)) return true;                // e-mail in title => footer
  if (s.replace(/[^A-Za-z]/g, '').length < 12) return true;              // too few letters for a headline
  if (s.replace(/[^0-9]/g, '').length / s.length > 0.25) return true;    // mostly numbers (timetables/results)
  return false;
}

/**
 * Parse a newspaper/editorial PDF (as flattened by pdf-parse, which preserves
 * a mostly column-correct reading order) into readable article documents.
 * Articles are delimited by the byline→dateline cluster that ends each story.
 * The lead sentence is used as the title (reliable and sensible), and the text
 * is de-hyphenated and reflowed into running paragraphs.
 */
function parseArticles(text, source, dateStr, minBody) {
  // De-hyphenate first (joins "infla-\ntion" -> "ination"), then repair
  // ligatures again so words that were split across a line break are fixed too.
  const lines = repairDroppedLigatures(deHyphenate(text)).split(/\r?\n/).map((l) => clean(l));
  const articles = [];
  let buf = [];

  // Drop ALL-CAPS teaser/section labels ("IN BRIEF", "WORLD", "TRAGIC PARTY").
  const stripLabels = (arr) =>
    arr.filter((l) => !(/^[^a-z]*$/.test(l) && l.replace(/[^A-Za-z]/g, '').length >= 2 && l.length <= 34));

  const emit = (rawBuf) => {
    const lines = stripLabels(rawBuf.map(clean).filter(Boolean));
    if (lines.length === 0) return;

    // Newspapers put the headline AFTER the body in reading order:
    // [body...][headline][subhead][byline]. Peel the trailing headline off.
    let k = lines.length;
    while (k > 0 && (lines[k - 1].length > 78 || /[;,]$/.test(lines[k - 1]))) k--; // skip subhead
    const head = [];
    while (
      k > 0 && head.length < 3 &&
      lines[k - 1].length <= 78 && !/[.!?]["']?$/.test(lines[k - 1]) && /[A-Za-z]/.test(lines[k - 1])
    ) {
      head.unshift(lines[k - 1]); k--;
    }

    const body = clean(lines.slice(0, k).join(' ')) || clean(lines.join(' '));
    if (body.length < minBody) return;

    let title = clean(head.join(' '));
    // Fallback: first substantial sentence of the body.
    if (title.length < 12 || title.length > 130 || /[.]$/.test(title)) {
      const first = body.split(/(?<=[.!?])\s+/).find((s) => s.split(/\s+/).length >= 6 && /[a-z]/.test(s)) || body;
      title = clean(first).slice(0, 110).replace(/\s+\S*$/, '');
    }
    if (title.length < 12 || isJunkTitle(title)) return;

    const sentences = body.split(/(?<=[.!?])\s+/);
    const keyPoints = sentences
      .filter((s) => s.length > 40 && s.length < 220)
      .slice(0, 6)
      .map(clean);
    articles.push({
      id: hashId('art', title, dateStr),
      title,
      summary: body.slice(0, 300).replace(/\s+\S*$/, '') + '…',
      content: body.slice(0, 6000),
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
    });
  };

  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (isNewspaperBoilerplate(l)) continue;

    // A byline immediately (ignoring boilerplate) followed by a dateline marks
    // the end of an article. Everything accumulated is that article's text.
    if (looksLikeByline(l)) {
      let j = i + 1;
      while (j < lines.length && isNewspaperBoilerplate(lines[j])) j++;
      if (j < lines.length && looksLikeDateline(lines[j])) {
        emit(buf);
        buf = [];
        i = j; // consume the dateline too
        continue;
      }
    }
    buf.push(l);
  }
  emit(buf);

  // De-dupe by title.
  const seen = new Set();
  return articles.filter((a) => {
    const k = a.title.toLowerCase();
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
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
      if (articleDocs.length === 0) {
        const alnum = fullText.replace(/[^A-Za-z0-9]/g, '').length;
        const perPage = pages > 0 ? Math.round(alnum / pages) : alnum;
        if (perPage < 1500) {
          console.warn(`  [warn] ${base}: only ~${perPage} readable chars/page — this looks like an image-only/scanned PDF (no real text layer). Article text can't be extracted without OCR.`);
        }
      }
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
      // Replace this source's articles/flashcards for the day, so re-ingesting
      // cleanly overwrites older (e.g. previously-garbled) versions instead of
      // leaving duplicates behind when titles/ids change.
      await deleteBySourceDate('articles', src, dateStr, dryRun);
      aStats = await uploadArticles(articleDocs, dryRun);
      const derived = generateAll(articleDocs);
      await deleteBySourceDate('flashcards', src, dateStr, dryRun);
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
