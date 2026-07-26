import * as cheerio from 'cheerio';
import crypto from 'crypto';
import { restructure, decodeEntities } from './restructure.js';

// ─── CONSTANTS ───────────────────────────────────────────────────────────
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
const FETCH_TIMEOUT = 30_000;

/** How many article detail pages to fetch at once. */
const DETAIL_CONCURRENCY = 4;

const CATEGORY_MAP = {
  'polity':                'Polity',
  'indian polity':         'Polity',
  'governance':            'Governance',
  'government policies & interventions': 'Governance',
  'government policies and interventions': 'Governance',
  'economy':               'Economy',
  'indian economy':        'Economy',
  'environment':           'Environment',
  'biodiversity & environment': 'Environment',
  'science and technology': 'Science & Technology',
  'science & technology':  'Science & Technology',
  'biotechnology':         'Science & Technology',
  'space technology':      'Science & Technology',
  'international relations': 'International Relations',
  'international':         'International Relations',
  'history':               'History',
  'indian history':        'History',
  'modern indian history': 'History',
  'ancient indian history': 'History',
  'geography':             'Geography',
  'indian geography':      'Geography',
  'security':              'Security',
  'internal security':     'Security',
  'defence':               'Security',
  'disaster management':   'Security',
  'social issues':         'Social Issues',
  'social justice':        'Social Issues',
  'art & culture':         'History',
  'art and culture':       'History',
  'indian heritage & culture': 'History',
  'ethics':                'Ethics',
  'agriculture':           'Economy',
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

/** Short source codes used by Drishti ("Source: TH") expanded to real names. */
const SOURCE_MAP = {
  th: 'The Hindu',
  ie: 'Indian Express',
  pib: 'PIB',
  bs: 'Business Standard',
  toi: 'Times of India',
  et: 'Economic Times',
  hbl: 'Business Line',
  dte: 'Down To Earth',
  ht: 'Hindustan Times',
  livemint: 'Mint',
  mint: 'Mint',
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

/** Tag → canonical syllabus subject, or '' when the tag is not a subject. */
function canonicalSubject(raw) {
  if (!raw) return '';
  const key = raw.toLowerCase().trim();
  const mapped = CATEGORY_MAP[key];
  return mapped && mapped !== 'General' ? mapped : '';
}

/** Drishti section labels that are not topics and should never become tags. */
const JUNK_TAG = /^(rapid fire|quick facts|important facts|prelims facts|facts for prelims|mains practice|to the point|be mains ready|daily updates|news analysis|editorial|infographics?)\b/i;

function mapGsPaper(tags) {
  for (const t of tags) {
    const key = t.toLowerCase().trim();
    if (GS_PAPER_MAP[key]) return GS_PAPER_MAP[key];
  }
  return '';
}

function cleanText(text) {
  // Entities are decoded here rather than at render time — the app shows the
  // stored string verbatim, so an "&#8217;" left in place reaches the reader.
  return decodeEntities(text)
    .replace(/\r\n/g, '\n')
    .replace(/ /g, ' ')
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
      if (cleaned.length > 10 && cleaned.length < 320 && !points.includes(cleaned)) points.push(cleaned);
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

async function fetchPage(url, { retries = 2 } = {}) {
  let lastErr;
  for (let attempt = 0; attempt <= retries; attempt++) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT);
    try {
      const resp = await fetch(url, {
        headers: { 'User-Agent': UA, 'Accept': 'text/html', 'Accept-Language': 'en-US,en;q=0.9' },
        signal: controller.signal,
      });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      return await resp.text();
    } catch (e) {
      lastErr = e;
      if (attempt < retries) await new Promise((r) => setTimeout(r, 800 * (attempt + 1)));
    } finally {
      clearTimeout(timeout);
    }
  }
  throw lastErr;
}

/** Run `worker` over `items` with a bounded number of parallel tasks. */
async function mapLimit(items, limit, worker) {
  const results = new Array(items.length);
  let cursor = 0;
  const runners = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (cursor < items.length) {
      const i = cursor++;
      try {
        results[i] = await worker(items[i], i);
      } catch (e) {
        results[i] = null;
      }
    }
  });
  await Promise.all(runners);
  return results;
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

/**
 * Normalise an image URL found in scraped HTML so the app can actually load it.
 *
 * Drishti serves body images as `http://drishtiias.com/...` (plain HTTP, no
 * `www`). Android blocks cleartext HTTP by default, so those URLs silently fail
 * in the app and the card ends up with no thumbnail — upgrade them to
 * `https://www.drishtiias.com/...` and resolve protocol-relative/relative paths.
 */
