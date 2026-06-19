// ==========================================
// OCR-based PDF Text Extractor for NCERT Books
// Uses: pdftoppm (render) → Tesseract.js (OCR)
// Handles Type3 custom font PDFs that break standard extractors
// ==========================================
// Usage: 
//   node fix_books.js                    — Process all corrupted books
//   node fix_books.js --only "file.pdf"  — Process specific PDF
//   node fix_books.js --start N          — Start from Nth book
//   node fix_books.js --batch N          — Process N books then exit
//   node fix_books.js --cleanup          — Clean up OK books only
//   node fix_books.js --upload           — Upload to Firebase only
// ==========================================

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const https = require('https');

// Catch unhandled errors to prevent crashes
process.on('uncaughtException', (err) => {
  console.error(`\n  ⚠ Uncaught error: ${err.message.substring(0, 120)}`);
});
process.on('unhandledRejection', (err) => {
  console.error(`\n  ⚠ Unhandled rejection: ${String(err).substring(0, 120)}`);
});

// ── CONFIG ──
const PDFTOPPM = path.join(__dirname, 'poppler', 'poppler-24.08.0', 'Library', 'bin', 'pdftoppm.exe');
const PDFINFO = path.join(__dirname, 'poppler', 'poppler-24.08.0', 'Library', 'bin', 'pdfinfo.exe');
const BOOKS_DIR = path.join(__dirname, '..', 'books');
const TXT_DIR = path.join(BOOKS_DIR, 'extracted_text');
const TEMP_DIR = path.join(__dirname, 'temp_ocr');
const PROGRESS_FILE = path.join(__dirname, 'fix_progress.json');
const FIREBASE_PROJECT_ID = 'upsc-app-e2475';
const FIREBASE_API_KEY = 'AIzaSyDbOuNUCnM5j81IXWd41vOV1lfsjMYwygE';

// OCR settings  
const OCR_DPI = 200;          // Resolution for rendering (200 = good balance of speed/quality)
const PAGES_PER_BATCH = 5;    // Render 5 pages at a time to control memory
const WORKER_RESTART_EVERY = 30; // Restart Tesseract worker every 30 pages to prevent memory leak
const MAX_RETRIES = 2;

// ── CLI args ──
const args = process.argv.slice(2);
let onlyFile = null, startIndex = 0, batchSize = 0, cleanupOnly = false, uploadOnly = false, ocrOnly = false;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--only' && args[i + 1]) onlyFile = args[i + 1];
  if (args[i] === '--start' && args[i + 1]) startIndex = parseInt(args[i + 1]);
  if (args[i] === '--batch' && args[i + 1]) batchSize = parseInt(args[i + 1]);
  if (args[i] === '--cleanup') cleanupOnly = true;
  if (args[i] === '--upload') uploadOnly = true;
  if (args[i] === '--ocr-only') ocrOnly = true;
}

