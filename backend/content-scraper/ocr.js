/**
 * OCR fallback for scanned / image-only newspaper PDFs.
 *
 * Many newspaper e-paper PDFs carry no text layer at all — `pdf-parse` returns
 * a handful of characters and article extraction silently produces nothing.
 * This module rasterises those pages with poppler's `pdftoppm` and runs
 * Tesseract over them.
 *
 * Both tools are free and are installed by the GitHub Actions workflow with
 * `apt-get install -y poppler-utils tesseract-ocr`. When they are missing the
 * module degrades gracefully: [ocrAvailable] returns false and the caller keeps
 * whatever text layer the PDF had.
 */

import { execFileSync, spawnSync } from 'child_process';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
// backend/content-scraper → backend
const BACKEND = path.resolve(HERE, '..');

/**
 * Windows installs poppler/tesseract in well-known places; check those too.
 * Resolved against this module's own location rather than the working
 * directory, so it works whichever folder the script is launched from.
 */
const EXTRA_DIRS = [
  'C:/Program Files/Tesseract-OCR',
  'C:/Program Files (x86)/Tesseract-OCR',
  path.join(os.homedir(), 'AppData', 'Local', 'Programs', 'Tesseract-OCR'),
  'C:/poppler/Library/bin',
  // Poppler is vendored in the repo for Windows runs.
  path.join(BACKEND, 'poppler', 'poppler-24.08.0', 'Library', 'bin'),
  path.join(BACKEND, 'poppler', 'bin'),
];

function resolveBinary(name) {
  const exe = process.platform === 'win32' ? `${name}.exe` : name;

  // On PATH?
  const probe = spawnSync(exe, ['--version'], { stdio: 'ignore' });
  if (!probe.error) return exe;

  for (const dir of EXTRA_DIRS) {
    const full = path.join(dir, exe);
    if (fs.existsSync(full)) return full;
  }
  return null;
}

let _cache = null;

/** Resolve both binaries once. Returns `{ pdftoppm, tesseract }` or null. */
export function ocrTools() {
  if (_cache !== null) return _cache;
  const pdftoppm = resolveBinary('pdftoppm');
  const tesseract = resolveBinary('tesseract');
  _cache = pdftoppm && tesseract ? { pdftoppm, tesseract } : null;
  return _cache;
}

export function ocrAvailable() {
  return ocrTools() !== null;
}

/**
 * Rasterise and OCR a PDF.
 *
 * @param {string} file       Path to the PDF.
 * @param {object} [opts]
 * @param {number} [opts.maxPages=12]  Cap pages so a 40-page e-paper cannot
 *                                     blow the CI time budget.
 * @param {number} [opts.dpi=300]      300 dpi is the accuracy/speed sweet spot
 *                                     for newsprint.
 * @param {string} [opts.lang='eng']
 * @returns {string} Extracted text, page blocks separated by blank lines.
 */
export function ocrPdf(file, { maxPages = 12, dpi = 300, lang = 'eng', batchSize = 6 } = {}) {
  const tools = ocrTools();
  if (!tools) throw new Error('OCR tools not available (need poppler-utils and tesseract-ocr)');

  const workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'upsc-ocr-'));

  try {
    const pages = [];

    // Rasterise in batches rather than in one call.
    //
    // A 48-page, 34 MB scan takes well over ten minutes to convert in a single
    // pdftoppm invocation, which is how a whole UPSC paper was lost to
    // ETIMEDOUT. Batching bounds each call, keeps peak disk use to a handful of
    // PNGs, and means a late failure still returns the pages already read.
    for (let start = 1; start <= maxPages; start += batchSize) {
      const end = Math.min(start + batchSize - 1, maxPages);
      const prefix = path.join(workDir, `b${start}`);

      try {
        execFileSync(
          tools.pdftoppm,
          ['-r', String(dpi), '-png', '-f', String(start), '-l', String(end), file, prefix],
          { stdio: 'ignore', timeout: 5 * 60 * 1000 },
        );
      } catch (e) {
        // Past the last page poppler simply produces nothing; anything else is
        // worth surfacing but must not discard the pages already collected.
        if (pages.length === 0) throw e;
        break;
      }

      const images = fs
        .readdirSync(workDir)
        .filter((f) => f.startsWith(`b${start}-`) && f.endsWith('.png'))
        .sort();

      if (images.length === 0) break; // ran past the end of the document

      for (const img of images) {
        const full = path.join(workDir, img);
        pages.push(ocrImage(full, { lang }));
        try { fs.rmSync(full, { force: true }); } catch { /* best effort */ }
      }
    }

    return pages.filter(Boolean).join('\n\n');
  } finally {
    try {
      fs.rmSync(workDir, { recursive: true, force: true });
    } catch { /* best effort */ }
  }
}

/** Language packs actually present, so `-l eng+hin` cannot fail on a bare box. */
export function hasLanguage(code) {
  const tools = ocrTools();
  if (!tools) return false;
  const out = spawnSync(tools.tesseract, ['--list-langs'], { encoding: 'utf-8' });
  if (out.error || out.status !== 0) return false;
  return (out.stdout || '').split(/\r?\n/).map((l) => l.trim()).includes(code);
}

/** OCR a single image file (also used for directly-uploaded page photos). */
export function ocrImage(file, { lang = 'eng' } = {}) {
  const tools = ocrTools();
  if (!tools) throw new Error('OCR tools not available');

  // --psm 3 = fully automatic page segmentation, which handles the multi-column
  // newspaper layout far better than the single-block default.
  const out = spawnSync(
    tools.tesseract,
    [file, 'stdout', '-l', lang, '--psm', '3', '--oem', '1'],
    { encoding: 'utf-8', maxBuffer: 64 * 1024 * 1024, timeout: 5 * 60 * 1000 },
  );

  if (out.error || out.status !== 0) return '';
  return (out.stdout || '').trim();
}
