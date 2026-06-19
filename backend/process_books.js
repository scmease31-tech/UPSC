// ==========================================
// UPSC Daily Edge — Book PDF Processor
// Extracts text from PDFs, cleans with Gemini, writes to Firestore
// ==========================================
// Usage: node process_books.js [--start N] [--only "filename.pdf"]
//
// Reads PDFs from ../books/ folder, extracts text, uses Gemini to
// organize into chapters with UPSC-relevant analysis, and writes
// to Firestore collections: "books" and "book_chapters"
// ==========================================

const fs = require('fs');
const path = require('path');
const https = require('https');
const http = require('http');

// ── CONFIG ──────────────────────────────────────────────────────────
const BOOKS_DIR = path.join(__dirname, '..', 'books');
const FIREBASE_PROJECT_ID = 'upsc-app-e2475';
const FIREBASE_API_KEY = 'AIzaSyDbOuNUCnM5j81IXWd41vOV1lfsjMYwygE';
// Gemini API keys (comma-separated via env or --keys arg)
let GEMINI_KEYS = (process.env.GEMINI_API_KEYS || process.env.GEMINI_API_KEY || '').split(',').map(k => k.trim()).filter(k => k);

const GEMINI_MODELS = ['gemini-2.5-flash', 'gemini-2.0-flash'];
const MAX_CHUNK_CHARS = 400000; // ~400K chars per Gemini call (safe for flash)
const QUOTA_COOLDOWN_MS = 65000;
const PROGRESS_FILE = path.join(__dirname, 'books_progress.json');

// ── PARSE CLI ARGS ──────────────────────────────────────────────────
const args = process.argv.slice(2);
let startIndex = 0;
let onlyFile = null;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--start' && args[i + 1]) startIndex = parseInt(args[i + 1]);
  if (args[i] === '--only' && args[i + 1]) onlyFile = args[i + 1];
  if (args[i] === '--keys' && args[i + 1]) {
    GEMINI_KEYS = args[i + 1].split(',').map(k => k.trim()).filter(k => k);
  }
}

// ── HELPERS ─────────────────────────────────────────────────────────
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function slugify(str) {
  return str.replace(/\.pdf$/i, '').replace(/[^a-zA-Z0-9]+/g, '_').toLowerCase().substring(0, 60);
}

