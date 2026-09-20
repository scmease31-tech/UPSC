import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { generateDailyQuiz } from './generators.js';

let db = null;

/**
 * Initialize Firebase Admin SDK.
 * Uses FIREBASE_SERVICE_ACCOUNT_B64 env var (base64-encoded service account JSON)
 * or GOOGLE_APPLICATION_CREDENTIALS file path.
 */
export function initFirebase() {
  if (db) return db;

  const b64 = process.env.FIREBASE_SERVICE_ACCOUNT_B64;
  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;

  if (b64) {
    const serviceAccount = JSON.parse(Buffer.from(b64, 'base64').toString('utf-8'));
    initializeApp({ credential: cert(serviceAccount) });
  } else if (credPath) {
    // Uses the file specified by GOOGLE_APPLICATION_CREDENTIALS
    initializeApp();
  } else {
    throw new Error(
      'Missing Firebase credentials. Set FIREBASE_SERVICE_ACCOUNT_B64 (base64) ' +
      'or GOOGLE_APPLICATION_CREDENTIALS (file path).'
    );
  }

  db = getFirestore();
  console.log('[Firebase] Initialized successfully');
  return db;
}

/**
 * Upload articles to Firestore `articles` collection.
 * Uses batch writes for efficiency. Skips existing documents (no overwrite).
 * @param {Array} articles - Array of article objects matching the Article model
 * @param {boolean} dryRun - If true, only logs without writing
 * @returns {Object} Stats: { uploaded, skipped, errors }
 */
export async function uploadArticles(articles, dryRun = false) {
  const stats = { uploaded: 0, skipped: 0, errors: 0, upgraded: 0 };

  if (dryRun) {
    console.log(`[DryRun] Would upload ${articles.length} articles:`);
    for (const a of articles) {
      console.log(`  - [${a.newspaper}] ${a.title} (${a.categoryTags.join(', ')})${a.imageUrl ? ' [img]' : ''}`);
    }
    stats.uploaded = articles.length;
    return stats;
  }

  if (!db) initFirebase();
  const collection = db.collection('articles');
  const BATCH_SIZE = 400; // Firestore limit is 500 per batch

  for (let i = 0; i < articles.length; i += BATCH_SIZE) {
    const chunk = articles.slice(i, i + BATCH_SIZE);
    const batch = db.batch();

    for (const article of chunk) {
      const docRef = collection.doc(article.id);

      try {
        // Check if document already exists
        const existing = await docRef.get();
        if (existing.exists) {
          // Re-scrapes now produce richer documents (real artwork, structured
          // body, syllabus tags). Rather than skipping outright, upgrade the
          // stored doc wherever the new version is strictly better — this is
          // what backfills thumbnails onto articles saved by older runs.
          const old = existing.data() || {};
          const patch = {};
          if (article.imageUrl && !old.imageUrl) {
            patch.imageUrl = article.imageUrl;
            patch.imageCredit = article.imageCredit || '';
            patch.imageCreditUrl = article.imageCreditUrl || '';
          }
          if ((article.content || '').length > (old.content || '').length + 200) {
            patch.content = article.content;
            patch.summary = article.summary;
            patch.keyPoints = article.keyPoints || [];
            patch.shortNotes = article.shortNotes || [];
          }
          if (article.upscPaper && !old.upscPaper) patch.upscPaper = article.upscPaper;
          if (article.sourcePaper && !old.sourcePaper) patch.sourcePaper = article.sourcePaper;
          if (article.syllabusMapping && !old.syllabusMapping) patch.syllabusMapping = article.syllabusMapping;

          if (Object.keys(patch).length > 0) {
            batch.update(docRef, { ...patch, updatedAt: FieldValue.serverTimestamp() });
            stats.upgraded++;
            console.log(`  [upgrade] ${article.title.slice(0, 55)} (${Object.keys(patch).join(', ')})`);
          } else {
            stats.skipped++;
          }
          continue;
        }

        const data = {
          title: article.title,
          summary: article.summary,
          content: article.content,
          keyPoints: article.keyPoints || [],
          examRelevance: article.examRelevance || 'Both',
          categoryTags: article.categoryTags || [],
          imageUrl: article.imageUrl || '',
          // Set when the artwork came from an openly-licensed source rather
          // than the publisher, so the app can attribute it.
          imageCredit: article.imageCredit || '',
          imageCreditUrl: article.imageCreditUrl || '',
          publishedDate: article.publishedDate, // ISO string 'YYYY-MM-DD'
          isTopNews: article.isTopNews || false,
          shortNotes: article.shortNotes || [],
          newspaper: article.newspaper || '',
          upscPaper: article.upscPaper || '',
          relatedTopics: article.relatedTopics || [],
          analysisNote: article.analysisNote || '',
          mnemonic: article.mnemonic || '',
          flowchartSteps: article.flowchartSteps || [],
          syllabusMapping: article.syllabusMapping || '',
          previousYearQs: article.previousYearQs || [],
          editorialOpinion: article.editorialOpinion || '',
          constitutionalBasis: article.constitutionalBasis || '',
          governmentScheme: article.governmentScheme || '',
          sourceUrl: article.sourceUrl || '',
          sourcePaper: article.sourcePaper || '',
          keyTerms: article.keyTerms || {},
          answerFramework: article.answerFramework || '',
          // Metadata
          createdAt: FieldValue.serverTimestamp(),
          scrapedFrom: article.newspaper || 'Unknown',
        };

        batch.set(docRef, data);
        stats.uploaded++;
        console.log(`  [add] ${article.title.slice(0, 60)} [${article.newspaper}]`);
      } catch (e) {
        console.error(`  [err] ${article.title}: ${e.message}`);
        stats.errors++;
      }
    }

    try {
      await batch.commit();
    } catch (e) {
      console.error(`[Firebase] Batch commit failed: ${e.message}`);
      stats.errors += chunk.length;
    }
  }

  return stats;
}

