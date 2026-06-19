import * as cheerio from 'cheerio';
import crypto from 'crypto';

// ─── CONSTANTS ───────────────────────────────────────────────────────────
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
const FETCH_TIMEOUT = 30_000;

const CATEGORY_MAP = {
  'polity':                'Polity',
  'governance':            'Governance',
  'economy':               'Economy',
  'environment':           'Environment',
  'science and technology': 'Science & Technology',
  'science & technology':  'Science & Technology',
  'international relations': 'International Relations',
  'international':         'International Relations',
  'history':               'History',
  'geography':             'Geography',
  'security':              'Security',
  'social issues':         'Social Issues',
  'art & culture':         'History',
  'art and culture':       'History',
  'ethics':                'Ethics',
  'miscellaneous':         'General',
  'mapping':               'Geography',
  'cme':                   'General',
};

const GS_PAPER_MAP = {
  'gs paper - 1': 'GS-I',   'gs-paper-1': 'GS-I',   'gs paper 1': 'GS-I',   'gs 1': 'GS-I',
  'gs paper - 2': 'GS-II',  'gs-paper-2': 'GS-II',  'gs paper 2': 'GS-II',  'gs 2': 'GS-II',
  'gs paper - 3': 'GS-III', 'gs-paper-3': 'GS-III', 'gs paper 3': 'GS-III', 'gs 3': 'GS-III',
  'gs paper - 4': 'GS-IV',  'gs-paper-4': 'GS-IV',  'gs paper 4': 'GS-IV',  'gs 4': 'GS-IV',
};

// ─── HELPERS ─────────────────────────────────────────────────────────────
function makeId(title, dateStr) {
  return crypto.createHash('md5').update(`${title.toLowerCase().trim()}|${dateStr}`).digest('hex').slice(0, 16);
}

function mapCategory(raw) {
  if (!raw) return 'General';
  const key = raw.toLowerCase().trim();
  return CATEGORY_MAP[key] || raw.trim();
}

function mapGsPaper(tags) {
  for (const t of tags) {
    const key = t.toLowerCase().trim();
    if (GS_PAPER_MAP[key]) return GS_PAPER_MAP[key];
  }
  return '';
}

