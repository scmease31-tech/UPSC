import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

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
  const stats = { uploaded: 0, skipped: 0, errors: 0 };

  if (dryRun) {
    console.log(`[DryRun] Would upload ${articles.length} articles:`);
    for (const a of articles) {
      console.log(`  - [${a.newspaper}] ${a.title} (${a.categoryTags.join(', ')})`);
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
          console.log(`  [skip] Already exists: ${article.title.slice(0, 50)}`);
          stats.skipped++;
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