/**
 * Generic dedup-aware upload for a Firestore collection.
 * Skips documents whose id already exists (no overwrite), batches writes,
 * and stamps a server timestamp. Used for vocabulary / flashcards / govtSchemes.
 *
 * @param {string} collectionName - Target Firestore collection
 * @param {Array<Object>} docs - Docs to write; each MUST have a stable `id`
 * @param {boolean} dryRun - If true, only logs
 * @param {string} labelField - Field used for human-readable log lines
 * @returns {Object} Stats: { uploaded, skipped, errors }
 */
export async function uploadToCollection(collectionName, docs, dryRun = false, labelField = 'title') {
  const stats = { uploaded: 0, skipped: 0, errors: 0 };

  if (!docs || docs.length === 0) {
    console.log(`  [${collectionName}] Nothing to upload`);
    return stats;
  }

  if (dryRun) {
    console.log(`[DryRun] Would upload ${docs.length} docs to '${collectionName}':`);
    for (const d of docs.slice(0, 20)) {
      console.log(`  - ${String(d[labelField] || d.id).slice(0, 70)}`);
    }
    if (docs.length > 20) console.log(`  ...and ${docs.length - 20} more`);
    stats.uploaded = docs.length;
    return stats;
  }

  if (!db) initFirebase();
  const collection = db.collection(collectionName);
  const BATCH_SIZE = 400;

  for (let i = 0; i < docs.length; i += BATCH_SIZE) {
    const chunk = docs.slice(i, i + BATCH_SIZE);
    const batch = db.batch();

    for (const doc of chunk) {
      if (!doc.id) {
        console.error(`  [err] ${collectionName}: doc missing id`);
        stats.errors++;
        continue;
      }
      const docRef = collection.doc(doc.id);
      try {
        const existing = await docRef.get();
        if (existing.exists) {
          stats.skipped++;
          continue;
        }
        const { id, ...data } = doc;
        batch.set(docRef, { ...data, createdAt: FieldValue.serverTimestamp() });
        stats.uploaded++;
        console.log(`  [add] ${collectionName}: ${String(doc[labelField] || id).slice(0, 60)}`);
      } catch (e) {
        console.error(`  [err] ${collectionName}/${doc.id}: ${e.message}`);
        stats.errors++;
      }
    }

    try {
      await batch.commit();
    } catch (e) {
      console.error(`[Firebase] Batch commit failed for ${collectionName}: ${e.message}`);
      stats.errors += chunk.length;
    }
  }

  return stats;
}

/** Upload derived vocabulary docs to the `vocabulary` collection. */
export function uploadVocabulary(docs, dryRun = false) {
  return uploadToCollection('vocabulary', docs, dryRun, 'word');
}

/** Upload derived flashcard docs to the `flashcards` collection. */
export function uploadFlashcards(docs, dryRun = false) {
  return uploadToCollection('flashcards', docs, dryRun, 'front');
}