// Detect subject/class from filename
function detectBookMeta(fileName) {
  const name = fileName.toLowerCase();
  let subject = 'General';
  let classLevel = '';
  let author = 'NCERT';
  let level = 'Beginner';

  // Detect class
  const classMatch = name.match(/class[- _]?(\d+)/i);
  if (classMatch) classLevel = 'Class ' + classMatch[1];
  const classNum = classMatch ? parseInt(classMatch[1]) : 0;

  // Detect subject
  if (name.includes('history')) subject = 'History';
  else if (name.includes('geography')) subject = 'Geography';
  else if (name.includes('polity') || name.includes('political')) subject = 'Polity';
  else if (name.includes('economics') || name.includes('economy')) subject = 'Economy';
  else if (name.includes('science')) subject = 'Science & Technology';
  else if (name.includes('biology')) subject = 'Science & Technology';
  else if (name.includes('chemistry')) subject = 'Science & Technology';
  else if (name.includes('physics')) subject = 'Science & Technology';
  else if (name.includes('environment')) subject = 'Environment';
  else if (name.includes('sociology')) subject = 'Social Issues';
  else if (name.includes('art') && name.includes('culture')) subject = 'History';
  else if (name.includes('english')) subject = 'General';
  else if (name.includes('mathematics') || name.includes('math')) subject = 'General';
  else if (name.includes('computer')) subject = 'Science & Technology';

  // Detect specific authors
  if (name.includes('bipan chandra')) { author = 'Bipan Chandra'; level = 'Intermediate'; }
  else if (name.includes('satish chandra')) { author = 'Satish Chandra'; level = 'Intermediate'; }
  else if (name.includes('rs sharma') || name.includes('r.s. sharma') || name.includes('rs-sharma')) { author = 'R.S. Sharma'; level = 'Intermediate'; }
  else if (classNum >= 11) { level = 'Intermediate'; }
  else if (classNum >= 6) { level = 'Beginner'; }

  // Build clean title
  let title = fileName.replace(/\.pdf$/i, '')
    .replace(/\s*\(\d+\)\s*/g, '')  // Remove (1), (2)
    .replace(/-\d+$/, '')            // Remove -49
    .replace(/NCERT-/g, 'NCERT ')
    .replace(/-/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  // Detect must-read for UPSC
  const upscCore = ['history', 'polity', 'political', 'geography', 'economics', 'economy', 'environment', 'art', 'culture'];
  const isMustRead = upscCore.some(s => name.includes(s)) && (classNum >= 6 || name.includes('old ncert') || name.includes('bipan') || name.includes('satish') || name.includes('sharma'));

  // Tags
  const tags = [];
  if (name.includes('prelims') || classNum <= 10) tags.push('Prelims');
  if (name.includes('mains') || classNum >= 11) tags.push('Mains');
  if (name.includes('problem')) tags.push('Practice');
  if (name.includes('practical')) tags.push('Practical');
  if (tags.length === 0) tags.push('Prelims', 'Mains');

  return { title, author, subject, classLevel, level, isMustRead, tags };
}

// ── FIREBASE AUTH (Anonymous Sign-In via API Key) ───────────────────
let cachedIdToken = null;
let tokenExpiry = 0;

async function getFirebaseToken() {
  if (cachedIdToken && Date.now() < tokenExpiry - 60000) return cachedIdToken;

  // Sign in anonymously via Firebase Auth REST API
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${FIREBASE_API_KEY}`;
  const result = await httpPost(url, { returnSecureToken: true });

  if (result.error) {
    throw new Error(`Firebase anonymous auth failed: ${result.error.message || JSON.stringify(result.error)}`);
  }

  cachedIdToken = result.idToken;
  // Anonymous tokens last 1 hour
  tokenExpiry = Date.now() + 3600 * 1000;
  console.log('🔐 Firebase anonymous auth successful');
  return cachedIdToken;
}

// ── HTTP HELPERS ────────────────────────────────────────────────────
function httpPost(url, body, contentType) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    let bodyStr;
    if (contentType === 'application/x-www-form-urlencoded') {
      bodyStr = Object.entries(body).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');
    } else {
      bodyStr = JSON.stringify(body);
      contentType = 'application/json';
    }

    const options = {
      hostname: urlObj.hostname,
      port: urlObj.port || 443,
      path: urlObj.pathname + urlObj.search,
      method: 'POST',
      headers: {
        'Content-Type': contentType,
        'Content-Length': Buffer.byteLength(bodyStr),
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch { resolve(data); }
      });
    });
    req.on('error', reject);
    req.write(bodyStr);
    req.end();
  });
}

// ── PDF TEXT EXTRACTION ─────────────────────────────────────────────
let pdfParse;
async function extractPdfText(filePath) {
  if (!pdfParse) pdfParse = require('pdf-parse');
  const dataBuffer = fs.readFileSync(filePath);
  const data = await pdfParse(dataBuffer);
  return data.text || '';
}

// ── GEMINI API ──────────────────────────────────────────────────────
let currentKeyIndex = 0;

async function callGemini(prompt, retries = 3) {
  if (GEMINI_KEYS.length === 0) {
    throw new Error('No GEMINI_API_KEYS set. Export GEMINI_API_KEYS=key1,key2');
  }

  let lastError = '';
  for (let attempt = 0; attempt < retries; attempt++) {
    for (let ki = 0; ki < GEMINI_KEYS.length; ki++) {
      const keyIdx = (currentKeyIndex + ki) % GEMINI_KEYS.length;
      const key = GEMINI_KEYS[keyIdx];

      for (const model of GEMINI_MODELS) {
        const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`;
        try {
          const result = await httpPost(url, {
            contents: [{ parts: [{ text: prompt }] }],
            generationConfig: { temperature: 0.2, maxOutputTokens: 65536 }
          });

          if (result.error) {
            lastError = result.error.message || JSON.stringify(result.error);
            const errLower = lastError.toLowerCase();
            if (errLower.includes('429') || errLower.includes('quota') || errLower.includes('resource_exhausted')) {
              console.log(`  ⏸ Quota hit on key ${keyIdx + 1}, model ${model}. Waiting ${QUOTA_COOLDOWN_MS / 1000}s...`);
              await sleep(QUOTA_COOLDOWN_MS);
              continue;
            }
            continue;
          }

          if (result.candidates && result.candidates[0]?.content?.parts?.[0]?.text) {
            currentKeyIndex = keyIdx; // Remember working key
            let text = result.candidates[0].content.parts[0].text.trim();
            // Strip markdown fences
            if (text.startsWith('```')) {
              text = text.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '');
            }
            return text;
          }
          lastError = 'No content in response';
        } catch (err) {
          lastError = err.message;
        }
      }
    }
    // All keys exhausted this round, wait and retry
    console.log(`  ⚠️ All keys failed (attempt ${attempt + 1}/${retries}). Waiting 30s...`);
    await sleep(30000);
  }
  throw new Error('Gemini failed after all retries: ' + lastError);
}

