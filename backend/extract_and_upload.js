// ==========================================
// Phase 1: Extract text from all PDFs → save as .txt
// Phase 2: Upload to Firebase (books + book_chapters)
// ==========================================
// Usage: node extract_and_upload.js [--extract] [--upload] [--both]
//        node extract_and_upload.js --only "filename.pdf"
// ==========================================

const fs = require('fs');
const path = require('path');
const https = require('https');

const BOOKS_DIR = path.join(__dirname, '..', 'books');
const TXT_DIR = path.join(BOOKS_DIR, 'extracted_text');
const FIREBASE_PROJECT_ID = 'upsc-app-e2475';
const FIREBASE_API_KEY = 'AIzaSyDbOuNUCnM5j81IXWd41vOV1lfsjMYwygE';
const PROGRESS_FILE = path.join(__dirname, 'extract_progress.json');

// ── CLI args ──
const args = process.argv.slice(2);
let doExtract = args.includes('--extract') || args.includes('--both') || args.length === 0;
let doUpload = args.includes('--upload') || args.includes('--both') || args.length === 0;
let onlyFile = null;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--only' && args[i + 1]) onlyFile = args[i + 1];
}
// Default: do both if no flag given
if (!args.includes('--extract') && !args.includes('--upload') && !args.includes('--both')) {
  doExtract = true;
  doUpload = true;
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function slugify(str) {
  return str.replace(/\.pdf$/i, '').replace(/[^a-zA-Z0-9]+/g, '_').toLowerCase().substring(0, 80);
}

// ── Detect book metadata from filename ──
function detectBookMeta(fileName) {
  const name = fileName.toLowerCase();
  let subject = 'General';
  let classLevel = '';
  let author = 'NCERT';
  let level = 'Beginner';

  const classMatch = name.match(/class[- _]?(\d+)/i);
  if (classMatch) classLevel = 'Class ' + classMatch[1];
  const classNum = classMatch ? parseInt(classMatch[1]) : 0;

  if (name.includes('history') || name.includes('our past') || name.includes('our pasts') || name.includes('india and the contemporary')) subject = 'History';
  else if (name.includes('geography') || name.includes('contemporary india') || name.includes('the earth')) subject = 'Geography';
  else if (name.includes('polity') || name.includes('political') || name.includes('democratic') || name.includes('social and political')) subject = 'Polity';
  else if (name.includes('economics') || name.includes('economy') || name.includes('understanding economic')) subject = 'Economy';
  else if (name.includes('science') && !name.includes('political')) subject = 'Science & Technology';
  else if (name.includes('biology')) subject = 'Science & Technology';
  else if (name.includes('chemistry')) subject = 'Science & Technology';
  else if (name.includes('physics')) subject = 'Science & Technology';
  else if (name.includes('environment') || name.includes('ecology')) subject = 'Environment';
  else if (name.includes('sociology')) subject = 'Social Issues';
  else if (name.includes('art') && name.includes('culture')) subject = 'History';
  else if (name.includes('mathematics') || name.includes('math')) subject = 'Mathematics';
  else if (name.includes('english')) subject = 'English';

  if (name.includes('bipan chandra') || name.includes('bipan-chandra')) { author = 'Bipan Chandra'; level = 'Intermediate'; }
  else if (name.includes('satish chandra') || name.includes('satish-chandra')) { author = 'Satish Chandra'; level = 'Intermediate'; }
  else if (name.includes('rs sharma') || name.includes('r.s. sharma') || name.includes('rs-sharma')) { author = 'R.S. Sharma'; level = 'Intermediate'; }
  else if (classNum >= 11) { level = 'Intermediate'; }

  let title = fileName.replace(/\.pdf$/i, '')
    .replace(/\s*\(\d+\)\s*/g, '')
    .replace(/-\d+$/, '')
    .replace(/NCERT-/g, 'NCERT ')
    .replace(/-/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  const upscCore = ['history', 'polity', 'political', 'geography', 'economics', 'economy', 'environment', 'art', 'culture', 'science'];
  const isMustRead = upscCore.some(s => name.includes(s)) && (classNum >= 6 || name.includes('old ncert') || name.includes('bipan') || name.includes('satish') || name.includes('sharma'));

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

  // ── Fix PDF extraction artifacts ──
  // Fix split words across lines (e.g. "I\nNDIAN" → "INDIAN")
  let fixedText = text.replace(/([A-Z])\n([A-Z]{2,})/g, '$1$2');
  // Fix hyphenation artifacts (e.g. "under-\nstand" → "understand")
  fixedText = fixedText.replace(/([a-z])-\n([a-z])/g, '$1$2');
  // Collapse multiple spaces to single space (fixes "i   ndian" etc.)
  fixedText = fixedText.replace(/[ \t]{2,}/g, ' ');
  // Fix mojibake UTF-8 encoding issues
  fixedText = fixedText.replace(/â€™/g, "'");
  fixedText = fixedText.replace(/â€˜/g, "'");
  fixedText = fixedText.replace(/â€œ/g, '"');
  fixedText = fixedText.replace(/â€\u009d/g, '"');
  fixedText = fixedText.replace(/â€"/g, '—');
  fixedText = fixedText.replace(/â€"/g, '–');
  fixedText = fixedText.replace(/Â©/g, '©');
  fixedText = fixedText.replace(/Â/g, '');

  // Strip common noise: copyright, publication info, ISBN, phone numbers, etc.
  const noisePatterns = [
    /Rationalised\s+\d{4}[-–]\d{2,4}/gi,
    /©\s*National Council[^\n]*/gi,
    /ALL RIGHTS RESERVED[^\n]*/gi,
    /ISBN\s+[\d\-]+/gi,
    /Printed on \d+ GSM[^\n]*/gi,
    /Published at the Publication Division[^\n]*/gi,
    /Phone\s*:\s*[\d\-]+/gi,
    /\bPD\s+\d+T\s+RPS\b/gi,
  ];
  let cleanedText = fixedText;
  for (const p of noisePatterns) {
    cleanedText = cleanedText.replace(p, '');
  }
  // Remove bare page numbers (lines that are just a number)
  cleanedText = cleanedText.replace(/\n\s*\d{1,4}\s*\n/g, '\n');

  // Try to find chapter boundaries
  // Common patterns: "Chapter 1", "CHAPTER 1", "Chapter One", "1. Title", "Unit 1"
  const chapterRegex = /(?:^|\n)(?:\s*)((?:CHAPTER|Chapter|UNIT|Unit|LESSON|Lesson)\s*[\-–—:.]?\s*(\d+|[IVXLC]+|One|Two|Three|Four|Five|Six|Seven|Eight|Nine|Ten|Eleven|Twelve|Thirteen|Fourteen|Fifteen|Sixteen|Seventeen|Eighteen|Nineteen|Twenty)[^\n]*)/gi;

  const matches = [...cleanedText.matchAll(chapterRegex)];

  if (matches.length >= 2) {
    // Split by detected chapter headings
    for (let i = 0; i < matches.length; i++) {
      const start = matches[i].index;
      const end = i + 1 < matches.length ? matches[i + 1].index : cleanedText.length;
      const chapterText = cleanedText.substring(start, end).trim();
      const titleLine = matches[i][1].trim();

      // Clean title — extract the actual chapter name
      let chTitle = titleLine.replace(/^(CHAPTER|Chapter|UNIT|Unit|LESSON|Lesson)\s*[\-–—:.]?\s*(\d+|[IVXLC]+|[A-Za-z]+)\s*[\-–—:.]?\s*/i, '').trim();
      if (!chTitle || chTitle.length < 3) {
        // Try to get title from next non-empty line after heading
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
    // No clear chapters found — split by page-like boundaries or fixed size
    const PAGE_SIZE = 8000; // ~8K chars per "chapter"
    const paragraphs = cleanedText.split(/\n{2,}/);
    let current = '';
    let chNum = 1;

    for (const para of paragraphs) {
      current += para + '\n\n';
      if (current.length >= PAGE_SIZE) {
        // Try to find a heading in the first line
        const firstLine = current.trim().split('\n')[0].trim();
        const title = firstLine.length < 100 && firstLine.length > 3 ? firstLine : `Section ${chNum}`;
        chapters.push({
          chapterNumber: chNum,
          chapterTitle: title,
          content: current.trim(),
        });
        current = '';
        chNum++;
      }
    }
    if (current.trim().length > 100) {
      const firstLine = current.trim().split('\n')[0].trim();
      const title = firstLine.length < 100 && firstLine.length > 3 ? firstLine : `Section ${chNum}`;
      chapters.push({
        chapterNumber: chNum,
        chapterTitle: title,
        content: current.trim(),
      });
    }
  }

  // If we got nothing, put it all as one chapter
  if (chapters.length === 0 && cleanedText.trim().length > 100) {
    chapters.push({
      chapterNumber: 1,
      chapterTitle: meta.title,
      content: cleanedText.trim(),
    });
  }

  return chapters;
}

// ── Firebase anonymous auth ──
let cachedIdToken = null;
let tokenExpiry = 0;

function httpPost(url, body) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const bodyStr = JSON.stringify(body);
    const options = {
      hostname: urlObj.hostname,
      port: 443,
      path: urlObj.pathname + urlObj.search,
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(bodyStr) }
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

function httpPatch(url, body, idToken) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const bodyStr = JSON.stringify(body);
    const headers = {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(bodyStr),
    };
    if (idToken) headers['Authorization'] = 'Bearer ' + idToken;
    const options = {
      hostname: urlObj.hostname,
      port: 443,
      path: urlObj.pathname + urlObj.search,
      method: 'PATCH',
      headers,
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => { try { resolve({ status: res.statusCode, body: JSON.parse(data) }); } catch { resolve({ status: res.statusCode, body: data }); } });
    });
    req.on('error', reject);
    req.write(bodyStr);
    req.end();
  });
}

async function getFirebaseToken() {
  if (cachedIdToken && Date.now() < tokenExpiry - 60000) return cachedIdToken;
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${FIREBASE_API_KEY}`;
  const result = await httpPost(url, { returnSecureToken: true });
  if (result.error) throw new Error('Firebase auth failed: ' + (result.error.message || JSON.stringify(result.error)));
  cachedIdToken = result.idToken;
  tokenExpiry = Date.now() + 3600 * 1000;
  return cachedIdToken;
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
  const url = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/${collection}/${docId}?key=${FIREBASE_API_KEY}`;
  const fields = {};
  for (const [key, value] of Object.entries(data)) fields[key] = jsToFirestoreValue(value);
  const result = await httpPatch(url, { fields }, null);
  if (result.status !== 200) throw new Error(`Firestore write failed (${result.status}): ${JSON.stringify(result.body).substring(0, 300)}`);
  return result;
}

// ── Progress ──
function loadProgress() {
  if (fs.existsSync(PROGRESS_FILE)) return JSON.parse(fs.readFileSync(PROGRESS_FILE, 'utf8'));
  return { extracted: [], uploaded: [], failed: [] };
}
function saveProgress(p) { fs.writeFileSync(PROGRESS_FILE, JSON.stringify(p, null, 2)); }

// ══════════════════════════════════════════
// PHASE 1: Extract text from PDFs
// ══════════════════════════════════════════
async function extractAll(pdfFiles, progress) {
  console.log('\n═══ PHASE 1: Extracting text from PDFs ═══\n');
  if (!fs.existsSync(TXT_DIR)) fs.mkdirSync(TXT_DIR, { recursive: true });

  let pdfParse;
  try { pdfParse = require('pdf-parse'); } catch { console.error('Run: npm install pdf-parse@1.1.1'); process.exit(1); }

  let done = 0, failed = 0, skipped = 0;

  for (let i = 0; i < pdfFiles.length; i++) {
    const fileName = pdfFiles[i];
    const txtName = fileName.replace(/\.pdf$/i, '.txt');
    const txtPath = path.join(TXT_DIR, txtName);

    if (progress.extracted.includes(fileName)) {
      skipped++;
      continue;
    }

    process.stdout.write(`\r  [${i + 1}/${pdfFiles.length}] Extracting: ${fileName.substring(0, 50).padEnd(50)}`);

    try {
      const pdfPath = path.join(BOOKS_DIR, fileName);
      const dataBuffer = fs.readFileSync(pdfPath);
      const data = await pdfParse(dataBuffer);
      const text = data.text || '';

      if (text.trim().length < 50) {
        console.log(`\n  ⚠ ${fileName}: Very little text (${text.length} chars) — may be scanned/image PDF`);
        progress.failed.push({ file: fileName, reason: 'Too little text extracted' });
        failed++;
        saveProgress(progress);
        continue;
      }

      fs.writeFileSync(txtPath, text, 'utf8');
      progress.extracted.push(fileName);
      saveProgress(progress);
      done++;
    } catch (err) {
      console.log(`\n  ✗ ${fileName}: ${err.message.substring(0, 100)}`);
      progress.failed.push({ file: fileName, reason: err.message.substring(0, 100) });
      saveProgress(progress);
      failed++;
    }
  }

  console.log(`\n\n  ✓ Extracted: ${done} | Skipped: ${skipped} | Failed: ${failed}\n`);
}

// ══════════════════════════════════════════
// PHASE 2: Upload to Firebase
// ══════════════════════════════════════════
async function uploadAll(pdfFiles, progress) {
  console.log('\n═══ PHASE 2: Uploading to Firebase ═══\n');

  let done = 0, failed = 0, skipped = 0;

  for (let i = 0; i < pdfFiles.length; i++) {
    const fileName = pdfFiles[i];
    const txtName = fileName.replace(/\.pdf$/i, '.txt');
    const txtPath = path.join(TXT_DIR, txtName);
    const bookId = 'book_' + slugify(fileName);

    if (progress.uploaded.includes(fileName)) {
      skipped++;
      continue;
    }

    if (!fs.existsSync(txtPath)) {
      continue; // text not extracted yet
    }

    const meta = detectBookMeta(fileName);
    const text = fs.readFileSync(txtPath, 'utf8');

    if (text.trim().length < 50) continue;

    console.log(`  [${i + 1}/${pdfFiles.length}] ${meta.title}`);

    try {
      // Split into chapters
      const chapters = splitIntoChapters(text, meta);
      console.log(`    → ${chapters.length} chapters detected`);

      // Upload chapters
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
          content: ch.content.substring(0, 900000), // Firestore doc size limit safety
          summary: '',
          keyTopics: [],
          keyTerms: {},
          upscRelevance: '',
          examTips: [],
          practiceQuestions: [],
          subject: meta.subject,
        });

        process.stdout.write(`\r    Chapters: ${c + 1}/${chapters.length}`);
        await sleep(200); // avoid rate limit
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

      console.log(`    ✓ Uploaded ${meta.title}`);
      progress.uploaded.push(fileName);
      saveProgress(progress);
      done++;

    } catch (err) {
      console.log(`    ✗ Error: ${err.message.substring(0, 150)}`);
      failed++;
    }

    await sleep(500);
  }

  console.log(`\n  ✓ Uploaded: ${done} | Skipped: ${skipped} | Failed: ${failed}\n`);
}

// ══════════════════════════════════════════
// MAIN
// ══════════════════════════════════════════
async function main() {
  console.log('════════════════════════════════════════════');
  console.log('  📚 UPSC Books — Extract & Upload');
  console.log('════════════════════════════════════════════');

  let pdfFiles = fs.readdirSync(BOOKS_DIR).filter(f => f.toLowerCase().endsWith('.pdf')).sort();
  if (onlyFile) {
    pdfFiles = pdfFiles.filter(f => f.includes(onlyFile));
    if (pdfFiles.length === 0) { console.error('No PDF matching:', onlyFile); process.exit(1); }
  }
  console.log(`  Found ${pdfFiles.length} PDFs\n`);

  const progress = loadProgress();

  if (doExtract) await extractAll(pdfFiles, progress);
  if (doUpload) await uploadAll(pdfFiles, progress);

  console.log('════════════════════════════════════════════');
  console.log('  ✅ DONE');
  console.log('════════════════════════════════════════════');
}

main().catch(err => { console.error('Fatal:', err); process.exit(1); });
