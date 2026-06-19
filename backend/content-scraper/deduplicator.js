import { compareTwoStrings } from 'string-similarity';

const SIMILARITY_THRESHOLD = 0.45; // Titles with > 45% similarity are considered duplicates

/**
 * Deduplicate and merge articles from multiple sources.
 * When articles from different sources cover the same topic,
 * they are merged into a single enriched article.
 *
 * @param {Array} drishtiArticles - Articles from Drishti IAS
 * @param {Array} insightsArticles - Articles from Insights on India
 * @returns {Array} Deduplicated + merged articles
 */
export function deduplicateAndMerge(drishtiArticles, insightsArticles) {
  const merged = [];
  const usedInsights = new Set();

  for (const da of drishtiArticles) {
    let bestMatch = null;
    let bestScore = 0;

    for (let i = 0; i < insightsArticles.length; i++) {
      if (usedInsights.has(i)) continue;
      const ia = insightsArticles[i];

      // Compare titles
      const titleSim = compareTwoStrings(
        da.title.toLowerCase().replace(/[^a-z0-9\s]/g, ''),
        ia.title.toLowerCase().replace(/[^a-z0-9\s]/g, '')
      );

      // Also compare categories for context
      const catOverlap = da.categoryTags.some(t =>
        ia.categoryTags.some(it => it.toLowerCase() === t.toLowerCase())
      );

      const score = catOverlap ? titleSim + 0.1 : titleSim;

      if (score > bestScore && score >= SIMILARITY_THRESHOLD) {
        bestMatch = { article: ia, index: i };
        bestScore = score;
      }
    }

    if (bestMatch) {
      // Merge the two articles
      usedInsights.add(bestMatch.index);
      const ia = bestMatch.article;

      console.log(`  [merge] "${da.title.slice(0, 40)}..." ↔ "${ia.title.slice(0, 40)}..." (${(bestScore * 100).toFixed(0)}%)`);

      merged.push(mergeArticles(da, ia));
    } else {
      // Unique to Drishti
      merged.push(da);
    }
  }

  // Add remaining Insights articles that weren't matched
  for (let i = 0; i < insightsArticles.length; i++) {
    if (!usedInsights.has(i)) {
      merged.push(insightsArticles[i]);
    }
  }

  console.log(`[Dedup] Drishti: ${drishtiArticles.length}, Insights: ${insightsArticles.length} → Merged: ${merged.length}`);
  return merged;
}

/**
 * Merge two articles covering the same topic into one enriched article.
 * Takes the best of each field from both sources.
 */
function mergeArticles(a, b) {
  // Use the longer/richer content
  const useAContent = a.content.length >= b.content.length;
  const primary = useAContent ? a : b;
  const secondary = useAContent ? b : a;

  // Merge key points (unique)
  const allKeyPoints = [...new Set([...a.keyPoints, ...b.keyPoints])].slice(0, 15);

  // Merge categories (unique)
  const allCategories = [...new Set([...a.categoryTags, ...b.categoryTags])].slice(0, 6);

  // Merge related topics
  const allTopics = [...new Set([...a.relatedTopics, ...b.relatedTopics])].slice(0, 8);

  // Merge PYQs
  const allPYQs = [...new Set([...a.previousYearQs, ...b.previousYearQs])].slice(0, 5);

  // Merge short notes
  const allNotes = [...new Set([...a.shortNotes, ...b.shortNotes])].slice(0, 7);

  // Build merged content with both perspectives
  let mergedContent = primary.content;
  if (secondary.content.length > 200) {
    // Append unique insights from the secondary source
    const secondaryExtra = secondary.content.slice(0, 1500);
    mergedContent += `\n\n--- Additional Analysis (${secondary.newspaper}) ---\n${secondaryExtra}`;
  }

  return {
    id: primary.id,
    title: primary.title.length >= secondary.title.length ? primary.title : secondary.title,
    summary: primary.summary.length >= secondary.summary.length ? primary.summary : secondary.summary,
    content: mergedContent.slice(0, 8000),
    keyPoints: allKeyPoints,
    examRelevance: a.examRelevance === 'Both' || b.examRelevance === 'Both' ? 'Both'
      : a.examRelevance === 'Mains' || b.examRelevance === 'Mains' ? 'Mains' : 'Prelims',
    categoryTags: allCategories,
    imageUrl: a.imageUrl || b.imageUrl,
    publishedDate: a.publishedDate,
    isTopNews: a.isTopNews || b.isTopNews,
    shortNotes: allNotes,
    newspaper: `Drishti IAS + Insights on India`,
    upscPaper: a.upscPaper || b.upscPaper,
    relatedTopics: allTopics,
    analysisNote: (a.analysisNote || '') + (b.analysisNote ? `\n${b.analysisNote}` : ''),
    mnemonic: a.mnemonic || b.mnemonic,
    flowchartSteps: a.flowchartSteps.length > 0 ? a.flowchartSteps : b.flowchartSteps,
    syllabusMapping: a.syllabusMapping || b.syllabusMapping,
    previousYearQs: allPYQs,
    editorialOpinion: a.editorialOpinion || b.editorialOpinion,
    constitutionalBasis: a.constitutionalBasis || b.constitutionalBasis,
    governmentScheme: a.governmentScheme || b.governmentScheme,
    sourceUrl: `${a.sourceUrl} | ${b.sourceUrl}`,
    keyTerms: { ...b.keyTerms, ...a.keyTerms },
    answerFramework: a.answerFramework || b.answerFramework,
  };
}