// ── Files that need OCR re-extraction ──
// 37 corrupted (Type3 font) + 3 scanned image PDFs
const CORRUPTED_FILES = [
  // Scanned image PDFs (Old NCERT books - very important for UPSC)
  'MEDIEVAL HISTORY OLD NCERT SATISH CHANDRA (1).pdf',
  'MODERN INDIA BIPAN CHANDRA OLD NCERT.pdf',
  'Ancient-India-RS-Sharma (2).pdf-49.pdf',
  // Type3 font corrupted NCERT books
  'NCERT-Class-10-English-Part-1.pdf',
  'NCERT-Class-10-English-Part-2.pdf',
  'NCERT-Class-10-Geography.pdf',
  'NCERT-Class-10-Political-Science.pdf',
  'NCERT-Class-10-Science.pdf',
  'NCERT-Class-11-Biology.pdf',
  'NCERT-Class-11-Chemistry-Part-1.pdf',
  'NCERT-Class-11-Chemistry-Part-2.pdf',
  'NCERT-Class-11-English-Part-1.pdf',
  'NCERT-Class-11-English-Part-3.pdf',
  'NCERT-Class-11-Geography-Part-1.pdf',
  'NCERT-Class-11-Geography-Part-2.pdf',
  'NCERT-Class-11-History.pdf',
  'NCERT-Class-11-Mathematics.pdf',
  'NCERT-Class-11-Physics-Part-2.pdf',
  'NCERT-Class-12-Chemistry-Part-1.pdf',
  'NCERT-Class-12-Economics-Part-1.pdf',
  'NCERT-Class-12-Economics-Part-2.pdf',
  'NCERT-Class-12-English-Part-1.pdf',
  'NCERT-Class-6-English-Part-2.pdf',
  'NCERT-Class-6-Geography.pdf',
  'NCERT-Class-7-Environment.pdf',
  'NCERT-Class-7-Geography.pdf',
  'NCERT-Class-8-English-Part-1.pdf',
  'NCERT-Class-8-English-Part-2.pdf',
  'NCERT-Class-8-Geography.pdf',
  'NCERT-Class-8-History.pdf',
  'NCERT-Class-8-Mathematics.pdf',
  'NCERT-Class-8-Political-Science.pdf',
  'NCERT-Class-8-Science.pdf',
  'NCERT-Class-9-Economics.pdf',
  'NCERT-Class-9-English-Part-2.pdf',
  'NCERT-Class-9-Geography.pdf',
  'NCERT-Class-9-History.pdf',
  'NCERT-Class-9-Political-Science.pdf',
  'NCERT-Class-9-Science.pdf',
  'NCERT-Class-9-Science-Problems.pdf',
];

// ── Utilities ──
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function slugify(str) { return str.replace(/\.pdf$/i, '').replace(/[^a-zA-Z0-9]+/g, '_').toLowerCase().substring(0, 80); }

function loadProgress() {
  if (fs.existsSync(PROGRESS_FILE)) return JSON.parse(fs.readFileSync(PROGRESS_FILE, 'utf8'));
  return { ocr_extracted: [], cleaned: [], uploaded: [] };
}
function saveProgress(p) { fs.writeFileSync(PROGRESS_FILE, JSON.stringify(p, null, 2)); }

// ── Get PDF page count using pdfinfo ──
function getPdfPageCount(pdfPath) {
  try {
    const output = execSync(`"${PDFINFO}" "${pdfPath}"`, { timeout: 15000, encoding: 'utf8' });
    const match = output.match(/Pages:\s+(\d+)/);
    return match ? parseInt(match[1]) : 0;
  } catch {
    return 0;
  }
}