// ── WRITE TO FIRESTORE ──────────────────────────────────────────────
async function writeToFirestore(collection, docId, data) {
  const token = await getFirebaseToken();
  const url = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/${collection}/${docId}?key=${FIREBASE_API_KEY}`;

  // Convert JS object to Firestore document format
  const fields = {};
  for (const [key, value] of Object.entries(data)) {
    fields[key] = jsToFirestoreValue(value);
  }

  const result = await httpPatchWithIdToken(url, { fields }, token);
  if (result.status !== 200) {
    throw new Error(`Firestore write failed (${result.status}): ${JSON.stringify(result.body).substring(0, 300)}`);
  }
  return result;
}

function httpPatchWithIdToken(url, body, idToken) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const bodyStr = JSON.stringify(body);
    const options = {
      hostname: urlObj.hostname,
      port: 443,
      path: urlObj.pathname + urlObj.search,
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + idToken,
        'Content-Length': Buffer.byteLength(bodyStr),
      }
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
  if (Array.isArray(val)) {
    return { arrayValue: { values: val.map(v => jsToFirestoreValue(v)) } };
  }
  if (typeof val === 'object') {
    const mapFields = {};
    for (const [k, v] of Object.entries(val)) {
      mapFields[k] = jsToFirestoreValue(v);
    }
    return { mapValue: { fields: mapFields } };
  }
  return { stringValue: String(val) };
}

// ── PROGRESS TRACKING ───────────────────────────────────────────────
function loadProgress() {
  if (fs.existsSync(PROGRESS_FILE)) {
    return JSON.parse(fs.readFileSync(PROGRESS_FILE, 'utf8'));
  }
  return { completed: [], failed: [] };
}

function saveProgress(progress) {
  fs.writeFileSync(PROGRESS_FILE, JSON.stringify(progress, null, 2));
}

// ── CHUNK TEXT FOR GEMINI ───────────────────────────────────────────
function chunkText(text, maxChars) {
  const chunks = [];
  let i = 0;
  while (i < text.length) {
    let end = Math.min(i + maxChars, text.length);
    // Try to break at a paragraph or sentence boundary
    if (end < text.length) {
      const lastPara = text.lastIndexOf('\n\n', end);
      if (lastPara > i + maxChars * 0.5) end = lastPara;
      else {
        const lastSent = text.lastIndexOf('. ', end);
        if (lastSent > i + maxChars * 0.5) end = lastSent + 1;
      }
    }
    chunks.push(text.substring(i, end));
    i = end;
  }
  return chunks;
}

// ── PROCESS ONE BOOK ────────────────────────────────────────────────
async function processBook(filePath, index, total) {
  const fileName = path.basename(filePath);
  const meta = detectBookMeta(fileName);
  const bookId = 'book_' + slugify(fileName);

  console.log(`\n📚 [${index + 1}/${total}] ${meta.title}`);
  console.log(`   Subject: ${meta.subject} | Author: ${meta.author} | Level: ${meta.level}`);

  // Step 1: Extract text
  console.log('   📄 Extracting text...');
  let rawText;
  try {
    rawText = await extractPdfText(filePath);
  } catch (err) {
    console.log(`   ❌ PDF extraction failed: ${err.message}`);
    return null;
  }

  if (!rawText || rawText.trim().length < 100) {
    console.log(`   ⚠️ Very little text extracted (${rawText?.length || 0} chars) — may be scanned/image PDF`);
    console.log('   ⏩ Skipping (scanned PDFs need OCR)');
    return null;
  }

  console.log(`   📝 Extracted ${rawText.length} chars (${(rawText.length / 1000).toFixed(0)}K)`);

  // Step 2: Clean and organize with Gemini
  const chunks = chunkText(rawText, MAX_CHUNK_CHARS);
  console.log(`   🤖 Processing with Gemini (${chunks.length} chunk(s))...`);

  const allChapters = [];
  for (let ci = 0; ci < chunks.length; ci++) {
    const chunkLabel = chunks.length > 1 ? ` [chunk ${ci + 1}/${chunks.length}]` : '';
    console.log(`   🔄 Gemini processing${chunkLabel}...`);

    const prompt = buildBookPrompt(meta, chunks[ci], ci, chunks.length);

    try {
      const response = await callGemini(prompt);
      const parsed = JSON.parse(response);

      if (parsed.chapters && Array.isArray(parsed.chapters)) {
        // Offset chapter numbers for multi-chunk books
        const offset = allChapters.length;
        for (const ch of parsed.chapters) {
          ch.chapterNumber = offset + (ch.chapterNumber || allChapters.length + 1);
          allChapters.push(ch);
        }
        console.log(`   ✅ Got ${parsed.chapters.length} chapters${chunkLabel}`);
      } else {
        console.log(`   ⚠️ No chapters in response${chunkLabel}`);
      }
    } catch (err) {
      console.log(`   ❌ Gemini error${chunkLabel}: ${err.message}`);
    }

    // Rate limit pause between chunks
    if (ci < chunks.length - 1) await sleep(5000);
  }

  if (allChapters.length === 0) {
    console.log('   ❌ No chapters extracted, skipping book');
    return null;
  }

  // Step 3: Write to Firestore
  console.log(`   💾 Writing ${allChapters.length} chapters to Firestore...`);

  const chapterIds = [];
  let chaptersWritten = 0;

  for (let i = 0; i < allChapters.length; i++) {
    const ch = allChapters[i];
    const chapterId = `${bookId}_ch${ch.chapterNumber || i + 1}`;
    chapterIds.push(chapterId);

    const chapterDoc = {
      id: chapterId,
      bookId: bookId,
      bookTitle: meta.title,
      chapterNumber: ch.chapterNumber || i + 1,
      chapterTitle: ch.chapterTitle || `Chapter ${i + 1}`,
      content: ch.content || '',
      summary: ch.summary || '',
      keyTopics: ch.keyTopics || [],
      keyTerms: ch.keyTerms || {},
      upscRelevance: ch.upscRelevance || '',
      examTips: ch.examTips || [],
      practiceQuestions: ch.practiceQuestions || [],
      subject: meta.subject,
    };

    try {
      await writeToFirestore('book_chapters', chapterId, chapterDoc);
      chaptersWritten++;
      process.stdout.write(`\r   💾 Chapters: ${chaptersWritten}/${allChapters.length}`);
    } catch (err) {
      console.log(`\n   ⚠️ Failed to write chapter ${chapterId}: ${err.message}`);
    }

    // Small pause to avoid Firestore rate limits
    if (i < allChapters.length - 1) await sleep(300);
  }
  console.log(''); // newline after progress

  // Write book metadata
  const bookDoc = {
    id: bookId,
    title: meta.title,
    author: meta.author,
    description: `${meta.classLevel ? meta.classLevel + ' — ' : ''}${meta.subject} textbook covering ${allChapters.length} chapters. Essential for UPSC ${meta.tags.join(' & ')} preparation.`,
    subject: meta.subject,
    coverUrl: '',
    rating: meta.isMustRead ? 4.7 : 4.3,
    isMustRead: meta.isMustRead,
    level: meta.level,
    tags: meta.tags,
    hasContent: true,
    totalChapters: allChapters.length,
    chapterIds: chapterIds,
  };

  try {
    await writeToFirestore('books', bookId, bookDoc);
    console.log(`   ✅ Book "${meta.title}" saved with ${chaptersWritten} chapters`);
  } catch (err) {
    console.log(`   ❌ Failed to write book metadata: ${err.message}`);
  }

  return { bookId, title: meta.title, chapters: chaptersWritten };
}

// ── GEMINI PROMPT ───────────────────────────────────────────────────
function buildBookPrompt(meta, text, chunkIndex, totalChunks) {
  const chunkNote = totalChunks > 1
    ? `\nThis is part ${chunkIndex + 1} of ${totalChunks} of the book text. Extract chapters from THIS part only.`
    : '';

  return `You are an expert UPSC study material editor. Analyze this ${meta.subject} book text and organize it into clean, well-structured chapters.${chunkNote}

Book: "${meta.title}" by ${meta.author}

TASKS:
1. Identify chapter boundaries in the text
2. Clean up OCR/scan artifacts: fix spelling errors, broken words, garbled text
3. Fix grammar and vocabulary — make content clear and academically precise
4. Organize each chapter with proper structure
5. Add UPSC-relevant analysis for each chapter

For each chapter, provide:
- chapterNumber: Sequential number
- chapterTitle: Clean chapter title
- content: The FULL cleaned-up chapter text (preserve all important information, fix errors, improve readability). Use markdown formatting with ## headings, **bold** for key terms, bullet points for lists. Minimum 500 words per chapter.
- summary: 3-5 sentence summary of the chapter
- keyTopics: Array of 5-8 key topics covered
- keyTerms: Object of important terms with definitions {"term": "definition"}
- upscRelevance: How this chapter is relevant to UPSC (2-3 sentences)
- examTips: Array of 3-5 exam tips specific to this chapter
- practiceQuestions: Array of 3-5 practice questions for self-assessment

QUALITY RULES:
- Fix ALL spelling, grammar, and formatting errors from OCR
- Do NOT skip or summarize content — preserve the full text in cleaned form
- Use proper academic English
- Merge fragmented sentences caused by page breaks
- Remove page numbers, headers/footers, watermarks from the text
- If text is too garbled to fix, note it but include your best interpretation
- Ensure technical terms are spelled correctly (cross-reference known terms)

Return ONLY valid JSON:
{"chapters":[{"chapterNumber":1,"chapterTitle":"...","content":"...","summary":"...","keyTopics":["..."],"keyTerms":{"term":"def"},"upscRelevance":"...","examTips":["..."],"practiceQuestions":["..."]}]}

BOOK TEXT:
${text.substring(0, MAX_CHUNK_CHARS)}`;
}

// ── MAIN ────────────────────────────────────────────────────────────
async function main() {
  console.log('═══════════════════════════════════════════════════');
  console.log('  📚 UPSC Daily Edge — Book Processor');
  console.log('═══════════════════════════════════════════════════\n');

  // Check prerequisites
  if (GEMINI_KEYS.length === 0) {
    console.error('❌ No Gemini API keys found!');
    console.error('Set environment variable: GEMINI_API_KEYS=key1,key2');
    console.error('Or: set GEMINI_API_KEY=your_key');
    process.exit(1);
  }
  console.log(`🔑 ${GEMINI_KEYS.length} Gemini API key(s) loaded`);

  // Test Firebase auth (anonymous sign-in)
  try {
    await getFirebaseToken();
    console.log('✅ Firebase authentication successful\n');
  } catch (err) {
    console.error('❌ Firebase auth failed:', err.message);
    process.exit(1);
  }

  // List all PDFs
  if (!fs.existsSync(BOOKS_DIR)) {
    console.error('❌ Books directory not found:', BOOKS_DIR);
    process.exit(1);
  }

  let pdfFiles = fs.readdirSync(BOOKS_DIR)
    .filter(f => f.toLowerCase().endsWith('.pdf'))
    .sort();

  if (onlyFile) {
    pdfFiles = pdfFiles.filter(f => f.includes(onlyFile));
    if (pdfFiles.length === 0) {
      console.error('❌ No PDF matching:', onlyFile);
      process.exit(1);
    }
  }

  console.log(`📁 Found ${pdfFiles.length} PDF(s) in books/`);

  // Load progress
  const progress = loadProgress();
  console.log(`📊 Previously completed: ${progress.completed.length} books\n`);

  const results = { success: 0, failed: 0, skipped: 0 };

  for (let i = startIndex; i < pdfFiles.length; i++) {
    const fileName = pdfFiles[i];
    const filePath = path.join(BOOKS_DIR, fileName);

    // Skip already completed
    if (progress.completed.includes(fileName)) {
      console.log(`⏩ [${i + 1}/${pdfFiles.length}] Skipping (already done): ${fileName}`);
      results.skipped++;
      continue;
    }

    try {
      const result = await processBook(filePath, i, pdfFiles.length);
      if (result) {
        progress.completed.push(fileName);
        saveProgress(progress);
        results.success++;
      } else {
        progress.failed.push(fileName);
        saveProgress(progress);
        results.failed++;
      }
    } catch (err) {
      console.log(`   ❌ Fatal error: ${err.message}`);
      progress.failed.push(fileName);
      saveProgress(progress);
      results.failed++;
    }

    // Pause between books
    if (i < pdfFiles.length - 1) {
      console.log('   ⏱ Waiting 5s before next book...');
      await sleep(5000);
    }
  }

  console.log('\n═══════════════════════════════════════════════════');
  console.log('  📊 PROCESSING COMPLETE');
  console.log('═══════════════════════════════════════════════════');
  console.log(`  ✅ Success: ${results.success}`);
  console.log(`  ❌ Failed:  ${results.failed}`);
  console.log(`  ⏩ Skipped: ${results.skipped}`);
  console.log(`  📚 Total:   ${pdfFiles.length}`);
  console.log('═══════════════════════════════════════════════════\n');
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