/** Upload derived scheme docs to the `govtSchemes` collection. */
export function uploadSchemes(docs, dryRun = false) {
  return uploadToCollection('govtSchemes', docs, dryRun, 'name');
}

/**
 * Upload key-fact docs to the `dailyFacts` collection, which the "UPSC Must
 * Know" screen merges with its built-in bank. Nothing wrote this collection
 * before, so the screen only ever showed its static content.
 */
export function uploadKeyFacts(docs, dryRun = false) {
  return uploadToCollection('dailyFacts', docs, dryRun, 'title');
}

/**
 * Upload previous-year question docs to the `pyqs` collection.
 * These come from the PYQ block Drishti appends to most daily articles, so the
 * PYQ tab keeps growing with genuine questions instead of a frozen list.
 */
export function uploadPyqs(docs, dryRun = false) {
  return uploadToCollection('pyqs', docs, dryRun, 'question');
}

/** Upsert one date's quiz bundle and its individual topic-question documents. */
export async function uploadDailyQuiz(dateStr, questions, dryRun = false) {
  const stats = { uploaded: 0, skipped: 0, errors: 0 };
  if (!questions?.length) return stats;
  if (dryRun) {
    console.log(`[DryRun] Would upsert dailyQuizzes/${dateStr} with ${questions.length} questions`);
    stats.uploaded = questions.length;
    return stats;
  }
  if (!db) initFirebase();

  try {
    const batch = db.batch();
    const bundleRef = db.collection('dailyQuizzes').doc(dateStr);
    batch.set(bundleRef, {
      date: dateStr,
      questionCount: questions.length,
      articleIds: [...new Set(questions.map((q) => q.articleRef).filter(Boolean))],
      questions: questions.map(({ id, ...question }) => ({ id, ...question })),
      generatedAt: FieldValue.serverTimestamp(),
    });
    for (const question of questions) {
      const { id, ...data } = question;
      batch.set(db.collection('quizQuestions').doc(id), {
        ...data,
        dailyQuizDate: dateStr,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    stats.uploaded = questions.length;
    console.log(`  [upsert] dailyQuizzes/${dateStr}: ${questions.length} questions`);
  } catch (error) {
    stats.errors = questions.length;
    console.error(`  [err] dailyQuizzes/${dateStr}: ${error.message}`);
  }
  return stats;
}

function dateKey(date) {
  return date.toISOString().slice(0, 10);
}

function periodBounds(dateStr, period) {
  const end = new Date(`${dateStr}T00:00:00Z`);
  if (period === 'weekly') {
    const start = new Date(end);
    const mondayOffset = (start.getUTCDay() + 6) % 7;
    start.setUTCDate(start.getUTCDate() - mondayOffset);
    return { start: dateKey(start), end: dateKey(end), id: `week_${dateKey(start)}` };
  }
  const start = new Date(Date.UTC(end.getUTCFullYear(), end.getUTCMonth(), 1));
  return {
    start: dateKey(start),
    end: dateKey(end),
    id: `month_${end.getUTCFullYear()}-${String(end.getUTCMonth() + 1).padStart(2, '0')}`,
  };
}

/** Rebuild current week and month summaries from the canonical articles store. */
export async function rebuildRoundups(dateStr, dryRun = false) {
  if (dryRun) {
    console.log(`[DryRun] Would rebuild weekly/monthly roundups ending ${dateStr}`);
    return { uploaded: 2, skipped: 0, errors: 0 };
  }
  if (!db) initFirebase();
  const stats = { uploaded: 0, skipped: 0, errors: 0 };

  for (const period of ['weekly', 'monthly']) {
    const bounds = periodBounds(dateStr, period);
    try {
      const snapshot = await db.collection('articles')
        .where('publishedDate', '>=', bounds.start)
        .where('publishedDate', '<=', bounds.end)
        .get();
      const articles = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }))
        .sort((a, b) => String(b.publishedDate).localeCompare(String(a.publishedDate)));
      const categoryCounts = {};
      for (const article of articles) {
        const category = primaryCategory(article);
        categoryCounts[category] = (categoryCounts[category] || 0) + 1;
      }
      const keyStories = articles.slice(0, 24).map((article) => ({
        id: article.id,
        title: clean(article.title),
        summary: clean(article.summary),
        category: primaryCategory(article),
        newspaper: clean(article.newspaper),
        publishedDate: clean(article.publishedDate),
        upscPaper: clean(article.upscPaper),
      }));
      const reviewQuestions = generateDailyQuiz(articles, bounds.id, { limit: 10 });
      await db.collection('currentAffairsRoundups').doc(bounds.id).set({
        id: bounds.id,
        period,
        startDate: bounds.start,
        endDate: bounds.end,
        title: period === 'weekly'
          ? `Weekly Current Affairs · ${bounds.start} to ${bounds.end}`
          : `Monthly Current Affairs · ${bounds.start.slice(0, 7)}`,
        storyCount: articles.length,
        categoryCounts,
        keyStories,
        reviewQuestions: reviewQuestions.map(({ id, ...question }) => ({ id, ...question })),
        generatedAt: FieldValue.serverTimestamp(),
      });
      stats.uploaded++;
      console.log(`  [upsert] ${bounds.id}: ${articles.length} stories, ${reviewQuestions.length} review questions`);
    } catch (error) {
      stats.errors++;
      console.error(`  [err] ${bounds.id}: ${error.message}`);
    }
  }
  return stats;
}