function cleanText(text) {
  return text
    .replace(/\r\n/g, '\n')
    .replace(/[ \t]+/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function extractKeyPoints(text) {
  const points = [];
  for (const line of text.split('\n')) {
    const trimmed = line.trim();
    if ((trimmed.startsWith('■') || trimmed.startsWith('•') || trimmed.startsWith('◦') || trimmed.match(/^\d+\.\s/)) && trimmed.length > 15) {
      const cleaned = trimmed.replace(/^[■•◦]\s*/, '').replace(/^\d+\.\s*/, '').trim();
      if (cleaned.length > 10 && !points.includes(cleaned)) points.push(cleaned);
    }
  }
  return points.slice(0, 10);
}

function extractPYQs(text) {
  const pyqs = [];
  const matches = text.match(/(?:UPSC|Prelims|Mains)\s*(?:\d{4}|\().*?(?:\n|$)/gi);
  if (matches) {
    for (const m of matches) {
      const cleaned = m.trim();
      if (cleaned.length > 15 && cleaned.length < 300) pyqs.push(cleaned);
    }
  }
  return pyqs.slice(0, 5);
}

async function fetchPage(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT);
  try {
    const resp = await fetch(url, {
      headers: { 'User-Agent': UA, 'Accept': 'text/html', 'Accept-Language': 'en-US,en;q=0.9' },
      signal: controller.signal,
    });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    return await resp.text();
  } finally {
    clearTimeout(timeout);
  }
}

function htmlToText(html) {
  let clean = html
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<nav[\s\S]*?<\/nav>/gi, '')
    .replace(/<footer[\s\S]*?<\/footer>/gi, '');
  clean = clean.replace(/<\/?(p|div|br|h[1-6]|li|ul|ol|tr|section|article|blockquote)[^>]*>/gi, '\n');
  clean = clean.replace(/<[^>]+>/g, ' ');
  clean = clean.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#039;/g, "'").replace(/&nbsp;/g, ' ');
  return cleanText(clean);
}

function extractImages(html) {
  const images = [];
  try {
    const $ = cheerio.load(html, { xml: false });
    $('img').each((_, el) => {
      const src = $(el).attr('src') || $(el).attr('data-src') || '';
      const alt = $(el).attr('alt') || '';
      if (src && src.startsWith('http') && !src.includes('logo') && !src.includes('icon')
          && !src.includes('avatar') && !src.includes('1x1')
          && (src.includes('.png') || src.includes('.jpg') || src.includes('.jpeg') || src.includes('.webp'))) {
        images.push({ src, alt });
      }
    });
  } catch (e) { /* ignore cheerio errors */ }
  return images;
}

// ─── DRISHTI IAS SCRAPER ─────────────────────────────────────────────────
export async function scrapeDrishti(dateStr) {
  const [y, m, d] = dateStr.split('-');
  const url = `https://www.drishtiias.com/current-affairs-news-analysis-editorials/news-analysis/${d}-${m}-${y}`;
  console.log(`[Drishti] Fetching: ${url}`);

  let html;
  try { html = await fetchPage(url); } catch (e) { console.error(`[Drishti] ${e.message}`); return []; }

  const articles = [];
  const fullText = htmlToText(html);
  const images = extractImages(html);

  // Find article links pointing to /daily-updates/
  const articleUrls = [];
  const linkRegex = /href="(https?:\/\/www\.drishtiias\.com\/daily-updates\/daily-news-(?:analysis|editorials)\/[^"]+)"[^>]*>([^<]+)</gi;
  let match;
  while ((match = linkRegex.exec(html)) !== null) {
    const title = match[2].trim();
    if (title.length > 10 && !articleUrls.some(a => a.title === title)) {
      articleUrls.push({ title, href: match[1] });
    }
  }

  if (articleUrls.length === 0) {
    console.log('[Drishti] No article links found, trying text-based extraction');
    // Fall back to scanning for Source: patterns
    const sourcePattern = /Source:\s*\w+[\s\S]*?(?=Source:\s*\w+|Tags:|$)/gi;
    // Just use headline patterns
  }

  // For each found article, extract its section from the page text
  for (let i = 0; i < articleUrls.length; i++) {
    const { title, href } = articleUrls[i];
    const titleIdx = fullText.indexOf(title);
    if (titleIdx < 0) continue;

    let endIdx = fullText.length;
    for (let j = i + 1; j < articleUrls.length; j++) {
      const nextIdx = fullText.indexOf(articleUrls[j].title, titleIdx + title.length);
      if (nextIdx > titleIdx) { endIdx = nextIdx; break; }
    }

    const section = fullText.slice(titleIdx, Math.min(endIdx, titleIdx + 5000));
    if (section.length < 80 || section.includes('Reach Us') || section.includes('Copyright ©')) continue;

    // Extract tags
    const tags = [];
    const tagMatch = section.match(/Tags:\s*([\s\S]*?)(?:\n\s*\n|Source:|For Prelims:|$)/i);
    if (tagMatch) {
      tagMatch[1].split(/[\n,\[\]]/).forEach(t => {
        const tag = t.trim();
        if (tag.length > 2 && tag.length < 50) tags.push(tag);
      });
    }

    const sourceMatch = section.match(/Source:\s*(\w+)/i);
    const gsPaper = mapGsPaper(tags);
    const category = tags.map(t => mapCategory(t)).find(c => c !== 'General') || 'General';
    const keyPoints = extractKeyPoints(section);
    const pyqs = extractPYQs(section);
    const mainsQ = section.match(/Drishti Mains Question:?\s*([\s\S]*?)(?:\n\n|Frequently|$)/i);

    const cleanedContent = cleanText(section).slice(0, 5000);
    const summary = cleanedContent.slice(title.length, title.length + 300).trim().replace(/\s+\S*$/, '...');

    let imageUrl = '';
    const titleWords = title.toLowerCase().split(/\s+/).slice(0, 3);
    for (const img of images) {
      if (titleWords.some(w => w.length > 3 && img.alt.toLowerCase().includes(w))) { imageUrl = img.src; break; }
    }

    articles.push({
      id: makeId(title, dateStr),
      title,
      summary: summary || cleanedContent.slice(0, 300) + '...',
      content: cleanedContent,
      keyPoints,
      examRelevance: gsPaper ? 'Mains' : 'Both',
      categoryTags: [category, ...tags.filter(t => !t.toLowerCase().includes('gs paper') && !t.toLowerCase().includes('rapid fire'))].filter((v, i, a) => a.indexOf(v) === i).slice(0, 5),
      imageUrl,
      publishedDate: dateStr,
      isTopNews: false,
      shortNotes: keyPoints.slice(0, 5),
      newspaper: 'Drishti IAS',
      upscPaper: gsPaper,
      relatedTopics: tags.filter(t => !t.toLowerCase().includes('gs paper')).slice(0, 8),
      analysisNote: '',
      mnemonic: '',
      flowchartSteps: [],
      syllabusMapping: gsPaper ? `${gsPaper} > ${category}` : '',
      previousYearQs: pyqs,
      editorialOpinion: '',
      constitutionalBasis: '',
      governmentScheme: '',
      sourceUrl: href || url,
      keyTerms: {},
      answerFramework: mainsQ ? mainsQ[1].trim().slice(0, 300) : '',
    });
  }

  console.log(`[Drishti] Extracted ${articles.length} articles for ${dateStr}`);
  return articles;
}

