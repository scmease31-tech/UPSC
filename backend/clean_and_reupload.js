// ==========================================
// Clean garbled book content & re-upload to Firestore
// ==========================================
// Usage: node clean_and_reupload.js [--dry-run] [--only "filename.txt"]
// ==========================================

const fs = require('fs');
const path = require('path');
const https = require('https');

const BOOKS_DIR = path.join(__dirname, '..', 'books');
const TXT_DIR = path.join(BOOKS_DIR, 'extracted_text');
const CLEAN_DIR = path.join(BOOKS_DIR, 'cleaned_text');
const FIREBASE_PROJECT_ID = 'upsc-app-e2475';
const FIREBASE_API_KEY = 'AIzaSyDbOuNUCnM5j81IXWd41vOV1lfsjMYwygE';

// CLI args
const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
let onlyFile = null;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--only' && args[i + 1]) onlyFile = args[i + 1];
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function slugify(str) {
  return str.replace(/\.pdf$/i, '').replace(/\.txt$/i, '').replace(/[^a-zA-Z0-9]+/g, '_').toLowerCase().substring(0, 80);
}

// ══════════════════════════════════════════
// LINE-LEVEL CLEANING
// ══════════════════════════════════════════

// Dingbats & symbols ranges that indicate garbled PDF extraction
const DINGBAT_REGEX = /[\u2700-\u27BF\u2600-\u26FF\u2B50-\u2B55\u2702-\u27B0\u2190-\u21FF\u25A0-\u25FF\u2300-\u23FF\u2460-\u24FF\u2580-\u259F\u2660-\u2667\u2669-\u266F\u2794-\u27BF\u2022-\u2023\u00A7\u00B6\u00AE\u00A9]/g;