function absoluteImageUrl(src, pageUrl) {
  if (!src) return '';
  let url = src.trim();
  if (url.startsWith('//')) url = `https:${url}`;
  if (url.startsWith('/')) {
    try { url = new URL(url, pageUrl).href; } catch { return ''; }
  }
  if (!/^https?:\/\//i.test(url)) return '';
  url = url.replace(/^http:\/\//i, 'https://');
  // drishtiias.com serves images only from the www host.
  url = url.replace(/^https:\/\/drishtiias\.com/i, 'https://www.drishtiias.com');
  return url;
}

/** Images that are chrome (logos, badges, ads), not article content. */
const IMAGE_BLOCKLIST = /logo|icon|avatar|1x1|badge|banner|app[-_ ]?store|play|social|whatsapp|twitter|telegram|coming%20soon|coming soon|thumbnail_contact|expand/i;

function isContentImage(url) {
  if (!url) return false;
  if (IMAGE_BLOCKLIST.test(url)) return false;
  return /\.(png|jpe?g|webp|gif)(\?|$)/i.test(url);
}

function extractImages(html, pageUrl = 'https://www.drishtiias.com/') {
  const images = [];
  try {
    const $ = cheerio.load(html, { xml: false });
    $('img').each((_, el) => {
      const raw = $(el).attr('src') || $(el).attr('data-src') || $(el).attr('data-original') || '';
      const src = absoluteImageUrl(raw, pageUrl);
      const alt = $(el).attr('alt') || '';
      if (isContentImage(src)) images.push({ src, alt });
    });
  } catch (e) { /* ignore cheerio errors */ }
  return images;
}

// ─── STRUCTURED BODY EXTRACTION ──────────────────────────────────────────
/**
 * Convert an article body element into lightly-marked plain text the app can
 * render as real sections instead of one undifferentiated wall of text:
 *
 *   "## "  section heading
 *   "### " sub-heading
 *   "• "   bullet
 *   "◦ "   nested bullet
 *
 * Everything else is a paragraph separated by a blank line.
 */
function blocksFromElement($, root) {
  const out = [];

  const push = (line) => {
    const v = cleanText(line);
    if (!v) return;
    // Collapse immediate duplicates (Drishti repeats some headings in markup).
    if (out.length && out[out.length - 1] === v) return;
    out.push(v);
  };

  const walkList = ($ul, depth) => {
    $ul.children('li').each((_, li) => {
      const $li = $(li);
      const nested = $li.children('ul,ol');
      const ownText = $li
        .clone()
        .children('ul,ol')
        .remove()
        .end()
        .text();
      push(`${depth >= 1 ? '◦' : '•'} ${ownText}`);
      nested.each((__, n) => walkList($(n), depth + 1));
    });
  };

  root.children().each((_, el) => {
    const $el = $(el);
    const tag = (el.tagName || '').toLowerCase();
    if (tag === 'script' || tag === 'style' || tag === 'iframe' || tag === 'form') return;

    if (tag === 'h1' || tag === 'h2') { push(`## ${$el.text()}`); return; }
    if (tag === 'h3' || tag === 'h4' || tag === 'h5') { push(`### ${$el.text()}`); return; }
    if (tag === 'ul' || tag === 'ol') { walkList($el, 0); return; }
    if (tag === 'table') {
      $el.find('tr').each((__, tr) => {
        const cells = $(tr).find('th,td').map((___, td) => cleanText($(td).text())).get().filter(Boolean);
        if (cells.length) push(`• ${cells.join(' — ')}`);
      });
      return;
    }
    if (tag === 'p' || tag === 'blockquote') { push($el.text()); return; }

    // Wrapper div/section: recurse so nested headings/lists keep their shape.
    const nested = blocksFromElement($, $el);
    if (nested.length) out.push(...nested);
    else push($el.text());
  });

  return out;
}

/** Join structured blocks into the string stored on the article document. */
function blocksToContent(blocks, limit = 12000) {
  const text = blocks.join('\n\n');
  if (text.length <= limit) return text;
  return `${text.slice(0, limit).replace(/\s+\S*$/, '')}…`;
}

// ─── DRISHTI PYQ EXTRACTION ──────────────────────────────────────────────
/**
 * Drishti closes most articles with a real "UPSC Civil Services Examination,
 * Previous Year Questions (PYQs)" block containing genuine Prelims MCQs (with
 * options + answer) and Mains questions with their year. Parse it into
 * structured question documents so the PYQ tab grows itself over time.
 */
export function parsePyqBlock(rawText, meta = {}) {
  const questions = [];
  if (!rawText) return questions;

  const text = rawText.replace(/ /g, ' ').replace(/[ \t]+/g, ' ');
  const startIdx = text.search(/Previous\s+Years?\s+Questions?\s*\(PYQs?\)/i);
  if (startIdx < 0) return questions;

  const block = text.slice(startIdx);
  const prelimsIdx = block.search(/\bPrelims\s*:/i);
  const mainsIdx = block.search(/\bMains\s*:/i);

  const prelimsText = prelimsIdx >= 0
    ? block.slice(prelimsIdx, mainsIdx > prelimsIdx ? mainsIdx : undefined)
    : '';
  const mainsText = mainsIdx >= 0 ? block.slice(mainsIdx) : '';

  // ── Prelims MCQs ──
  for (const chunk of prelimsText.split(/\n(?=\s*Q\.)/)) {
    const q = parsePrelimsQuestion(chunk, meta);
    if (q) questions.push(q);
  }

  // ── Mains questions ──
  for (const line of mainsText.split('\n')) {
    const m = line.match(/^\s*Q\.?\s*(.+?)\s*\((\d{4})\)\s*$/);
    if (!m) continue;
    const question = cleanText(m[1]);
    if (question.length < 25) continue;
    questions.push({
      id: makeId(`mains|${question}`, m[2]),
      type: 'mains',
      year: parseInt(m[2], 10),
      question,
      options: [],
      answer: -1,
      explanation: '',
      subject: meta.subject || 'General',
      paper: meta.gsPaper || '',
      marks: 0,
      source: 'Drishti IAS',
      sourceUrl: meta.sourceUrl || '',
      topic: meta.topic || '',
    });
  }

  return questions;
}

function parsePrelimsQuestion(chunk, meta) {
  if (!/\bQ\.?\s/.test(chunk)) return null;

  const yearMatch = chunk.match(/\((\d{4})\)/);
  const year = yearMatch ? parseInt(yearMatch[1], 10) : 0;
  if (!year || year < 1990 || year > 2100) return null;

  // Options look like "(a) 1 only".
  const optionRe = /\(([a-d])\)\s*([^\n(]{1,200})/gi;
  const options = [];
  let m;
  while ((m = optionRe.exec(chunk)) !== null) {
    const label = m[1].toLowerCase();
    const value = cleanText(m[2]);
    if (!value || value.length < 1) continue;
    const idx = label.charCodeAt(0) - 97;
    if (idx >= 0 && idx < 4 && !options[idx]) options[idx] = value;
  }

  const ansMatch = chunk.match(/\bAns\s*[:.]?\s*\(?([a-d])\)?/i);
  const answer = ansMatch ? ansMatch[1].toLowerCase().charCodeAt(0) - 97 : -1;

  // Stem = everything from "Q." up to the first option marker.
  const stemStart = chunk.search(/\bQ\.?\s/);
  const firstOpt = chunk.search(/\(a\)/i);
  let stem = chunk.slice(stemStart, firstOpt > stemStart ? firstOpt : undefined);
  stem = cleanText(stem.replace(/^\s*Q\.?\s*/, '').replace(/\bAns\s*[:.]?\s*\(?[a-d]\)?/i, ''));
  if (stem.length < 25) return null;

  const filled = [];
  for (let i = 0; i < 4; i++) if (options[i]) filled.push(options[i]);
  if (filled.length !== 4 || answer < 0) {
    // Statement-only or malformed — keep it as a reference question instead of
    // shipping a broken MCQ with missing options.
    return {
      id: makeId(`prelims-ref|${stem}`, String(year)),
      type: 'prelims',
      year,
      question: stem,
      options: [],
      answer: -1,
      explanation: '',
      subject: meta.subject || 'General',
      paper: 'Prelims GS-I',
      marks: 0,
      source: 'Drishti IAS',
      sourceUrl: meta.sourceUrl || '',
      topic: meta.topic || '',
    };
  }

  return {
    id: makeId(`prelims|${stem}`, String(year)),
    type: 'prelims',
    year,
    question: stem,
    options: filled,
    answer,
    explanation: '',
    subject: meta.subject || 'General',
    paper: 'Prelims GS-I',
    marks: 0,
    source: 'Drishti IAS',
    sourceUrl: meta.sourceUrl || '',
    topic: meta.topic || '',
  };
}

// ─── DRISHTI IAS SCRAPER ─────────────────────────────────────────────────

/** Collect the day's article URLs from a Drishti news-analysis index page. */
function drishtiArticleLinks(html) {
  const seen = new Map();
  const linkRegex = /href="(https?:\/\/www\.drishtiias\.com\/daily-updates\/daily-news-(?:analysis|editorials)\/[^"#?]+)"[^>]*>([^<]*)</gi;
  let match;
  while ((match = linkRegex.exec(html)) !== null) {
    const href = match[1];
    const title = match[2].trim();
    if (/\/hindi\//i.test(href)) continue;
    if (!seen.has(href)) seen.set(href, title);
    else if (title.length > (seen.get(href) || '').length) seen.set(href, title);
  }
  return [...seen.entries()].map(([href, title]) => ({ href, title }));
}

/**
 * Parse one Drishti article detail page.
 *
 * Reading the detail page (instead of slicing the index page's text) is what
 * makes the content readable AND is the only place the real article artwork
 * lives — which is why cards used to render without thumbnails.
 */
export async function parseDrishtiArticle(url, dateStr, fallbackTitle = '') {
  const html = await fetchPage(url);
  const $ = cheerio.load(html);

  const detail = $('.article-detail').first();
  if (!detail.length) return null;

  detail.find('.next-post, script, style, iframe, .social-share, .tags-btn').remove();

  const title = cleanText($('h1').first().text()) || cleanText(fallbackTitle);
  if (!title || title.length < 8) return null;

  // ── Tags → category + GS paper ──
  const rawTags = [];
  $('.tags-new a, .tags a').each((_, el) => {
    const t = cleanText($(el).text());
    if (t && t.length > 1 && t.length < 60 && !rawTags.includes(t)) rawTags.push(t);
  });

  const gsPaper = mapGsPaper(rawTags);
  // Only tags that map onto a real syllabus subject may become the category —
  // otherwise section labels like "Rapid Fire CA" end up shown as the topic.
  const tags = rawTags.filter((t) => !JUNK_TAG.test(t));
  const category = tags.map(canonicalSubject).find(Boolean)
    || (gsPaper === 'GS-IV' ? 'Ethics' : 'Current Affairs');

  // ── Body ──
  const body = detail.find('.ckeditor-content').first();
  const bodyRoot = body.length ? body : detail;
  const blocks = blocksFromElement($, bodyRoot);

  // The FAQ/PYQ tail is extracted separately — keep it out of the reading flow.
  const tailIdx = blocks.findIndex((b) => /^##+ .*(Frequently Asked Questions|Previous Years? Questions)/i.test(b));
  const bodyBlocks = tailIdx > 0 ? blocks.slice(0, tailIdx) : blocks;
  const plain = bodyBlocks.join('\n');

  // ── Focus lines ("For Prelims: …", "For Mains: …") ──
  const forPrelims = (plain.match(/For Prelims:\s*([^\n]{0,400})/i) || [])[1] || '';
  const forMains = (plain.match(/For Mains:\s*([^\n]{0,400})/i) || [])[1] || '';

  // The coloured "For Prelims / For Mains / Source" box is metadata, not prose —
  // it is surfaced as its own fields, so drop it from the reading flow.
  const readingBlocks = bodyBlocks.filter(
    (b) => !/^(For Prelims:|For Mains:|Source:)/i.test(b) && b.trim() !== '',
  );

  const content = blocksToContent(readingBlocks);

  // ── Source paper ──
  const rawSource = (bodyRoot.text().match(/Source:\s*([A-Za-z ]{2,20})/) || [])[1] || '';
  const sourcePaper = SOURCE_MAP[rawSource.trim().toLowerCase()] || cleanText(rawSource);

  // ── Thumbnail ──
  let imageUrl = '';
  const contentImg = detail.find('img.content-img').first();
  if (contentImg.length) imageUrl = absoluteImageUrl(contentImg.attr('src') || contentImg.attr('data-src') || '', url);
  if (!isContentImage(imageUrl)) {
    const candidate = detail
      .find('img')
      .map((_, el) => absoluteImageUrl($(el).attr('src') || $(el).attr('data-src') || '', url))
      .get()
      .find((s) => isContentImage(s));
    imageUrl = candidate || '';
  }
  if (!isContentImage(imageUrl)) {
    const og = absoluteImageUrl($('meta[property="og:image"]').attr('content') || '', url);
    imageUrl = isContentImage(og) ? og : '';
  }

  // ── Structured PYQs from the article tail ──
  const pyqs = parsePyqBlock(detail.text(), {
    subject: category,
    gsPaper,
    sourceUrl: url,
    topic: title,
  });

  const keyPoints = extractKeyPoints(content);
  const whyInNews = (() => {
    const i = readingBlocks.findIndex((b) => /^##+\s*Why in News/i.test(b));
    return i >= 0 && readingBlocks[i + 1] ? readingBlocks[i + 1] : '';
  })();

  const summary = cleanText(whyInNews || readingBlocks.find((b) => !b.startsWith('#') && b.length > 80) || content)
    .slice(0, 320)
    .replace(/\s+\S*$/, '') + '…';

  const mainsQ = detail.text().match(/Drishti Mains Question:?\s*([\s\S]{20,400}?)(?:\n\n|Frequently|UPSC Civil|$)/i);

  return {
    id: makeId(title, dateStr),
    title,
    summary,
    content,
    keyPoints,
    examRelevance: forPrelims && forMains ? 'Both' : (forMains ? 'Mains' : (forPrelims ? 'Prelims' : 'Both')),
    categoryTags: [category, ...tags.filter((t) => !/^GS Paper/i.test(t) && !/rapid fire/i.test(t))]
      .filter((v, i, a) => v && a.indexOf(v) === i)
      .slice(0, 6),
    imageUrl,
    publishedDate: dateStr,
    isTopNews: false,
    shortNotes: keyPoints.slice(0, 5),
    newspaper: 'Drishti IAS',
    upscPaper: gsPaper,
    relatedTopics: tags.filter((t) => !/^GS Paper/i.test(t)).slice(0, 8),
    analysisNote: forMains ? `Mains focus: ${cleanText(forMains)}` : '',
    mnemonic: '',
    flowchartSteps: [],
    syllabusMapping: gsPaper ? `${gsPaper} > ${category}` : category,
    previousYearQs: pyqs.map((q) => `${q.type === 'mains' ? 'Mains' : 'Prelims'} ${q.year}: ${q.question}`).slice(0, 5),
    editorialOpinion: '',
    constitutionalBasis: '',
    governmentScheme: '',
    sourceUrl: url,
    sourcePaper,
    keyTerms: {},
    answerFramework: mainsQ ? cleanText(mainsQ[1]).slice(0, 400) : '',
    // Not persisted on the article doc — consumed by index.js and uploaded to
    // the `pyqs` collection.
    _pyqs: pyqs,
  };
}

export async function scrapeDrishti(dateStr) {
  const [y, m, d] = dateStr.split('-');
  const url = `https://www.drishtiias.com/current-affairs-news-analysis-editorials/news-analysis/${d}-${m}-${y}`;
  console.log(`[Drishti] Fetching index: ${url}`);

  let html;
  try {
    html = await fetchPage(url);
  } catch (e) {
    console.error(`[Drishti] ${e.message}`);
    return [];
  }

  const links = drishtiArticleLinks(html);
  if (links.length === 0) {
    console.log('[Drishti] No article links found for this date (Sunday/holiday?)');
    return [];
  }
  console.log(`[Drishti] ${links.length} article link(s); fetching detail pages…`);

  const parsed = await mapLimit(links, DETAIL_CONCURRENCY, async ({ href, title }) => {
    try {
      return await parseDrishtiArticle(href, dateStr, title);
    } catch (e) {
      console.error(`[Drishti] ${href}: ${e.message}`);
      return null;
    }
  });

  const articles = parsed.filter(Boolean);
  const withImages = articles.filter((a) => a.imageUrl).length;
  const pyqCount = articles.reduce((n, a) => n + (a._pyqs?.length || 0), 0);
  console.log(`[Drishti] Extracted ${articles.length} article(s) for ${dateStr} (${withImages} with images, ${pyqCount} PYQs)`);
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
  const images = extractImages(html, url);
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

    const subjectMatch = section.match(/Subject:\s*(.+?)(?:\n|$)/i);
    const rawCategory = subjectMatch ? subjectMatch[1].trim() : '';
    const category = mapCategory(rawCategory);

    let examRelevance = 'Both';
    const lower = section.toLowerCase();
    if (lower.includes('prelims in focus')) examRelevance = 'Prelims';
    else if (lower.includes('mains') || lower.includes('editorial')) examRelevance = 'Mains';

    const keyPoints = extractKeyPoints(section);
    const pyqs = extractPYQs(section);
    // Insights pages are scraped as flat text (there is no per-article page to
    // read), so impose the reader's section structure here — otherwise these
    // articles render as a wall while Drishti's render as sections.
    const cleanedContent = restructure(cleanText(section), { title }).slice(0, 6000);
    const summary = cleanedContent.replace(/^##.*$/gm, '').replace(/^[•◦]\s*/gm, '').trim()
      .slice(0, 300).replace(/\s+\S*$/, '') + '…';

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
      _pyqs: [],
    });
  }

  console.log(`[Insights] Extracted ${articles.length} articles for ${dateStr}`);
  return articles;
}