/**
 * Delete docs in a collection matching newspaper + publishedDate, so a re-ingest
 * cleanly REPLACES that day's content for that source instead of leaving stale
 * (e.g. previously-garbled) docs behind when their ids change. Requires the
 * collection's docs to carry `newspaper` and `publishedDate` fields.
 * @returns {Promise<number>} number of docs deleted
 */
export async function deleteBySourceDate(collectionName, newspaper, dateStr, dryRun = false) {
  if (dryRun || !newspaper || !dateStr) return 0;
  if (!db) initFirebase();
  const snap = await db.collection(collectionName)
    .where('newspaper', '==', newspaper)
    .where('publishedDate', '==', dateStr)
    .get();
  if (snap.empty) return 0;
  let deleted = 0;
  const docs = snap.docs;
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db.batch();
    for (const d of docs.slice(i, i + 400)) { batch.delete(d.ref); deleted++; }
    await batch.commit();
  }
  console.log(`  [clean] removed ${deleted} stale '${newspaper}' doc(s) from ${collectionName} for ${dateStr}`);
  return deleted;
}

/**
 * One-time maintenance: scan a collection and delete docs whose text fields
 * still contain extraction garbage — stray control bytes, running page ids
 * (e2145468...), or common dropped-ligature forms (ination, ocials, decit...).
 * Safe for the fully-derived `articles`/`flashcards` collections.
 * @returns {Promise<number>} number of docs deleted
 */
const BROKEN_RE = /[\u0001-\u0008\u000e-\u001f\u0080-\u009f]|e\d{7,}|\b(?:ination|inations|ocials?|ocers?|decits?|dierent|dierences?|claried|conrm|conrmed|conrmation|signicant|signicantly|reects?|conicts?|eective|dicult|diculty|staer|armation)\b/i;

export async function sweepBrokenDocs(collectionName, textFields, dryRun = false) {
  if (!db) initFirebase();
  const snap = await db.collection(collectionName).get();
  const toDelete = [];
  snap.forEach((doc) => {
    const data = doc.data();
    const text = textFields.map((f) => String(data[f] || '')).join(' \u0001 ');
    // Reset lastIndex not needed (no /g); test each field's combined text.
    if (BROKEN_RE.test(text)) toDelete.push(doc.ref);
  });
  if (toDelete.length === 0) {
    console.log(`  [sweep] ${collectionName}: no broken docs found`);
    return 0;
  }
  if (dryRun) {
    console.log(`  [sweep] ${collectionName}: would delete ${toDelete.length} broken doc(s)`);
    return toDelete.length;
  }
  let deleted = 0;
  for (let i = 0; i < toDelete.length; i += 400) {
    const batch = db.batch();
    for (const ref of toDelete.slice(i, i + 400)) { batch.delete(ref); deleted++; }
    await batch.commit();
  }
  console.log(`  [sweep] ${collectionName}: deleted ${deleted} broken doc(s)`);
  return deleted;
}

/**
 * Mark today's top articles (most recent, first from each source).
 */
export async function markTopNews(dateStr, count = 3) {
  if (!db) initFirebase();
  const collection = db.collection('articles');

  const snapshot = await collection
    .where('publishedDate', '==', dateStr)
    .limit(count)
    .get();

  const batch = db.batch();
  snapshot.forEach(doc => {
    batch.update(doc.ref, { isTopNews: true });
  });

  if (!snapshot.empty) {
    await batch.commit();
    console.log(`[Firebase] Marked ${snapshot.size} articles as top news for ${dateStr}`);
  }
}