function isGarbledLine(line) {
  const trimmed = line.trim();
  if (trimmed.length === 0) return false; // Keep blank lines for paragraph breaks
  if (trimmed.length <= 2) return true; // Single/double char lines are noise

  // Count different character types
  const alphaCount = (trimmed.match(/[a-zA-Z]/g) || []).length;
  const digitCount = (trimmed.match(/[0-9]/g) || []).length;
  const dingbatCount = (trimmed.match(DINGBAT_REGEX) || []).length;
  const punctCount = (trimmed.match(/[=\[\]{}|<>\\\/;:@#$%^&*()_+~`]/g) || []).length;
  const totalChars = trimmed.length;

  // If line is mostly dingbats/symbols, it's garbled
  if (dingbatCount > totalChars * 0.3) return true;

  // If line has very few alpha chars relative to total
  const alphaRatio = alphaCount / totalChars;
  if (alphaRatio < 0.25 && totalChars > 10) {
    if ((alphaCount + digitCount) / totalChars > 0.5) return false;
    return true;
  }

  // Lines with excessive punctuation/special chars (scrambled OCR)
  if (punctCount / totalChars > 0.15 && totalChars > 15) return true;

  // Lines that are just random single characters with spaces
  const words = trimmed.split(/\s+/);
  if (words.length >= 3) {
    const singleCharWords = words.filter(w => w.length === 1 && !/[aAiI0-9]/.test(w)).length;
    if (singleCharWords / words.length > 0.6) return true;
  }

  // KEY CHECK: Count "real word" tokens — sequences of 3+ consecutive alpha chars
  // that look like plausible English. If the line lacks these, it's garbled.
  const realWordTokens = trimmed.match(/[a-zA-Z]{3,}/g) || [];
  const totalNonSpace = trimmed.replace(/\s/g, '').length;
  if (totalNonSpace >= 6) {
    const realWordChars = realWordTokens.reduce((sum, w) => sum + w.length, 0);
    // If less than 50% of non-space chars form real word tokens, it's likely garbled
    if (realWordChars / totalNonSpace < 0.5) return true;

    // Also check if "words" have scrambled patterns (mixed digits+alpha, weird case)
    let scrambledCount = 0;
    for (const token of realWordTokens) {
      // Excessive case transitions in a word (like "FRopirfswitntRe", "iCRLofe")
      let caseSwitches = 0;
      for (let ci = 1; ci < token.length; ci++) {
        if (/[a-z]/.test(token[ci - 1]) && /[A-Z]/.test(token[ci])) caseSwitches++;
      }
      if (caseSwitches >= 3) scrambledCount++;
      // 5+ consonants in a row (not English)
      else if (/[bcdfghjklmnpqrstvwxyz]{5,}/i.test(token) && token.length > 5) scrambledCount++;
    }
    if (realWordTokens.length > 0 && scrambledCount / realWordTokens.length > 0.5) return true;
  }

  // Unicode garbage patterns
  const weirdUnicodeCount = (trimmed.match(/[âœ✶✷✸✹✺✻✼✽✾✿❀❁❂❃❄❅❆❇❈❉❊❋]/g) || []).length;
  if (weirdUnicodeCount > 3) return true;

  // Zapf Dingbats
  const zapfCount = (trimmed.match(/[✂✄☎✆✝✞✟✠✡✢✣✤✥✦✧★✩✪✫✬✭✮✯✰✱✲✳✴✵✡✒✏✎✍✌✋✊☛☞☜☝☟✁✃✅✈✉✑✓✔✕✖✗✘✙✚✛✜]/g) || []).length;
  if (zapfCount > 2) return true;

  // Lines like "C K" or "CK" (PDF header artifacts)
  if (/^[A-Z]\s+[A-Z]$/.test(trimmed) || /^[A-Z]{1,2}$/.test(trimmed)) return true;

  // Lines with lots of random brackets, equals, pipes
  const bracketCount = (trimmed.match(/[\[\]{}()=|]/g) || []).length;
  if (bracketCount > 5 && bracketCount / totalChars > 0.1) return true;

  // Detect words with digits mixed into alpha (like "2aNaii", "g4tI", "oF1Fy")
  const mixedWords = words.filter(w => /[a-zA-Z]/.test(w) && /\d/.test(w) && w.length >= 3);
  if (mixedWords.length >= 2) return true;
  if (mixedWords.length >= 1 && words.length <= 4) return true;

  // Short lines (<30 chars) that don't contain a real English word are likely garbage
  if (totalChars < 30) {
    const hasRealWord = realWordTokens.some(w => {
      // Must be 3+ chars and look like a real word (not random caps)
      if (w.length < 3) return false;
      // All lowercase or first-letter cap = likely real
      if (/^[a-z]+$/.test(w) || /^[A-Z][a-z]+$/.test(w)) return true;
      // All caps short words are OK (acronyms like THE, AND)
      if (/^[A-Z]+$/.test(w) && w.length <= 5) return true;
      // Common short English words
      const lower = w.toLowerCase();
      const commonWords = ['the','and','for','are','but','not','you','all','can','had','her','was','one','our','out','has','his','how','its','may','new','now','old','see','way','who','did','get','let','say','she','too','use','with','this','that','have','from','they','been','call','come','each','make','like','long','look','many','some','them','then','what','when','will','into','just','also','back','much','most','very','after','other','about','could','their','which','would','these','first','being','those','where','before','should','between','through','because','people','between'];
      return commonWords.includes(lower);
    });
    if (!hasRealWord && totalChars > 3) return true;
  }

  return false;
}

function fixSpacedLetters(text) {
  // Fix spaced-out letters like "c o nc e rning" → "concerning"
  // Pattern: single letters separated by spaces, where joining them makes real words
  // Only fix lines where most words are 1-2 chars (indicating letter-spacing issue)
  const lines = text.split('\n');
  const result = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) { result.push(line); continue; }

    const words = trimmed.split(/\s+/);
    const shortWords = words.filter(w => w.length <= 2).length;

    // If >60% of words are 1-2 chars and line has many words, it's likely spaced-out text
    if (words.length >= 5 && shortWords / words.length > 0.6) {
      // Join all single letters together, keep longer words
      let fixed = '';
      let i = 0;
      while (i < words.length) {
        if (words[i].length <= 2) {
          // Accumulate consecutive short segments
          let chunk = words[i];
          while (i + 1 < words.length && words[i + 1].length <= 2) {
            i++;
            chunk += words[i];
          }
          fixed += (fixed ? ' ' : '') + chunk;
        } else {
          fixed += (fixed ? ' ' : '') + words[i];
        }
        i++;
      }
      result.push(fixed);
    } else {
      result.push(line);
    }
  }

  return result.join('\n');
}

function removeRepetitiveHeaders(text) {
  // Detect and remove lines that repeat identically more than 3 times
  const lines = text.split('\n');
  const lineCounts = {};
  for (const line of lines) {
    const t = line.trim();
    if (t.length >= 3 && t.length <= 50) {
      lineCounts[t] = (lineCounts[t] || 0) + 1;
    }
  }

  // Find headers that repeat too many times (likely page headers/footers)
  const repetitiveHeaders = new Set();
  for (const [line, count] of Object.entries(lineCounts)) {
    if (count > 5) repetitiveHeaders.add(line);
  }

  if (repetitiveHeaders.size === 0) return text;

  return lines.filter(l => !repetitiveHeaders.has(l.trim())).join('\n');
}

function cleanText(rawText) {
  // Fix common mojibake
  let text = rawText;
  text = text.replace(/â€™/g, "'");
  text = text.replace(/â€˜/g, "'");
  text = text.replace(/â€œ/g, '"');
  text = text.replace(/â€\u009d/g, '"');
  text = text.replace(/â€"/g, '—');
  text = text.replace(/â€"/g, '–');
  text = text.replace(/Â©/g, '©');
  text = text.replace(/Â/g, '');
  text = text.replace(/Ã©/g, 'é');
  text = text.replace(/Ã¨/g, 'è');
  text = text.replace(/Ã¼/g, 'ü');
  text = text.replace(/Ã¶/g, 'ö');
  text = text.replace(/Ã¤/g, 'ä');
  text = text.replace(/Ã±/g, 'ñ');
  text = text.replace(/ï¬/g, 'fi');
  text = text.replace(/ï¬‚/g, 'fl');

  // Split into lines and filter garbled ones
  const lines = text.split('\n');
  const cleanLines = [];
  let consecutiveBlank = 0;

  for (const line of lines) {
    if (isGarbledLine(line)) continue;

    // Don't allow more than 2 consecutive blank lines
    if (line.trim() === '') {
      consecutiveBlank++;
      if (consecutiveBlank <= 2) cleanLines.push(line);
      continue;
    }
    consecutiveBlank = 0;
    cleanLines.push(line);
  }

  let cleaned = cleanLines.join('\n');

  // Fix split words across lines
  cleaned = cleaned.replace(/([A-Z])\n([A-Z]{2,})/g, '$1$2');
  cleaned = cleaned.replace(/([a-z])-\n([a-z])/g, '$1$2');

  // Fix common OCR number-for-letter substitutions
  cleaned = cleaned.replace(/\b1n\b/g, 'in');
  cleaned = cleaned.replace(/\b1s\b/g, 'is');
  cleaned = cleaned.replace(/\b1t\b/g, 'it');
  cleaned = cleaned.replace(/\btbe\b/g, 'the');
  cleaned = cleaned.replace(/\bwbich\b/g, 'which');
  cleaned = cleaned.replace(/\btbat\b/g, 'that');
  cleaned = cleaned.replace(/\btbe\b/g, 'the');
  cleaned = cleaned.replace(/\bwbere\b/g, 'where');
  cleaned = cleaned.replace(/\btbey\b/g, 'they');
  cleaned = cleaned.replace(/\btbeir\b/g, 'their');
  cleaned = cleaned.replace(/\btbis\b/g, 'this');
  cleaned = cleaned.replace(/\bcoms\b/g, 'coins');
  cleaned = cleaned.replace(/\bâ€˜/g, "'");
  cleaned = cleaned.replace(/â€™/g, "'");

  // Fix spaced-out letters (PDF extraction artifact)
  cleaned = fixSpacedLetters(cleaned);

  // Remove repetitive page headers/footers
  cleaned = removeRepetitiveHeaders(cleaned);

  // Collapse multiple spaces
  cleaned = cleaned.replace(/[ \t]{2,}/g, ' ');

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
    /^\s*C\s+K\s*$/gm,
  ];
  for (const p of noisePatterns) {
    cleaned = cleaned.replace(p, '');
  }

  // Remove bare page numbers
  cleaned = cleaned.replace(/\n\s*\d{1,4}\s*\n/g, '\n');

  // Remove "... " (ellipsis followed by page number inside TOC)
  cleaned = cleaned.replace(/\.{3,}\s*\d+/g, '');

  // Collapse excessive blank lines again after cleanup
  cleaned = cleaned.replace(/\n{4,}/g, '\n\n\n');

  // PARAGRAPH-LEVEL CLEANING: Check each paragraph block for quality
  const paragraphs = cleaned.split(/\n\n+/);
  const goodParagraphs = [];
  for (const para of paragraphs) {
    const lines = para.split('\n').map(l => l.trim()).filter(l => l.length > 0);
    if (lines.length === 0) continue;

    const paraText = lines.join(' ');
    const paraAlpha = (paraText.match(/[a-zA-Z]/g) || []).length;
    const paraTotal = paraText.replace(/\s/g, '').length;
    
    if (paraTotal < 5) continue; // Skip tiny fragments
    
    // Check paragraph quality: does it contain real readable sentences?
    const paraWords = paraText.split(/\s+/);
    const realWords = paraWords.filter(w => {
      const clean = w.replace(/[^a-zA-Z]/g, '');
      if (clean.length < 3) return false;
      // Check for random case transitions (garbled OCR)
      let caseSwitches = 0;
      for (let i = 1; i < clean.length; i++) {
        if (/[a-z]/.test(clean[i-1]) && /[A-Z]/.test(clean[i])) caseSwitches++;
      }
      if (caseSwitches >= 2 && clean.length > 4) return false;
      // Check for 4+ consonants in a row
      if (/[bcdfghjklmnpqrstvwxyz]{4,}/i.test(clean) && clean.length > 5) return false;
      return true;
    });

    // If less than 40% of paragraph words are "real", skip it
    if (paraWords.length >= 3 && realWords.length / paraWords.length < 0.4) continue;
    // If paragraph alpha ratio is too low
    if (paraTotal > 10 && paraAlpha / paraTotal < 0.5) continue;

    goodParagraphs.push(para);
  }

  cleaned = goodParagraphs.join('\n\n');

  return cleaned.trim();
}

// ══════════════════════════════════════════
// CHAPTER SPLITTING (reused from extract_and_upload.js)
// ══════════════════════════════════════════

function splitIntoChapters(text, meta) {
  const chapters = [];

  const chapterRegex = /(?:^|\n)(?:\s*)((?:CHAPTER|Chapter|UNIT|Unit|LESSON|Lesson)\s*[\-–—:.]?\s*(\d+|[IVXLC]+|One|Two|Three|Four|Five|Six|Seven|Eight|Nine|Ten|Eleven|Twelve|Thirteen|Fourteen|Fifteen|Sixteen|Seventeen|Eighteen|Nineteen|Twenty)[^\n]*)/gi;

  const matches = [...text.matchAll(chapterRegex)];

  if (matches.length >= 2) {
    for (let i = 0; i < matches.length; i++) {
      const start = matches[i].index;
      const end = i + 1 < matches.length ? matches[i + 1].index : text.length;
      const chapterText = text.substring(start, end).trim();
      const titleLine = matches[i][1].trim();

      let chTitle = titleLine.replace(/^(CHAPTER|Chapter|UNIT|Unit|LESSON|Lesson)\s*[\-–—:.]?\s*(\d+|[IVXLC]+|[A-Za-z]+)\s*[\-–—:.]?\s*/i, '').trim();
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
    // No clear chapters — split by page boundaries or fixed size
    const PAGE_SIZE = 8000;
    const paragraphs = text.split(/\n{2,}/);
    let current = '';
    let chNum = 1;

    for (const para of paragraphs) {
      current += para + '\n\n';
      if (current.length >= PAGE_SIZE) {
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

  if (chapters.length === 0 && text.trim().length > 100) {
    chapters.push({
      chapterNumber: 1,
      chapterTitle: meta.title,
      content: text.trim(),
    });
  }

  return chapters;
}

// ══════════════════════════════════════════
// BOOK METADATA (reused from extract_and_upload.js)
// ══════════════════════════════════════════

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

  let title = fileName.replace(/\.pdf$/i, '').replace(/\.txt$/i, '')
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

// ══════════════════════════════════════════
// FIREBASE HELPERS
// ══════════════════════════════════════════

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

async function getFirebaseToken() {
  if (cachedIdToken && Date.now() < tokenExpiry - 60000) return cachedIdToken;
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}`;
  const result = await httpPost(url, { email: 'bookuploader@test.com', password: 'TempUpload2025!', returnSecureToken: true });
  if (result.error) throw new Error('Firebase auth failed: ' + (result.error.message || JSON.stringify(result.error)));
  cachedIdToken = result.idToken;
  tokenExpiry = Date.now() + 3600 * 1000;
  return cachedIdToken;
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

function httpDelete(url, idToken) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const headers = {};
    if (idToken) headers['Authorization'] = 'Bearer ' + idToken;
    const options = {
      hostname: urlObj.hostname,
      port: 443,
      path: urlObj.pathname + urlObj.search,
      method: 'DELETE',
      headers,
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve({ status: res.statusCode }));
    });
    req.on('error', reject);
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
  const idToken = await getFirebaseToken();
  const url = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/${collection}/${docId}?key=${FIREBASE_API_KEY}`;
  const fields = {};
  for (const [key, value] of Object.entries(data)) fields[key] = jsToFirestoreValue(value);
  const result = await httpPatch(url, { fields }, idToken);
  if (result.status !== 200) throw new Error(`Firestore write failed (${result.status}): ${JSON.stringify(result.body).substring(0, 300)}`);
  return result;
}

async function deleteFromFirestore(collection, docId) {
  const idToken = await getFirebaseToken();
  const url = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/${collection}/${docId}?key=${FIREBASE_API_KEY}`;
  return await httpDelete(url, idToken);
}

// ══════════════════════════════════════════
// QUALITY ASSESSMENT
// ══════════════════════════════════════════

function assessQuality(rawText, cleanedText) {
  const rawLen = rawText.length;
  const cleanLen = cleanedText.length;
  const retainedPct = rawLen > 0 ? (cleanLen / rawLen * 100).toFixed(1) : 0;
  
  const alphaCount = (cleanedText.match(/[a-zA-Z]/g) || []).length;
  const alphaRatio = cleanLen > 0 ? (alphaCount / cleanLen * 100).toFixed(1) : 0;
  
  const wordCount = cleanedText.split(/\s+/).filter(w => w.length > 0).length;

  // Common English word density check
  const COMMON_WORDS = new Set(['the','of','and','to','in','is','it','that','was','for','on','are','with','as','his','they','be','at','one','have','this','from','or','had','by','but','not','what','all','were','we','when','your','can','said','there','each','which','do','how','their','if','will','up','other','about','out','many','then','them','these','so','some','her','would','make','like','has','him','into','time','very','two','its','over','such','after','more','also','did','been','most','only','come','could','no','than','first','been','who','way','she','made','find','long','down','day','get','may','part','just','where','back','much','before','well','through','being','our','between','does','work','must','because','good','any','new','know','should','take','last','still','see','need','people','country','great','high','year','give','old','while','world','under','took','found','head','came','used','called']);
  const words = cleanedText.toLowerCase().split(/\s+/).filter(w => w.length > 0);
  const commonCount = words.filter(w => COMMON_WORDS.has(w.replace(/[^a-z]/g, ''))).length;
  const commonDensity = words.length > 0 ? (commonCount / words.length * 100).toFixed(1) : 0;
  
  // Overall readability score (0-100)
  // Files with good common word density AND good alpha ratio are readable
  const readabilityScore = Math.min(100, (parseFloat(commonDensity) * 2 + parseFloat(alphaRatio)) / 3 * 1.3).toFixed(0);
  
  return { rawLen, cleanLen, retainedPct, alphaRatio, wordCount, commonDensity, readabilityScore };
}

// ══════════════════════════════════════════
// MAIN PROCESS
// ══════════════════════════════════════════

async function main() {
  console.log('════════════════════════════════════════════');
  console.log('  📚 Clean & Re-upload Books to Firestore');
  console.log('════════════════════════════════════════════');
  if (dryRun) console.log('  🔍 DRY RUN — no uploads will be made\n');

  if (!fs.existsSync(CLEAN_DIR)) fs.mkdirSync(CLEAN_DIR, { recursive: true });

  let txtFiles = fs.readdirSync(TXT_DIR).filter(f => f.endsWith('.txt')).sort();
  if (onlyFile) {
    txtFiles = txtFiles.filter(f => f.includes(onlyFile));
    if (txtFiles.length === 0) { console.error('No file matching:', onlyFile); process.exit(1); }
  }

  console.log(`  Found ${txtFiles.length} text files\n`);

  const results = { cleaned: 0, uploaded: 0, removed: 0, failed: 0 };

  for (let i = 0; i < txtFiles.length; i++) {
    const fileName = txtFiles[i];
    const meta = detectBookMeta(fileName);
    const bookId = 'book_' + slugify(fileName.replace(/\.txt$/, ''));
    
    console.log(`\n[${i + 1}/${txtFiles.length}] ${meta.title}`);
    console.log(`  Book ID: ${bookId}`);

    try {
      const rawText = fs.readFileSync(path.join(TXT_DIR, fileName), 'utf8');
      const cleanedText = cleanText(rawText);
      const quality = assessQuality(rawText, cleanedText);

      console.log(`  Raw: ${(quality.rawLen / 1024).toFixed(0)}KB → Clean: ${(quality.cleanLen / 1024).toFixed(0)}KB (${quality.retainedPct}% retained)`);
      console.log(`  Alpha: ${quality.alphaRatio}% | Common words: ${quality.commonDensity}% | Readability: ${quality.readabilityScore} | Words: ${quality.wordCount}`);

      // Save cleaned text
      fs.writeFileSync(path.join(CLEAN_DIR, fileName), cleanedText, 'utf8');

      // QUALITY GATE: If readability score is too low or content too sparse, skip
      if (quality.cleanLen < 500 || quality.wordCount < 50) {
        console.log(`  ⚠ Content too short after cleaning — removing from Firestore`);
        if (!dryRun) {
          try {
            await deleteFromFirestore('books', bookId);
            console.log(`  🗑 Deleted book: ${bookId}`);
          } catch (e) {
            console.log(`  (book may not exist in Firestore)`);
          }
        }
        results.removed++;
        continue;
      }

      // If common word density is below 10%, the content is mostly garbled/formulas
      if (parseFloat(quality.commonDensity) < 10) {
        console.log(`  ⚠ Content too garbled (common word density: ${quality.commonDensity}%) — removing from Firestore`);
        if (!dryRun) {
          try {
            await deleteFromFirestore('books', bookId);
            console.log(`  🗑 Deleted book: ${bookId}`);
          } catch (e) {
            console.log(`  (book may not exist in Firestore)`);
          }
        }
        results.removed++;
        continue;
      }

      // Split into chapters
      const chapters = splitIntoChapters(cleanedText, meta);
      
      // PER-CHAPTER QUALITY CHECK: Remove garbled chapters
      const COMMON_WORDS = new Set(['the','of','and','to','in','is','it','that','was','for','on','are','with','as','his','they','be','at','one','have','this','from','or','had','by','but','not','what','all','were','we','when','your','can','said','there','each','which','do','how','their','if','will','up','other','about','out','many','then','them','these','so','some','her','would','make','like','has','him','into','time','very','two','its','over','such','after','more','also','did','been','most','only','come','could','no','than','first','who','way','she','made','find','long','down','day','get','may','part','where','back','much','before','well','through','being','our','between','work','new','know','take','people','because','good','any','country','great','year','old','world','called','used']);
      
      const goodChapters = [];
      let removedChapters = 0;
      for (const ch of chapters) {
        const chWords = ch.content.toLowerCase().split(/\s+/).filter(w => w.length > 0);
        if (chWords.length < 20) { removedChapters++; continue; } // Too short
        
        const chCommon = chWords.filter(w => COMMON_WORDS.has(w.replace(/[^a-z]/g, ''))).length;
        const chCommonPct = chCommon / chWords.length;
        
        // Check for real word tokens
        const chRealTokens = ch.content.match(/[a-zA-Z]{3,}/g) || [];
        const chAlpha = (ch.content.match(/[a-zA-Z]/g) || []).length;
        const chTotal = ch.content.replace(/\s/g, '').length;
        const chAlphaRatio = chTotal > 0 ? chAlpha / chTotal : 0;
        
        // Chapter passes if: common word density >18% AND alpha ratio >55%
        if (chCommonPct < 0.18 || chAlphaRatio < 0.55) {
          removedChapters++;
          continue;
        }
        
        // Also check for scrambled words in the chapter
        let scrambled = 0;
        for (const token of chRealTokens.slice(0, 200)) { // Sample first 200 tokens
          let caseSwitches = 0;
          for (let ci = 1; ci < token.length; ci++) {
            if (/[a-z]/.test(token[ci-1]) && /[A-Z]/.test(token[ci])) caseSwitches++;
          }
          if (caseSwitches >= 3) scrambled++;
          else if (/[bcdfghjklmnpqrstvwxyz]{5,}/i.test(token) && token.length > 6) scrambled++;
        }
        const sampleSize = Math.min(200, chRealTokens.length);
        if (sampleSize > 10 && scrambled / sampleSize > 0.15) {
          removedChapters++;
          continue;
        }
        
        goodChapters.push(ch);
      }
      
      // Renumber good chapters
      for (let g = 0; g < goodChapters.length; g++) {
        goodChapters[g].chapterNumber = g + 1;
      }
      
      console.log(`  → ${goodChapters.length} good chapters (${removedChapters} garbled removed)`);
      results.cleaned++;
      
      if (goodChapters.length === 0) {
        console.log(`  ⚠ No good chapters remain — removing from Firestore`);
        if (!dryRun) {
          try { await deleteFromFirestore('books', bookId); } catch(e) {}
        }
        results.removed++;
        continue;
      }

      if (dryRun) {
        // Show first chapter preview
        if (chapters.length > 0) {
          const preview = chapters[0].content.substring(0, 200).replace(/\n/g, ' ');
          console.log(`  Preview: ${preview}...`);
        }
        continue;
      }

      // Upload chapters to Firestore
      const chapterIds = [];
      for (let c = 0; c < goodChapters.length; c++) {
        const ch = goodChapters[c];
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

        process.stdout.write(`\r    Uploading: ${c + 1}/${goodChapters.length}`);
        await sleep(200);
      }
      console.log('');

      // Upload book metadata
      await writeToFirestore('books', bookId, {
        id: bookId,
        title: meta.title,
        author: meta.author,
        description: `${meta.classLevel ? meta.classLevel + ' — ' : ''}${meta.subject} textbook with ${goodChapters.length} chapters.`,
        subject: meta.subject,
        coverUrl: '',
        rating: meta.isMustRead ? 4.7 : 4.3,
        isMustRead: meta.isMustRead,
        level: meta.level,
        tags: meta.tags,
        hasContent: true,
        totalChapters: goodChapters.length,
        chapterIds: chapterIds,
      });

      console.log(`  ✓ Uploaded: ${goodChapters.length} chapters`);
      results.uploaded++;

    } catch (err) {
      console.log(`  ✗ Error: ${err.message.substring(0, 200)}`);
      results.failed++;
    }

    await sleep(300);
  }

  console.log('\n════════════════════════════════════════════');
  console.log(`  ✅ DONE`);
  console.log(`  Cleaned: ${results.cleaned} | Uploaded: ${results.uploaded} | Removed: ${results.removed} | Failed: ${results.failed}`);
  console.log('════════════════════════════════════════════');
}

main().catch(err => { console.error('Fatal:', err); process.exit(1); });