// ── OCR a single PDF file ──
async function ocrExtractPdf(pdfFileName) {
  const pdfPath = path.join(BOOKS_DIR, pdfFileName);
  const txtName = pdfFileName.replace(/\.pdf$/i, '.txt');
  const txtPath = path.join(TXT_DIR, txtName);
  
  if (!fs.existsSync(pdfPath)) {
    console.log(`  ✗ PDF not found: ${pdfFileName}`);
    return false;
  }
  
  const totalPages = getPdfPageCount(pdfPath);
  if (totalPages === 0) {
    console.log(`  ✗ Could not determine page count for ${pdfFileName}`);
    return false;
  }
  
  console.log(`  📄 ${pdfFileName} — ${totalPages} pages`);
  
  // Clean temp directory
  if (fs.existsSync(TEMP_DIR)) fs.rmSync(TEMP_DIR, { recursive: true });
  fs.mkdirSync(TEMP_DIR, { recursive: true });
  
  let fullText = '';
  const { createWorker } = require('tesseract.js');
  let worker = null;
  let pagesProcessed = 0;
  
  try {
    // Initialize Tesseract worker
    worker = await createWorker('eng');
    
    // Process pages in batches
    for (let batchStart = 1; batchStart <= totalPages; batchStart += PAGES_PER_BATCH) {
      const batchEnd = Math.min(batchStart + PAGES_PER_BATCH - 1, totalPages);
      
      process.stdout.write(`\r    Pages ${batchStart}-${batchEnd}/${totalPages}...`);
      
      // Step 1: Render batch of pages to PNG images
      const prefix = path.join(TEMP_DIR, 'pg');
      try {
        execSync(
          `"${PDFTOPPM}" -f ${batchStart} -l ${batchEnd} -r ${OCR_DPI} -png "${pdfPath}" "${prefix}"`,
          { timeout: 120000, stdio: ['pipe', 'pipe', 'pipe'] }
        );
      } catch (e) {
        console.log(`\n    ⚠ Render failed for pages ${batchStart}-${batchEnd}, skipping`);
        // Clean temp images from failed render
        try { const files = fs.readdirSync(TEMP_DIR).filter(f => f.endsWith('.png')); files.forEach(f => fs.unlinkSync(path.join(TEMP_DIR, f))); } catch {}
        continue;
      }
      
      // Step 2: OCR each image in order
      const images = fs.readdirSync(TEMP_DIR)
        .filter(f => f.startsWith('pg') && f.endsWith('.png'))
        .sort();
      
      for (const img of images) {
        const imgPath = path.join(TEMP_DIR, img);
        try {
          // Verify image file is valid (at least has a header)
          const stat = fs.statSync(imgPath);
          if (stat.size < 100) {
            try { fs.unlinkSync(imgPath); } catch {}
            pagesProcessed++;
            continue;
          }
          const { data } = await worker.recognize(imgPath);
          if (data.text.trim().length > 10) {
            fullText += data.text + '\n\n';
          }
        } catch (e) {
          // Worker may have crashed — recreate it
          console.log(`\n    ⚠ OCR error on ${img}, recreating worker...`);
          try { await worker.terminate(); } catch {}
          worker = null;
          if (global.gc) global.gc();
          await sleep(1000);
          try {
            worker = await createWorker('eng');
          } catch (e2) {
            console.log(`    ✗ Failed to recreate worker: ${e2.message.substring(0, 80)}`);
            throw e2;
          }
        }
        // Remove image immediately to free disk space
        try { fs.unlinkSync(imgPath); } catch {}
        pagesProcessed++;
      }
      
      // Restart worker periodically to prevent memory leak
      if (pagesProcessed >= WORKER_RESTART_EVERY) {
        try { await worker.terminate(); } catch {}
        worker = null;
        if (global.gc) global.gc();
        await sleep(500);
        worker = await createWorker('eng');
        pagesProcessed = 0;
      }
    }
    
    // Terminate worker to free memory
    await worker.terminate();
    worker = null;
    
  } catch (e) {
    console.log(`\n    ✗ OCR error: ${e.message.substring(0, 100)}`);
    if (worker) try { await worker.terminate(); } catch {}
    return false;
  }
  
  // Clean temp
  try { fs.rmSync(TEMP_DIR, { recursive: true }); } catch {}
  
  // Clean up OCR text
  fullText = cleanOcrText(fullText);
  
  if (fullText.trim().length < 500) {
    console.log(`\n    ✗ Too little text extracted (${fullText.length} chars)`);
    return false;
  }
  
  // Write to file
  fs.writeFileSync(txtPath, fullText, 'utf8');
  console.log(`\n    ✓ Saved: ${(fullText.length / 1024).toFixed(0)} KB, ${txtPath.split(path.sep).pop()}`);
  
  return true;
}

