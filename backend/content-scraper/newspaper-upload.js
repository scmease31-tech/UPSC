#!/usr/bin/env node
/**
 * Newspaper Content Upload Script
 *
 * Upload newspaper articles to Firestore from a markdown file.
 * The user creates a .md file with articles separated by `---`.
 *
 * Usage:
 *   node newspaper-upload.js path/to/newspaper.md
 *   node newspaper-upload.js path/to/newspaper.md --source "The Hindu"
 *   node newspaper-upload.js path/to/newspaper.md --date 2026-06-19
 *   node newspaper-upload.js path/to/newspaper.md --dry-run
 *
 * Markdown format:
 *   # Article Title
 *   Category: Economy
 *   Paper: GS-III
 *
 *   Article content here...
 *
 *   ---
 *
 *   # Next Article Title
 *   Category: Polity
 *   ...
 */

import fs from 'fs';
import crypto from 'crypto';
import { initFirebase, uploadArticles } from './uploader.js';

function parseArgs() {
  const args = process.argv.slice(2);
  const opts = {
    file: null,
    source: 'Newspaper',
    date: null,
    dryRun: false,
  };

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--source':
        opts.source = args[++i] || 'Newspaper';
        break;
      case '--date':
        opts.date = args[++i];
        break;
      case '--dry-run':
        opts.dryRun = true;
        break;
      default:
        if (!args[i].startsWith('--')) opts.file = args[i];
    }
  }

  if (!opts.date) {
    const now = new Date();
    const istOffset = 5.5 * 60 * 60 * 1000;
    const istNow = new Date(now.getTime() + istOffset);
    opts.date = `${istNow.getFullYear()}-${String(istNow.getMonth() + 1).padStart(2, '0')}-${String(istNow.getDate()).padStart(2, '0')}`;
  }

  return opts;
}

function parseMarkdown(content, source, dateStr) {
  const sections = content.split(/^---+$/m).filter(s => s.trim());
  const articles = [];

  for (const section of sections) {
    const lines = section.trim().split('\n');
    let title = '';
    let category = 'General';
    let gsPaper = '';
    let bodyLines = [];
    let inHeader = true;

    for (const line of lines) {
      const trimmed = line.trim();

      if (inHeader) {
        // Parse title
        if (trimmed.startsWith('# ')) {
          title = trimmed.replace(/^#+\s*/, '');
          continue;
        }
        // Parse metadata
        const catMatch = trimmed.match(/^Category:\s*(.+)/i);
        if (catMatch) { category = catMatch[1].trim(); continue; }
        const paperMatch = trimmed.match(/^Paper:\s*(.+)/i);
        if (paperMatch) { gsPaper = paperMatch[1].trim(); continue; }
        const sourceMatch = trimmed.match(/^Source:\s*(.+)/i);
        if (sourceMatch) { source = sourceMatch[1].trim(); continue; }
        // Empty line or content starts
        if (trimmed === '') continue;
        inHeader = false;
      }

      bodyLines.push(line);
    }

    const body = bodyLines.join('\n').trim();
    if (!title || body.length < 20) continue;

    // Extract key points from bullet points
    const keyPoints = body.split('\n')
      .filter(l => l.trim().match(/^[-•*]\s+/))
      .map(l => l.trim().replace(/^[-•*]\s+/, ''))
      .slice(0, 10);

    const summary = body.slice(0, 300).replace(/\s+\S*$/, '...');
    const id = crypto.createHash('md5').update(`${title.toLowerCase()}|${dateStr}|newspaper`).digest('hex').slice(0, 16);

    articles.push({
      id,
      title,
      summary,
      content: body.slice(0, 5000),
      keyPoints,
      examRelevance: 'Both',
      categoryTags: [category],
      imageUrl: '',
      publishedDate: dateStr,
      isTopNews: false,
      shortNotes: keyPoints.slice(0, 5),
      newspaper: source,
      upscPaper: gsPaper,
      relatedTopics: [category],
      analysisNote: '',
      mnemonic: '',
      flowchartSteps: [],
      syllabusMapping: gsPaper ? `${gsPaper} > ${category}` : '',
      previousYearQs: [],
      editorialOpinion: '',
      constitutionalBasis: '',
      governmentScheme: '',
      sourceUrl: '',
      keyTerms: {},
      answerFramework: '',
    });
  }

  return articles;
}

async function main() {
  const opts = parseArgs();

  if (!opts.file) {
    console.log(`
Usage: node newspaper-upload.js <file.md> [options]

Options:
  --source "The Hindu"    Newspaper source name
  --date 2026-06-19       Publication date (default: today IST)
  --dry-run               Test without uploading

Markdown Format:
  # Article Title
  Category: Economy
  Paper: GS-III

  Article content here with bullet points...
  - Key point 1
  - Key point 2

  ---

  # Next Article Title
  Category: Polity
  ...
`);
    process.exit(1);
  }

  if (!fs.existsSync(opts.file)) {
    console.error(`File not found: ${opts.file}`);
    process.exit(1);
  }

  const content = fs.readFileSync(opts.file, 'utf-8');
  const articles = parseMarkdown(content, opts.source, opts.date);

  console.log(`Parsed ${articles.length} articles from ${opts.file}`);
  console.log(`Source: ${opts.source} | Date: ${opts.date}`);

  if (articles.length === 0) {
    console.log('No articles found in file. Check the markdown format.');
    process.exit(0);
  }

  if (!opts.dryRun) {
    initFirebase();
  }

  const stats = await uploadArticles(articles, opts.dryRun);
  console.log(`Done: Uploaded=${stats.uploaded} Skipped=${stats.skipped} Errors=${stats.errors}`);
}

main().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});