// ─── INSIGHTS ON INDIA SCRAPER ───────────────────────────────────────────
export async function scrapeInsights(dateStr) {
  const [y, m, d] = dateStr.split('-');
  const months = ['january','february','march','april','may','june','july','august','september','october','november','december'];
  const monthName = months[parseInt(m) - 1];
  const url = `https://www.insightsonindia.com/${y}/${m}/${d}/upsc-current-affairs-${parseInt(d)}-${monthName}-${y}/`;
  console.log(`[Insights] Fetching: ${url}`);

  let html;
  try { html = await fetchPage(url); } catch (e) { console.error(`[Insights] ${e.message}`); return []; }

  const articles = [];
  const fullText = htmlToText(html);
  const images = extractImages(html);
  const lines = fullText.split('\n');

  // Find article starts: lines followed by "Source:" and "Subject:" within next 5 lines
  const articleStarts = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.length < 10 || line.length > 120) continue;

    const nextFew = lines.slice(i + 1, i + 8).join('\n');
    if (nextFew.match(/Source:\s*\w/i) && nextFew.match(/Subject:\s*\w/i)) {
      if (!line.includes('UPSC CURRENT AFFAIRS') && !line.includes('Related Articles')
          && !line.includes('QUIZ') && !line.includes('How to Use')
          && !line.includes('Frequently Asked') && !line.includes('About Us')
          && !line.includes('Popular Courses') && !line.includes('Insights IAS')
          && !line.includes('Additional Links') && !line.includes('Copyright')
          && !line.includes('RECENT UPDATES') && !line.includes('QUICK RESOURCES')) {
        // Avoid duplicates
        const normalized = line.toLowerCase().replace(/[^a-z0-9]/g, '');
        if (!articleStarts.some(a => a.normalized === normalized)) {
          articleStarts.push({ line: i, title: line, normalized });
        }
      }
    }
  }

  let currentGsPaper = '';

  for (let idx = 0; idx < articleStarts.length; idx++) {
    const start = articleStarts[idx];
    const endLine = articleStarts[idx + 1]?.line || Math.min(start.line + 200, lines.length);
    const section = lines.slice(start.line, endLine).join('\n');
    const title = start.title;

    if (section.length < 100) continue;

    // Check for GS PAPER markers
    for (let j = start.line - 1; j >= Math.max(0, start.line - 8); j--) {
      const prevLine = lines[j].trim().toLowerCase();
      for (const [key, val] of Object.entries(GS_PAPER_MAP)) {
        if (prevLine.includes(key.replace(/-/g, ' '))) { currentGsPaper = val; break; }
      }
      if (prevLine.includes('prelims in focus')) { currentGsPaper = ''; break; }
    }

    const gsMatch = section.match(/GS\s*PAPER\s*[-:]?\s*([1-4]|I{1,3}V?)/i);
    if (gsMatch) {
      const num = gsMatch[1].replace(/IV/i, '4').replace(/III/i, '3').replace(/II/i, '2').replace(/^I$/i, '1');
      const paperMap = { '1': 'GS-I', '2': 'GS-II', '3': 'GS-III', '4': 'GS-IV' };
      if (paperMap[num]) currentGsPaper = paperMap[num];
    }

    const sourceMatch = section.match(/Source:\s*\[?(\w+)\]?/i);
    const subjectMatch = section.match(/Subject:\s*(.+?)(?:\n|$)/i);
    const rawCategory = subjectMatch ? subjectMatch[1].trim() : '';
    const category = mapCategory(rawCategory);

    let examRelevance = 'Both';
    const lower = section.toLowerCase();
    if (lower.includes('prelims in focus')) examRelevance = 'Prelims';
    else if (lower.includes('mains') || lower.includes('editorial')) examRelevance = 'Mains';

    const keyPoints = extractKeyPoints(section);
    const pyqs = extractPYQs(section);
    const cleanedContent = cleanText(section).slice(0, 5000);
    const summary = cleanedContent.slice(0, 300).replace(/\s+\S*$/, '...');

    const wayForward = section.match(/Way Forward:?\s*([\s\S]*?)(?:Conclusion|SECURE|PRACTICE|$)/i);
    const conclusion = section.match(/Conclusion:?\s*([\s\S]*?)(?:\n\n\s*\n|SECURE|PRACTICE|GS PAPER|PRELIMS|CME|$)/i);
    const practiceQ = section.match(/SECURE ANSWER WRITING PRACTICE QUESTION\s*([\s\S]*?)(?:\n\n|GS PAPER|PRELIMS|CME|$)/i);
    if (practiceQ && practiceQ[1].trim().length > 20) pyqs.push(practiceQ[1].trim().slice(0, 300));

    let imageUrl = '';
    const titleWords = title.toLowerCase().split(/[\s\-–]+/).filter(w => w.length > 3).slice(0, 3);
    for (const img of images) {
      if (titleWords.some(w => img.alt.toLowerCase().includes(w) || img.src.toLowerCase().includes(w))) { imageUrl = img.src; break; }
    }

    articles.push({
      id: makeId(title, dateStr),
      title,
      summary,
      content: cleanedContent,
      keyPoints,
      examRelevance,
      categoryTags: category !== 'General' ? [category] : (rawCategory ? [rawCategory] : ['General']),
      imageUrl,
      publishedDate: dateStr,
      isTopNews: false,
      shortNotes: keyPoints.slice(0, 5),
      newspaper: 'Insights on India',
      upscPaper: currentGsPaper,
      relatedTopics: [rawCategory, category].filter((v, i, a) => v && a.indexOf(v) === i),
      analysisNote: wayForward ? cleanText(wayForward[1]).slice(0, 500) : '',
      mnemonic: '',
      flowchartSteps: [],
      syllabusMapping: currentGsPaper ? `${currentGsPaper} > ${category}` : '',
      previousYearQs: pyqs,
      editorialOpinion: '',
      constitutionalBasis: '',
      governmentScheme: '',
      sourceUrl: url,
      keyTerms: {},
      answerFramework: conclusion ? cleanText(conclusion[1]).slice(0, 500) : '',
    });
  }

  console.log(`[Insights] Extracted ${articles.length} articles for ${dateStr}`);
  return articles;
}