// ── Clean OCR artifacts ──
function cleanOcrText(text) {
  let t = text;
  
  // Remove OCR garbage lines (lines with mostly symbols and no real words)
  t = t.split('\n').filter(line => {
    const trimmed = line.trim();
    if (trimmed.length === 0) return true;
    if (trimmed.length < 3) return false;
    // Remove lines that are mostly non-alpha symbols
    const alphaCount = (trimmed.match(/[a-zA-Z]/g) || []).length;
    const ratio = alphaCount / trimmed.length;
    if (ratio < 0.25 && trimmed.length > 5) return false;
    // Remove lines that look like garbled OCR from images
    if (/^[^a-zA-Z]*$/.test(trimmed) && trimmed.length > 3) return false;
    return true;
  }).join('\n');
  
  // Fix common OCR errors
  t = t.replace(/(?<=[a-z])\s*\n\s*(?=[a-z])/g, ' ');  // Join broken lines within sentences
  t = t.replace(/- *\n/g, '');                    // Fix hyphenated line breaks
  t = t.replace(/\n{4,}/g, '\n\n\n');            // Reduce excessive newlines
  
  // Remove OCR noise
  t = t.replace(/^\s*\d{1,3}\s*$/gm, '');       // Bare page numbers
  t = t.replace(/^\s*[|l]{1,3}\s*$/gm, '');     // Stray vertical lines
  
  // Clean encoding issues
  t = t.replace(/â€™/g, "'");
  t = t.replace(/â€˜/g, "'");
  t = t.replace(/â€œ/g, '"');
  t = t.replace(/â€\u009d/g, '"');
  t = t.replace(/â€"/g, '—');
  t = t.replace(/â€"/g, '–');
  t = t.replace(/Â/g, '');
  
  // Strip noise patterns
  const noisePatterns = [
    /Rationalised\s+\d{4}[-–]\d{2,4}/gi,
    /©\s*National Council[^\n]*/gi,
    /ALL RIGHTS RESERVED[^\n]*/gi,
    /ISBN\s+[\d\-]+/gi,
    /Printed on \d+ GSM[^\n]*/gi,
    /Published at the Publication Division[^\n]*/gi,
    /Phone\s*:\s*[\d\-]+/gi,
    /\bPD\s+\d+T\s+RPS\b/gi,
    /not to be republished/gi,
    /NCERT\s+NOT\s+TO\s+BE\s+REPUBLISHED/gi,
  ];
  for (const p of noisePatterns) {
    t = t.replace(p, '');
  }
  
  // Collapse multiple spaces
  t = t.replace(/[ \t]{2,}/g, ' ');
  // Trim lines
  t = t.split('\n').map(l => l.trimEnd()).join('\n');
  
  return t.trim();
}

// ── Clean text from OK (non-corrupted) files ──
function cleanExistingText(text) {
  let t = text;
  
  // Fix PDF extraction artifacts
  t = t.replace(/([A-Z])\n([A-Z]{2,})/g, '$1$2');     // Split words across lines
  t = t.replace(/([a-z])-\n([a-z])/g, '$1$2');         // Hyphenation artifacts
  t = t.replace(/[ \t]{2,}/g, ' ');                     // Multiple spaces
  
  // Fix mojibake
  t = t.replace(/â€™/g, "'");
  t = t.replace(/â€˜/g, "'");
  t = t.replace(/â€œ/g, '"');
  t = t.replace(/â€\u009d/g, '"');
  t = t.replace(/â€"/g, '—');
  t = t.replace(/â€"/g, '–');
  t = t.replace(/Â©/g, '©');
  t = t.replace(/Â/g, '');
  
  // Strip noise
  const noisePatterns = [
    /Rationalised\s+\d{4}[-–]\d{2,4}/gi,
    /©\s*National Council[^\n]*/gi,
    /ALL RIGHTS RESERVED[^\n]*/gi,
    /ISBN\s+[\d\-]+/gi,
    /Printed on \d+ GSM[^\n]*/gi,
    /Published at the Publication Division[^\n]*/gi,
    /Phone\s*:\s*[\d\-]+/gi,
    /\bPD\s+\d+T\s+RPS\b/gi,
    /not to be republished/gi,
    /NCERT\s+NOT\s+TO\s+BE\s+REPUBLISHED/gi,
  ];
  for (const p of noisePatterns) {
    t = t.replace(p, '');
  }
  
  // Remove bare page numbers
  t = t.replace(/\n\s*\d{1,4}\s*\n/g, '\n');
  
  // Trim lines, reduce excessive newlines
  t = t.split('\n').map(l => l.trimEnd()).join('\n');
  t = t.replace(/\n{4,}/g, '\n\n\n');
  
  return t.trim();
}

// ── Detect book metadata ──
function detectBookMeta(fileName) {
  const name = fileName.toLowerCase();
  let subject = 'General', classLevel = '', author = 'NCERT', level = 'Beginner';

  const classMatch = name.match(/class[- _]?(\d+)/i);
  if (classMatch) classLevel = 'Class ' + classMatch[1];
  const classNum = classMatch ? parseInt(classMatch[1]) : 0;

  if (name.includes('history') || name.includes('our past')) subject = 'History';
  else if (name.includes('geography') || name.includes('contemporary india') || name.includes('the earth')) subject = 'Geography';
  else if (name.includes('polity') || name.includes('political') || name.includes('democratic')) subject = 'Polity';
  else if (name.includes('economics') || name.includes('economy')) subject = 'Economy';
  else if (name.includes('science') && !name.includes('political')) subject = 'Science & Technology';
  else if (name.includes('biology')) subject = 'Science & Technology';
  else if (name.includes('chemistry')) subject = 'Science & Technology';
  else if (name.includes('physics')) subject = 'Science & Technology';
  else if (name.includes('environment')) subject = 'Environment';
  else if (name.includes('sociology')) subject = 'Social Issues';
  else if (name.includes('art') && name.includes('culture')) subject = 'History';
  else if (name.includes('mathematics') || name.includes('math')) subject = 'Mathematics';
  else if (name.includes('english')) subject = 'English';
  else if (name.includes('computer')) subject = 'Science & Technology';

  if (name.includes('bipan chandra')) { author = 'Bipan Chandra'; level = 'Intermediate'; }
  else if (name.includes('satish chandra')) { author = 'Satish Chandra'; level = 'Intermediate'; }
  else if (name.includes('rs sharma') || name.includes('r.s. sharma') || name.includes('rs-sharma') || name.includes('ancient-india-rs')) { author = 'R.S. Sharma'; level = 'Intermediate'; }
  else if (classNum >= 11) { level = 'Intermediate'; }

  let title = fileName.replace(/\.pdf$/i, '').replace(/\.txt$/i, '')
    .replace(/\s*\(\d+\)\s*/g, '')
    .replace(/-\d+$/, '')
    .replace(/NCERT-/g, 'NCERT ')
    .replace(/-/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  const upscCore = ['history', 'polity', 'political', 'geography', 'economics', 'economy', 'environment', 'art', 'culture', 'science'];
  const isMustRead = upscCore.some(s => name.includes(s)) && (classNum >= 6 || name.includes('old ncert') || name.includes('bipan') || name.includes('satish'));

  const tags = [];
  if (classNum <= 10 && classNum > 0) tags.push('Prelims');
  if (classNum >= 11) tags.push('Mains');
  if (name.includes('problem')) tags.push('Practice');
  if (tags.length === 0) tags.push('Prelims', 'Mains');

  return { title, author, subject, classLevel, level, isMustRead, tags };
}

// ── Split text into chapters ──
function splitIntoChapters(text, meta) {
  const chapters = [];
  
  // Chapter detection regex
  const chapterRegex = /(?:^|\n)(?:\s*)((?:CHAPTER|Chapter|UNIT|Unit|LESSON|Lesson)\s*[\-–—:.]?\s*(\d+|[IVXLC]+|One|Two|Three|Four|Five|Six|Seven|Eight|Nine|Ten|Eleven|Twelve|Thirteen|Fourteen|Fifteen|Sixteen|Seventeen|Eighteen|Nineteen|Twenty)[^\n]*)/gi;
  const matches = [...text.matchAll(chapterRegex)];

  if (matches.length >= 2) {
    for (let i = 0; i < matches.length; i++) {
      const start = matches[i].index;
      const end = i + 1 < matches.length ? matches[i + 1].index : text.length;
      const chapterText = text.substring(start, end).trim();
      const titleLine = matches[i][1].trim();

      let chTitle = titleLine
        .replace(/^(CHAPTER|Chapter|UNIT|Unit|LESSON|Lesson)\s*[\-–—:.]?\s*(\d+|[IVXLC]+|[A-Za-z]+)\s*[\-–—:.]?\s*/i, '')
        .trim();
      
      if (!chTitle || chTitle.length < 3) {
        const linesAfter = chapterText.split('\n').slice(1);
        for (const ln of linesAfter) {
          const t = ln.trim();
          if (t.length > 3 && t.length < 150 && !/^\d+$/.test(t)) {
            chTitle = t;
            break;
          }
        }
        if (!chTitle || chTitle.length < 3) chTitle = titleLine;
      }

      chapters.push({
        chapterNumber: i + 1,
        chapterTitle: chTitle.substring(0, 200),
        content: chapterText,
      });
    }
  } else {
    // Fallback: split by size
    const PAGE_SIZE = 8000;
    const paragraphs = text.split(/\n{2,}/);
    let current = '';
    let chNum = 1;

    for (const para of paragraphs) {
      current += para + '\n\n';
      if (current.length >= PAGE_SIZE) {
        const firstLine = current.trim().split('\n')[0].trim();
        const title = firstLine.length < 100 && firstLine.length > 3 ? firstLine : `Section ${chNum}`;
        chapters.push({ chapterNumber: chNum, chapterTitle: title, content: current.trim() });
        current = '';
        chNum++;
      }
    }
    if (current.trim().length > 100) {
      const firstLine = current.trim().split('\n')[0].trim();
      const title = firstLine.length < 100 && firstLine.length > 3 ? firstLine : `Section ${chNum}`;
      chapters.push({ chapterNumber: chNum, chapterTitle: title, content: current.trim() });
    }
  }

  if (chapters.length === 0 && text.trim().length > 100) {
    chapters.push({ chapterNumber: 1, chapterTitle: meta.title, content: text.trim() });
  }

  return chapters;
}

// ── Firebase helpers ──
let cachedIdToken = null;
let tokenExpiry = 0;

function httpPost(url, body) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const bodyStr = JSON.stringify(body);
    const options = {
      hostname: urlObj.hostname, port: 443,
      path: urlObj.pathname + urlObj.search,
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(bodyStr) },
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => { try { resolve(JSON.parse(data)); } catch { resolve(data); } });
    });
    req.on('error', reject);
    req.write(bodyStr);
    req.end();
  });
}

