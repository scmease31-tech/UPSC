#!/usr/bin/env node
/**
 * UPSC Content Scraper — Main Entry Point
 *
 * Scrapes daily current affairs from:
 *   1. Drishti IAS (https://www.drishtiias.com)
 *   2. Insights on India (https://www.insightsonindia.com)
 *
 * Deduplicates overlapping content, merges complementary articles,
 * and uploads to Firestore `articles` collection.
 *
 * Usage:
 *   node index.js                  # Scrape today's content
 *   node index.js --today          # Same as above
 *   node index.js --date 2026-06-19  # Scrape specific date
 *   node index.js --dry-run        # Test without uploading
 *   node index.js --days 3         # Scrape last 3 days
 */

import { scrapeDrishti, scrapeInsights } from './scrapers.js';
import { deduplicateAndMerge } from './deduplicator.js';
import { initFirebase, uploadArticles, markTopNews } from './uploader.js';

function getDateStr(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function parseArgs() {
  const args = process.argv.slice(2);
  const opts = {
    dates: [],
    dryRun: false,
  };

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--dry-run':
        opts.dryRun = true;
        break;
      case '--date':
        if (args[i + 1]) {
          opts.dates.push(args[++i]);
        }
        break;
      case '--days': {
        const days = parseInt(args[++i]) || 1;
        const now = new Date();
        for (let d = 0; d < days; d++) {
          const date = new Date(now);
          date.setDate(now.getDate() - d);
          opts.dates.push(getDateStr(date));
        }
        break;
      }
      case '--today':
      default:
        break;
    }
  }

  // Default: today
  if (opts.dates.length === 0) {
    // Use IST (UTC+5:30) for India-based content
    const now = new Date();
    const istOffset = 5.5 * 60 * 60 * 1000;
    const istNow = new Date(now.getTime() + istOffset);
    opts.dates.push(getDateStr(istNow));
  }

  return opts;
}

async function scrapeForDate(dateStr, dryRun) {
  console.log(`\n${'═'.repeat(60)}`);
  console.log(`  Scraping content for: ${dateStr}`);
  console.log(`${'═'.repeat(60)}\n`);

  // 1. Scrape both sources in parallel
  const [drishtiArticles, insightsArticles] = await Promise.all([
    scrapeDrishti(dateStr).catch(e => {
      console.error(`[Drishti] Error: ${e.message}`);
      return [];
    }),
    scrapeInsights(dateStr).catch(e => {
      console.error(`[Insights] Error: ${e.message}`);
      return [];
    }),
  ]);

  if (drishtiArticles.length === 0 && insightsArticles.length === 0) {
    console.log(`[Info] No articles found for ${dateStr} (may be Sunday/holiday)`);
    return { uploaded: 0, skipped: 0, errors: 0 };
  }

  // 2. Deduplicate and merge
  console.log('\n[Dedup] Merging overlapping content...');
  const mergedArticles = deduplicateAndMerge(drishtiArticles, insightsArticles);

  // Mark first 3 articles as top news
  for (let i = 0; i < Math.min(3, mergedArticles.length); i++) {
    mergedArticles[i].isTopNews = true;
  }

  // 3. Upload to Firestore
  console.log(`\n[Upload] Uploading ${mergedArticles.length} articles to Firestore...`);
  const stats = await uploadArticles(mergedArticles, dryRun);

  console.log(`\n[Done] ${dateStr}: Uploaded=${stats.uploaded} Skipped=${stats.skipped} Errors=${stats.errors}`);
  return stats;
}

async function main() {
  const opts = parseArgs();
  console.log('╔══════════════════════════════════════════════════════════╗');
  console.log('║        UPSC Daily Content Scraper v1.0                  ║');
  console.log('║  Sources: Drishti IAS + Insights on India               ║');
  console.log('╚══════════════════════════════════════════════════════════╝');
  console.log(`Mode: ${opts.dryRun ? 'DRY RUN (no upload)' : 'LIVE'}`);
  console.log(`Dates: ${opts.dates.join(', ')}`);

  if (!opts.dryRun) {
    initFirebase();
  }

  const totalStats = { uploaded: 0, skipped: 0, errors: 0 };

  for (const dateStr of opts.dates) {
    const stats = await scrapeForDate(dateStr, opts.dryRun);
    totalStats.uploaded += stats.uploaded;
    totalStats.skipped += stats.skipped;
    totalStats.errors += stats.errors;
  }

  console.log('\n' + '═'.repeat(60));
  console.log(`TOTAL: Uploaded=${totalStats.uploaded} Skipped=${totalStats.skipped} Errors=${totalStats.errors}`);
  console.log('═'.repeat(60));

  if (totalStats.errors > 0) {
    process.exit(1);
  }
}

main().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});