async function getFirebaseToken() {
  if (cachedIdToken && Date.now() < tokenExpiry - 60000) return cachedIdToken;
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}`;
  const result = await httpPost(url, { email: 'bookuploader@test.com', password: 'TempUpload2025!', returnSecureToken: true });
  if (result.error) throw new Error('Firebase auth failed: ' + (result.error.message || JSON.stringify(result.error)));
  cachedIdToken = result.idToken;
  tokenExpiry = Date.now() + 3600 * 1000;
  console.log('  🔑 Firebase auth OK');
  return cachedIdToken;
}

function httpPatch(url, body) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const bodyStr = JSON.stringify(body);
    const options = {
      hostname: urlObj.hostname, port: 443,
      path: urlObj.pathname + urlObj.search,
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(bodyStr) },
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
        catch { resolve({ status: res.statusCode, body: data }); }
      });
    });
    req.on('error', reject);
    req.write(bodyStr);
    req.end();
  });
}

function jsToFirestoreValue(val) {
  if (val === null || val === undefined) return { nullValue: null };
  if (typeof val === 'string') return { stringValue: val };
  if (typeof val === 'number') {
    if (Number.isInteger(val)) return { integerValue: String(val) };
    return { doubleValue: val };
  }
  if (typeof val === 'boolean') return { booleanValue: val };
  if (Array.isArray(val)) return { arrayValue: { values: val.map(v => jsToFirestoreValue(v)) } };
  if (typeof val === 'object') {
    const mapFields = {};
    for (const [k, v] of Object.entries(val)) mapFields[k] = jsToFirestoreValue(v);
    return { mapValue: { fields: mapFields } };
  }
  return { stringValue: String(val) };
}

async function writeToFirestore(collection, docId, data) {
  const token = await getFirebaseToken();
  const url = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/${collection}/${docId}?key=${FIREBASE_API_KEY}`;
  const fields = {};
  for (const [key, value] of Object.entries(data)) fields[key] = jsToFirestoreValue(value);
  const urlObj = new URL(url);
  const bodyStr = JSON.stringify({ fields });
  const result = await new Promise((resolve, reject) => {
    const options = {
      hostname: urlObj.hostname, port: 443,
      path: urlObj.pathname + urlObj.search,
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(bodyStr),
        'Authorization': 'Bearer ' + token,
      },
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
        catch { resolve({ status: res.statusCode, body: data }); }
      });
    });
    req.on('error', reject);
    req.write(bodyStr);
    req.end();
  });
  if (result.status !== 200) throw new Error(`Firestore write failed (${result.status}): ${JSON.stringify(result.body).substring(0, 300)}`);
  return result;
}

// ── Upload a single book to Firebase ──
async function uploadBook(txtFileName) {
  const txtPath = path.join(TXT_DIR, txtFileName);
  if (!fs.existsSync(txtPath)) return false;
  
  const text = fs.readFileSync(txtPath, 'utf8');
  if (text.trim().length < 50) return false;
  
  const pdfName = txtFileName.replace(/\.txt$/, '.pdf');
  const meta = detectBookMeta(pdfName);
  const bookId = 'book_' + slugify(pdfName);
  
  console.log(`  📤 ${meta.title}`);
  
  const chapters = splitIntoChapters(text, meta);
  console.log(`     ${chapters.length} chapters`);
  
  // Upload chapters one at a time (memory-efficient)
  const chapterIds = [];
  for (let c = 0; c < chapters.length; c++) {
    const ch = chapters[c];
    const chapterId = `${bookId}_ch${ch.chapterNumber}`;
    chapterIds.push(chapterId);
    
    await writeToFirestore('book_chapters', chapterId, {
      id: chapterId,
      bookId: bookId,
      bookTitle: meta.title,
      chapterNumber: ch.chapterNumber,
      chapterTitle: ch.chapterTitle,
      content: ch.content.substring(0, 900000),
      summary: '',
      keyTopics: [],
      keyTerms: {},
      upscRelevance: '',
      examTips: [],
      practiceQuestions: [],
      subject: meta.subject,
    });
    
    process.stdout.write(`\r     Chapters: ${c + 1}/${chapters.length}`);
    await sleep(200);
  }
  console.log('');
  
  // Upload book metadata
  await writeToFirestore('books', bookId, {
    id: bookId,
    title: meta.title,
    author: meta.author,
    description: `${meta.classLevel ? meta.classLevel + ' — ' : ''}${meta.subject} textbook with ${chapters.length} chapters.`,
    subject: meta.subject,
    coverUrl: '',
    rating: meta.isMustRead ? 4.7 : 4.3,
    isMustRead: meta.isMustRead,
    level: meta.level,
    tags: meta.tags,
    hasContent: true,
    totalChapters: chapters.length,
    chapterIds: chapterIds,
  });
  
  console.log(`     ✓ Uploaded`);
  return true;
}

// ══════════════════════════════════════════
// MAIN
// ══════════════════════════════════════════
async function main() {
  console.log('════════════════════════════════════════════');
  console.log('  📚 UPSC Books — Fix & Re-upload');
  console.log('════════════════════════════════════════════');
  
  const progress = loadProgress();
  
  if (!uploadOnly) {
    // ── Phase 1: OCR Extract corrupted books ──
    if (!cleanupOnly) {
      console.log('\n═══ PHASE 1: OCR Re-extraction of Corrupted Books ═══\n');
      
      let filesToProcess = CORRUPTED_FILES;
      if (onlyFile) {
        filesToProcess = filesToProcess.filter(f => f.includes(onlyFile));
        if (filesToProcess.length === 0) {
          // Check if it's a specific file
          if (fs.existsSync(path.join(BOOKS_DIR, onlyFile))) {
            filesToProcess = [onlyFile];
          } else {
            console.log(`No file matching: ${onlyFile}`);
            return;
          }
        }
      }
      
      let done = 0, skipped = 0, failed = 0;
      const total = filesToProcess.length;
      
      for (let i = startIndex; i < total; i++) {
        if (batchSize > 0 && done >= batchSize) {
          console.log(`\n  Batch limit reached (${batchSize}). Run again with --start ${i}`);
          break;
        }
        
        const pdfFile = filesToProcess[i];
        
        if (progress.ocr_extracted.includes(pdfFile)) {
          skipped++;
          continue;
        }
        
        console.log(`\n  [${i + 1}/${total}] Processing ${pdfFile}`);
        
        try {
          const success = await ocrExtractPdf(pdfFile);
          if (success) {
            progress.ocr_extracted.push(pdfFile);
            saveProgress(progress);
            done++;
          } else {
            failed++;
          }
        } catch (e) {
          console.log(`    ✗ Error: ${e.message.substring(0, 100)}`);
          failed++;
        }
        
        // Force GC between books
        if (global.gc) global.gc();
      }
      
      console.log(`\n  Summary: Done=${done} Skipped=${skipped} Failed=${failed}`);
    }
    
    // ── Phase 2: Cleanup OK books ──
    if (!ocrOnly) {
    console.log('\n═══ PHASE 2: Cleaning up existing text files ═══\n');
    
    const txtFiles = fs.readdirSync(TXT_DIR).filter(f => f.endsWith('.txt')).sort();
    let cleaned = 0;
    
    for (const txtFile of txtFiles) {
      if (progress.cleaned.includes(txtFile)) continue;
      
      const txtPath = path.join(TXT_DIR, txtFile);
      const text = fs.readFileSync(txtPath, 'utf8');
      
      // Check if it's readable
      const alphaRatio = (text.match(/[a-zA-Z]/g) || []).length / Math.max(text.length, 1);
      if (alphaRatio < 0.2) {
        console.log(`  ⚠ ${txtFile} — still unreadable (${(alphaRatio * 100).toFixed(0)}% alpha), needs OCR`);
        continue;
      }
      
      const cleaned_text = cleanExistingText(text);
      fs.writeFileSync(txtPath, cleaned_text, 'utf8');
      progress.cleaned.push(txtFile);
      saveProgress(progress);
      cleaned++;
      
      process.stdout.write(`\r  Cleaned: ${cleaned} files`);
    }
    console.log(`\n  ✓ Cleaned ${cleaned} text files`);
    } // end !ocrOnly
  }
  
  if (!ocrOnly) {
  // ── Phase 3: Upload to Firebase ──
  console.log('\n═══ PHASE 3: Uploading to Firebase ═══\n');
  
  const txtFiles = fs.readdirSync(TXT_DIR).filter(f => f.endsWith('.txt')).sort();
  let uploaded = 0, uploadSkipped = 0, uploadFailed = 0;
  
  for (const txtFile of txtFiles) {
    if (progress.uploaded.includes(txtFile)) {
      uploadSkipped++;
      continue;
    }
    
    try {
      const success = await uploadBook(txtFile);
      if (success) {
        progress.uploaded.push(txtFile);
        saveProgress(progress);
        uploaded++;
      }
    } catch (e) {
      console.log(`  ✗ ${txtFile}: ${e.message.substring(0, 150)}`);
      uploadFailed++;
    }
    
    await sleep(300);
  }
  
  console.log(`\n  Upload Summary: Done=${uploaded} Skipped=${uploadSkipped} Failed=${uploadFailed}`);
  } // end !ocrOnly
  
  console.log('\n════════════════════════════════════════════');
  console.log('  ✅ ALL DONE');
  console.log('════════════════════════════════════════════');
}

main().catch(err => { console.error('Fatal:', err); process.exit(1); });
