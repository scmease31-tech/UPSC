/**
 * Pure generators for the study-library collections.
 *
 * Every generated document uses a stable, legacy-compatible id and schema v2
 * provenance. Persistence is deliberately handled elsewhere so these
 * transforms stay deterministic and straightforward to test.
 */

import crypto from 'crypto';

export const CONTENT_SCHEMA_VERSION = 2;

function hashId(prefix, ...parts) {
  const h = crypto
    .createHash('md5')
    .update(parts.join('|').toLowerCase())
    .digest('hex')
    .slice(0, 16);
  return `${prefix}_${h}`;
}

export function clean(str) {
  return String(str ?? '').normalize('NFKC').replace(/\s+/g, ' ').trim();
}

export function normalizeVocabularyWord(word) {
  return clean(word).toLocaleLowerCase('en-US');
}

export function vocabularyId(word) {
  return hashId('v', normalizeVocabularyWord(word));
}

export function normalizeFlashcardFront(front) {
  return clean(front).toLocaleLowerCase('en-US').replace(/[^a-z0-9]/g, '');
}

export function flashcardId(front) {
  // Keep the established id contract: hash the cleaned display front, not the
  // punctuation-free dedup key. Existing cards therefore remain addressable.
  return hashId('fc', clean(front));
}

export function keyFactId(title) {
  // This is the live collection's established id contract. Provenance is now
  // carried as metadata rather than changing ids and duplicating old cards.
  return hashId('kf', clean(title));
}

const CATEGORY_ALIASES = new Map([
  ['science and technology', 'Science & Technology'],
  ['science & technology', 'Science & Technology'],
  ['sci-tech', 'Science & Technology'],
  ['international relations', 'International Relations'],
  ['international relation', 'International Relations'],
  ['environment and ecology', 'Environment'],
  ['environment & ecology', 'Environment'],
  ['environment', 'Environment'],
  ['indian polity', 'Polity'],
  ['polity', 'Polity'],
  ['economics', 'Economy'],
  ['economy', 'Economy'],
  ['geography', 'Geography'],
  ['history', 'History'],
  ['governance', 'Governance'],
  ['ethics', 'Ethics'],
  ['agriculture', 'Agriculture'],
  ['social issues', 'Social Issues'],
  ['internal security', 'Internal Security'],
  ['current affairs', 'Current Affairs'],
  ['general', 'General'],
]);

export function normalizeCategory(value) {
  const category = clean(value || 'General');
  return CATEGORY_ALIASES.get(category.toLocaleLowerCase('en-US')) || category;
}

/** Map an article's primary tag to one normalized UPSC category. */
export function primaryCategory(article) {
  const tags = article?.categoryTags || [];
  const first = tags.find((tag) => clean(tag) && clean(tag).toLowerCase() !== 'general');
  return normalizeCategory(first || tags[0] || 'General');
}

export function articleMetadata(article) {
  return {
    articleRef: clean(article?.id),
    sourceUrl: clean(article?.sourceUrl),
    upscPaper: clean(article?.upscPaper),
    publishedDate: clean(article?.publishedDate),
    newspaper: clean(article?.newspaper),
  };
}

function articleSortKey(article) {
  const meta = articleMetadata(article);
  return [meta.publishedDate, meta.articleRef, meta.sourceUrl, clean(article?.title)].join('|');
}

function sortedArticles(articles) {
  return [...(articles || [])].sort((a, b) => articleSortKey(a).localeCompare(articleSortKey(b)));
}

/** Find the first sentence in text that explicitly contains term. */
function findExampleSentence(text, term) {
  if (!text || !term) return '';
  const lower = clean(term).toLowerCase();
  const hit = String(text)
    .split(/(?<=[.!?])\s+/)
    .map(clean)
    .find((sentence) =>
      sentence.toLowerCase().includes(lower) && sentence.length > 25 && sentence.length < 260
    );
  return hit || '';
}

// ─────────────────────────────────────────────────────────────────────────────
// Vocabulary
// ─────────────────────────────────────────────────────────────────────────────

function vocabFromKeyTerms(article) {
  const out = [];
  const category = primaryCategory(article);
  const metadata = articleMetadata(article);

  for (const [term, definition] of Object.entries(article.keyTerms || {})) {
    const word = clean(term);
    const meaning = clean(definition);
    if (!word || word.length < 3 || meaning.length < 15) continue;

    out.push({
      id: vocabularyId(word),
      schemaVersion: CONTENT_SCHEMA_VERSION,
      word,
      normalizedWord: normalizeVocabularyWord(word),
      partOfSpeech: word.includes(' ') ? 'phrase' : 'noun',
      meaning,
      example: findExampleSentence(article.content, word),
      synonyms: [],
      antonyms: [],
      category,
      ...metadata,
      upscUsage: `Relevant to ${metadata.upscPaper || category}${
        metadata.publishedDate ? ` — appeared in current affairs on ${metadata.publishedDate}` : ''
      }.`,
    });
  }
  return out;
}

export function generateVocabulary(articles) {
  const byWord = new Map();
  for (const article of sortedArticles(articles)) {
    for (const doc of vocabFromKeyTerms(article)) {
      if (!byWord.has(doc.normalizedWord)) byWord.set(doc.normalizedWord, doc);
    }
  }
  return [...byWord.values()].sort((a, b) => a.normalizedWord.localeCompare(b.normalizedWord));
}

// ─────────────────────────────────────────────────────────────────────────────
// Flashcards
// ─────────────────────────────────────────────────────────────────────────────

function sections(content) {
  const out = [];
  let heading = null;
  let buf = [];
  const flush = () => {
    if (heading && buf.length) {
      const body = buf.join(' ').replace(/^[•◦]\s*/gm, '').replace(/\s+/g, ' ').trim();
      if (body.length > 40) out.push({ heading, body });
    }
    buf = [];
  };

  for (const line of String(content || '').split('\n')) {
    const text = line.trim();
    if (!text) continue;
    const headingMatch = text.match(/^#{2,3}\s+(.+)$/);
    if (headingMatch) {
      flush();
      heading = headingMatch[1].replace(/[:?]+$/, '').trim();
      continue;
    }
    buf.push(text.replace(/^[•◦]\s*/, ''));
  }
  flush();
  return out;
}

const WEAK_HEADING = /^(summary|context|source|introduction|conclusion|note|about|overview|background)$/i;
const DEFINITION_RE = /^([A-Z][A-Za-z0-9 ()'&/-]{3,70}?)\s+(?:is|are|was|were|refers to|means|stands for|is defined as)\s+(.{25,300}?[.!])/;

function isNamedTerm(term) {
  if (/[,;:]/.test(term)) return false;
  const words = term.split(/\s+/);
  if (words.length > 8) return false;
  if (/^(It|This|That|These|Those|There|He|She|They|Which|What|Such|Both|One|Some|Many|Most)\b/i.test(term)) return false;
  if (/^The\s/i.test(term) && words.length <= 2) return false;
  return true;
}

export function generateFlashcards(articles) {
  const byFront = new Map();

  const add = (front, back, article, category, kind) => {
    const f = clean(front);
    const b = clean(back);
    if (!f || f.length < 6 || f.length > 160 || b.length < 30) return;
    const normalizedFront = normalizeFlashcardFront(f);
    if (!normalizedFront || byFront.has(normalizedFront)) return;
    byFront.set(normalizedFront, {
      id: flashcardId(f),
      schemaVersion: CONTENT_SCHEMA_VERSION,
      front: f,
      normalizedFront,
      back: b.slice(0, 600),
      category: normalizeCategory(category),
      kind,
      ...articleMetadata(article),
    });
  };

  for (const article of sortedArticles(articles)) {
    const category = primaryCategory(article);
    const title = clean(article.title);

    for (const [term, definition] of Object.entries(article.keyTerms || {})) {
      add(term, definition, article, category, 'term');
    }

    for (const { heading, body } of sections(article.content)) {
      if (WEAK_HEADING.test(heading)) continue;
      const isQuestion = /\?$|^(what|why|how|who|when|where|which)\b/i.test(heading);
      const words = (value) => new Set(value.toLowerCase().match(/[a-z]{4,}/g) || []);
      const headingWords = words(heading);
      const shared = [...words(title)].filter((word) => headingWords.has(word)).length;
      const front = isQuestion
        ? heading.replace(/\?*$/, '?')
        : (shared >= 2 ? heading : `${heading} — ${title}`);
      add(front, body, article, category, 'section');
    }

    const plain = String(article.content || '')
      .replace(/^#{2,3}\s+.*$/gm, '')
      .replace(/^[•◦]\s*/gm, '');
    for (const sentence of plain.split(/(?<=[.!?])\s+/)) {
      const match = sentence.trim().match(DEFINITION_RE);
      if (!match) continue;
      const term = match[1].trim();
      if (isNamedTerm(term)) add(term, sentence.trim(), article, category, 'definition');
    }

    const summary = clean(article.summary);
    if (title && summary.length > 40) {
      add(`Why in news: ${title}`, summary, article, category, 'why_in_news');
    }
  }

  return [...byFront.values()].sort((a, b) =>
    a.normalizedFront.localeCompare(b.normalizedFront) || a.id.localeCompare(b.id)
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Must Know facts
// ─────────────────────────────────────────────────────────────────────────────

const FACT_SIGNAL = /(\b\d{4}\b|\b\d+(\.\d+)?\s*(%|per cent|crore|lakh|billion|million|km|GW|MW|tonnes?)\b|Article\s+\d+|Section\s+\d+|Schedule\b|Amendment\b|Convention\b|Treaty\b|Protocol\b|Mission\b|Yojana\b|Act,?\s+\d{4}|established|launched|headquarters|ranked|largest|first\b)/i;
const NOT_A_FACT = /(recently|last week|yesterday|today|this week|has been in the news|why in news|according to the article)/i;

export function generateKeyFacts(articles, { perArticle = 6 } = {}) {
  const byId = new Map();

  for (const article of sortedArticles(articles)) {
    const category = primaryCategory(article);
    const title = clean(article.title);
    if (!title) continue;

    const seen = new Set();
    const facts = [];
    const candidates = [
      ...(article.keyPoints || []),
      ...(article.shortNotes || []),
      ...String(article.content || '')
        .split('\n')
        .filter((line) => /^[•◦]\s/.test(line.trim()))
        .map((line) => line.replace(/^[•◦]\s*/, '')),
      ...String(article.content || '')
        .replace(/^#{2,3}\s+.*$/gm, '')
        .split(/(?<=[.!?])\s+/),
    ];

    for (const raw of candidates) {
      const fact = clean(raw);
      if (fact.length < 45 || fact.length > 260 || !FACT_SIGNAL.test(fact) || NOT_A_FACT.test(fact)) continue;
      const key = fact.toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 60);
      if (seen.has(key)) continue;
      seen.add(key);
      facts.push(fact);
      if (facts.length >= perArticle) break;
    }
    if (facts.length < 2) continue;

    const id = keyFactId(title);
    const doc = {
      id,
      schemaVersion: CONTENT_SCHEMA_VERSION,
      category,
      title,
      facts,
      ...articleMetadata(article),
    };
    const held = byId.get(id);
    if (!held || doc.facts.length > held.facts.length) byId.set(id, doc);
  }

  return [...byId.values()].sort((a, b) => a.id.localeCompare(b.id));
}

// ─────────────────────────────────────────────────────────────────────────────
// Government schemes
// ─────────────────────────────────────────────────────────────────────────────

const SCHEME_PATTERNS = [
  /\b((?:Pradhan Mantri|PM[- ])[A-Z][\w'-]*(?:\s+[A-Z][\w'-]*){0,4})\b/g,
  /\b([A-Z][\w'-]*(?:\s+[A-Z][\w'-]*){0,4}\s+Yojana)\b/g,
  /\b([A-Z][\w'-]*(?:\s+[A-Z][\w'-]*){0,4}\s+Abhiyan)\b/g,
  /\b([A-Z][\w'-]*(?:\s+[A-Z][\w'-]*){0,3}\s+Mission)\b/g,
  /\b([A-Z][\w'-]*(?:\s+[A-Z][\w'-]*){0,3}\s+Scheme)\b/g,
];

const SECTOR_KEYWORDS = [
  ['Health', ['health', 'ayushman', 'medical', 'hospital', 'disease']],
  ['Agriculture', ['farmer', 'agri', 'crop', 'kisan', 'irrigation']],
  ['Education', ['education', 'school', 'student', 'skill', 'literacy']],
  ['Women & Child', ['women', 'child', 'girl', 'mahila', 'beti']],
  ['Rural', ['rural', 'gram', 'village', 'panchayat', 'mgnrega']],
  ['Financial', ['bank', 'loan', 'credit', 'insurance', 'pension', 'jan dhan']],
  ['Infrastructure', ['road', 'housing', 'awas', 'smart city', 'transport']],
  ['Energy', ['solar', 'energy', 'power', 'ujjwala', 'lpg', 'electricity']],
];

function guessSector(text) {
  const lower = clean(text).toLowerCase();
  for (const [sector, keys] of SECTOR_KEYWORDS) {
    if (keys.some((key) => lower.includes(key))) return sector;
  }
  return 'Governance';
}

function acronym(name) {
  const words = name.split(/\s+/).filter((word) => /^[A-Z]/.test(word) && word.length > 2);
  return words.length >= 2 ? words.map((word) => word[0]).join('') : '';
}

const MINISTRY_RE = /\b(Ministry|Department)\s+of\s+([A-Z][A-Za-z&'-]*(?:(?:,\s+|\s+and\s+|\s+&\s+|\s+of\s+|\s+)[A-Z][A-Za-z&'-]*){0,6})/g;

function findMinistry(text) {
  if (!text) return '';
  MINISTRY_RE.lastIndex = 0;
  const counts = new Map();
  let match;
  while ((match = MINISTRY_RE.exec(text)) !== null) {
    const name = clean(`${match[1]} of ${match[2]}`)
      .replace(/[,\s]+(and|of|&)$/i, '')
      .replace(/[,\s]+$/, '');
    if (name.length > 80) continue;
    counts.set(name, (counts.get(name) || 0) + 1);
  }
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || b[0].length - a[0].length || a[0].localeCompare(b[0]))[0]?.[0] || '';
}

const SECTOR_PAPER = {
  Health: 'GS-II — Issues relating to development and management of Social Sector/Services (Health)',
  Agriculture: 'GS-III — Issues related to direct and indirect farm subsidies, agricultural marketing',
  Education: 'GS-II — Issues relating to development and management of Social Sector/Services (Education)',
  'Women & Child': 'GS-I / GS-II — Role of women, and welfare schemes for vulnerable sections',
  Rural: 'GS-II — Welfare schemes for vulnerable sections and rural development',
  Financial: 'GS-III — Inclusive growth, mobilisation of resources and financial inclusion',
  Infrastructure: 'GS-III — Infrastructure: energy, ports, roads, airports and railways',
  Energy: 'GS-III — Infrastructure and energy; conservation and environmental impact',
  Governance: 'GS-II — Government policies and interventions for development in various sectors',
};

function schemeRelevance({ sector, ministry, year }) {
  const parts = [`${SECTOR_PAPER[sector] || SECTOR_PAPER.Governance}.`];
  if (ministry && year) parts.push(`Administered by the ${ministry}; appeared in coverage from ${year}.`);
  else if (ministry) parts.push(`Administered by the ${ministry}.`);
  else if (year) parts.push(`Appeared in coverage from ${year}.`);
  parts.push('Expect questions pairing the scheme with its ministry, objective and target group.');
  return parts.join(' ');
}

const SCHEME_FIGURE = /(\b\d{4}\b|\b\d+(?:\.\d+)?\s*(?:%|per ?cent|crore|lakh|billion|million|km|GW|MW|tonnes?|rupees?)\b|\bRs\.?\s*\d|\bArticle\s+\d+|\bSection\s+\d+|\b\d+\s+(?:trades|districts|states|villages|beneficiaries|artisans|families|years|days|months|tranches)\b)/i;

function schemeFeatures(text, name, { limit = 4 } = {}) {
  if (!text || !name) return [];
  const lower = name.toLowerCase();
  const out = [];
  const seen = new Set();
  for (const raw of String(text).split(/(?<=[.!?])\s+/)) {
    const sentence = clean(raw);
    if (sentence.length < 40 || sentence.length > 240) continue;
    if (!sentence.toLowerCase().includes(lower) || !SCHEME_FIGURE.test(sentence) || NOT_A_FACT.test(sentence)) continue;
    const key = sentence.toLowerCase().replace(/[^a-z0-9]/g, '');
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(sentence);
    if (out.length >= limit) break;
  }
  return out;
}

function schemeDetail(text, name, { sentences = 3 } = {}) {
  if (!text || !name) return '';
  const all = String(text).split(/(?<=[.!?])\s+/).map(clean).filter(Boolean);
  const lower = name.toLowerCase();
  const at = all.findIndex((sentence) => sentence.toLowerCase().includes(lower));
  if (at === -1) return '';
  return clean(all.slice(at, at + sentences).join(' ')).slice(0, 900);
}

function tidySchemeName(raw) {
  let name = clean(raw).replace(/[.,;:]+$/, '').replace(/^(the|a|an)\s+/i, '');
  const words = name.split(/\s+/);
  if (words.length % 2 === 0) {
    const half = words.length / 2;
    if (words.slice(0, half).join(' ').toLowerCase() === words.slice(half).join(' ').toLowerCase()) {
      name = words.slice(0, half).join(' ');
    }
  }
  return name.replace(/^(PM|Government|Centre|Cabinet)\s+(Announces?|Launches?|Approves?|Unveils?)\s+/i, '');
}

export function schemeKey(name) {
  return clean(name).toLowerCase().replace(/[^a-z0-9]/g, '');
}

const GENERIC_SCHEME = /^(centrally sponsored|central sector|authorised use|state sponsored|government|national|new|old|special|various|other|similar|such|this|that|above|following|flagship|umbrella)\s+(scheme|mission|programme|program|yojana)s?$/i;
const SECTION_WORD = /^(conclusion|introduction|summary|overview|background|context|question|questions|answer|answers|note|notes|highlight|highlights|about|significance|challenge|challenges|way|analysis|editorial|source|sources|reference|references|prelims|mains|syllabus|topic|news|why|what|how|when|where|objective|objectives|aim|aims|beneficiary|beneficiaries|eligibility|benefit|benefits|funding|implementation|launch)\b/i;
const VERB_PHRASE = /\b(transform|transforms|transforming|deliver|delivers|delivering|aims?|aiming|seeks?|seeking|provides?|providing|ensures?|ensuring|promotes?|promoting|strengthens?|strengthening|boosts?|boosting|covers?|covering|helps?|helping|enables?|enabling|launches|launched|approves|approved|announces|announced|extends|extended|replaces|replaced|supports?|supporting|improves?|improving|addresses|addressing|marks?|shows?|said|says)\b/i;
const NOT_A_SCHEME = /^(ramakrishna|sri ramakrishna|aurobindo|brahmo|arya samaj|theosophical|salvation|jesuit|christian|catholic|baptist|methodist|lutheran|anglican|evangelical|mormon|scientology|red cross|rotary|lions|unesco|unicef|undp|unhcr|who|world bank|imf|asian development|oxfam|greenpeace|amnesty)\b/i;
const SCHEME_NOUN = /\b(yojana|abhiyan|mission|scheme|programme|program|nidhi|kosh|bima|pension|awas|gram|sarva|shiksha|kaushal|kisan|jan|bachao|padhao|jeevan|poshan|suraksha|samman|ujjwala|saubhagya|ayushman|swachh|amrit|setu|vikas|kalyan|anna|garib|mudra|ujala|saksham)\b/i;
const GENERIC_TOKEN = new Set([
  'the', 'a', 'an', 'of', 'and', 'for', 'in', 'on', 'to', 'its', 'this', 'that',
  'new', 'old', 'existing', 'current', 'proposed', 'revised', 'revamped',
  'restructured', 'modified', 'amended', 'extended', 'continued', 'merged',
  'parent', 'special', 'general', 'various', 'other', 'similar', 'above',
  'following', 'flagship', 'umbrella', 'overall', 'total', 'main', 'major',
  'key', 'core', 'basic', 'model', 'pilot', 'phase', 'ii', 'iii', 'iv',
  'national', 'central', 'centrally', 'state', 'government', 'union', 'public',
  'technology', 'ecosystem', 'development', 'welfare', 'support', 'assistance',
  'scheme', 'schemes', 'mission', 'missions', 'programme', 'program', 'yojana',
  'abhiyan', 'plan', 'policy', 'fund', 'initiative', 'project', 'package',
  'visit', 'visits', 'schools', 'school', 'fellowship', 'fellowships',
  'court', 'courts', 'address', 'speech', 'meeting', 'rally', 'interview',
  'statement', 'remarks', 'message', 'greeting', 'tribute', 'inauguration',
]);
const TRAILING_JUNK = /\b(target|targets|highlights?|details?|features?|benefits?|eligibility|objectives?|outcomes?|status|progress|update|updates|data|report|reports|coverage|allocation|budget|outlay|funding|guidelines?|criteria|beneficiaries|implementation|launch|review)$/i;

export function schemeNameProblem(raw) {
  const name = clean(raw);
  if (!name) return 'empty';
  if (name.length < 6) return 'too short';
  if (name.length > 90) return 'too long';

  const words = name.split(/\s+/);
  const isAcronym = (word) =>
    /^[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*$/.test(word) && word.replace(/-/g, '').length >= 4;
  if (words.length < 2 && !isAcronym(words[0])) return 'single word';
  if (words.length > 9) return 'too many words (sentence fragment)';
  if (GENERIC_SCHEME.test(name)) return 'generic category, names no scheme';
  if (SECTION_WORD.test(name)) return 'starts with an article-structure word';
  if (VERB_PHRASE.test(name)) return 'contains a verb (sentence fragment)';
  if (NOT_A_SCHEME.test(name)) return 'organisation, not a government scheme';
  if (TRAILING_JUNK.test(name)) return 'ends with a non-name word';
  if (tidySchemeName(name) !== name) return 'malformed (tidies differently)';

  const distinctive = words.filter(
    (word) => !GENERIC_TOKEN.has(word.toLowerCase().replace(/[^a-z0-9-]/g, ''))
  );
  if (distinctive.length === 0) return 'no distinctive name';

  const hasSchemeNoun = SCHEME_NOUN.test(name);
  const hasAcronym = /\b[A-Z]{3,}\b/.test(name) || words.some(isAcronym);
  const prefixed = /^(pm|pradhan mantri|mukhyamantri|rashtriya|atal)\b/i.test(name);
  const tailCarriesIdentity = words.slice(1).some(
    (word) => !GENERIC_TOKEN.has(word.toLowerCase().replace(/[^a-z0-9-]/g, ''))
  );
  const hasKnownPrefix = prefixed && (hasSchemeNoun || words.length >= 3 || tailCarriesIdentity);
  const isTitleCasePhrase = words.length >= 3 && words.every(
    (word) => /^[A-Z0-9]/.test(word) || /^(of|and|for|in|on|to|the|a|an)$/i.test(word)
  );
  if (!hasSchemeNoun && !hasAcronym && !hasKnownPrefix && !isTitleCasePhrase) {
    return 'no scheme/programme noun';
  }

  const capitalised = words.filter((word) => /^[A-Z0-9]/.test(word)).length;
  if (capitalised / words.length < 0.6) return 'mostly lowercase (mid-sentence)';
  return null;
}

const HEADING_FIELDS = [
  ['objective', /^(?:key\s+)?(?:objectives?|aims?|purpose)(?:\s+of\s+(?:the\s+)?scheme)?$/i],
  ['beneficiaries', /^(?:(?:(?:target|intended)\s+)?beneficiaries|target\s+groups?|who\s+benefits)$/i],
  ['eligibility', /^(?:eligibility|eligibility\s+criteria|who\s+(?:is\s+eligible|can\s+apply))$/i],
  ['benefits', /^(?:key\s+)?(?:benefits?|assistance|incentives?)(?:\s+under\s+(?:the\s+)?scheme)?$/i],
  ['funding', /^(?:funding|funding\s+pattern|financial\s+outlay|budget(?:ary\s+allocation)?|outlay)$/i],
  ['implementation', /^(?:implementation|implementing\s+agency|nodal\s+(?:agency|ministry)|execution)$/i],
  ['launchYear', /^(?:launch|launched|launch\s+year|year\s+(?:launched|of\s+launch)|inception)$/i],
  ['officialUrl', /^(?:official\s+)?(?:website|web\s*site|url|portal|scheme\s+portal)$/i],
];

function headingField(value) {
  const heading = clean(value).replace(/[:?]+$/, '').replace(/^\d+[.)]\s*/, '');
  return HEADING_FIELDS.find(([, pattern]) => pattern.test(heading))?.[0] || '';
}

function explicitHeadingBlocks(content) {
  const blocks = [];
  let current = null;
  const flush = () => {
    if (current && current.lines.length) {
      blocks.push({ field: current.field, text: current.lines.join('\n') });
    }
    current = null;
  };

  for (const rawLine of String(content || '').split('\n')) {
    const line = rawLine.trim();
    if (!line) continue;
    const markdownHeading = line.match(/^#{1,6}\s+(.+)$/);
    if (markdownHeading) {
      flush();
      const field = headingField(markdownHeading[1]);
      current = field ? { field, lines: [] } : null;
      continue;
    }
    const labelled = line.match(/^([^:]{3,45}):\s+(.+)$/);
    if (labelled) {
      const field = headingField(labelled[1]);
      if (field) {
        flush();
        blocks.push({ field, text: labelled[2] });
        continue;
      }
    }
    if (current) current.lines.push(line);
  }
  flush();
  return blocks;
}

function mentionsAlias(text, aliases) {
  const lower = clean(text).toLowerCase();
  return aliases.some((alias) => lower.includes(alias.toLowerCase()));
}

function splitExplicitItems(text) {
  return String(text || '')
    .split(/\n|(?<=[.!?;])\s+/)
    .map((item) => clean(item).replace(/^[•◦*-]\s*/, ''))
    .filter((item) => item.length >= 4);
}

function normalizedEvidenceKey(value) {
  return clean(value).toLowerCase().replace(/[^a-z0-9]/g, '');
}

function uniqueStrings(values, limit = Infinity) {
  const byKey = new Map();
  for (const value of values.flatMap((item) => splitExplicitItems(item))) {
    const key = normalizedEvidenceKey(value);
    if (!key || byKey.has(key)) continue;
    byKey.set(key, value);
  }
  return [...byKey.values()]
    .sort((a, b) => a.localeCompare(b))
    .slice(0, limit);
}

function bestText(values, maxLength = 900) {
  return uniqueStrings(values)
    .sort((a, b) => b.length - a.length || a.localeCompare(b))[0]
    ?.slice(0, maxLength) || '';
}

export function isVerifiedOfficialUrl(value) {
  try {
    const url = new URL(clean(value));
    const host = url.hostname.toLowerCase().replace(/\.$/, '');
    return ['gov.in', 'nic.in'].some((domain) => host === domain || host.endsWith(`.${domain}`));
  } catch {
    return false;
  }
}

function approvedUrls(text) {
  const urls = String(text || '').match(/https?:\/\/[^\s<>()"']+/gi) || [];
  return urls
    .map((url) => url.replace(/[.,;:!?\])}]+$/, ''))
    .filter(isVerifiedOfficialUrl);
}

const SENTENCE_CUES = {
  objective: /\b(objectives?|aims?|purpose|seeks?\s+to|intended\s+to)\b/i,
  beneficiaries: /\b(beneficiar(?:y|ies)|target\s+groups?|intended\s+for|targeted\s+at)\b/i,
  eligibility: /\b(eligib(?:le|ility)|can\s+apply|qualif(?:y|ies|ication))\b/i,
  benefits: /\b(benefits?|assistance|incentives?|entitled|provides?)\b/i,
  funding: /\b(fund(?:ed|ing)|outlay|budget(?:ary)?\s+allocation|cost[- ]sharing)\b/i,
  implementation: /\b(implement(?:ed|ation|ing)|nodal\s+(?:agency|ministry)|administered|executed)\b/i,
};

function extractExplicitSchemeFields(article, aliases, allowHeadingContext) {
  const fields = {
    objective: [], beneficiaries: [], eligibility: [], benefits: [],
    funding: [], implementation: [], launchYear: [], officialUrl: [],
  };

  for (const block of explicitHeadingBlocks(article.content)) {
    if (!allowHeadingContext && !mentionsAlias(block.text, aliases)) continue;
    if (block.field === 'launchYear') {
      fields.launchYear.push(...(block.text.match(/\b(?:19|20)\d{2}\b/g) || []));
    } else if (block.field === 'officialUrl') {
      fields.officialUrl.push(...approvedUrls(block.text));
    } else {
      fields[block.field].push(block.text);
    }
  }

  const sentences = String(article.content || '')
    .split(/(?<=[.!?])\s+|\n+/)
    .map(clean)
    .filter(Boolean);
  for (const sentence of sentences) {
    if (!mentionsAlias(sentence, aliases)) continue;
    for (const [field, cue] of Object.entries(SENTENCE_CUES)) {
      if (cue.test(sentence)) fields[field].push(sentence);
    }
    const launch = sentence.match(
      /\b(?:launched|introduced|started|rolled\s+out|came\s+into\s+effect|inception)\b[^.!?]{0,80}\b((?:19|20)\d{2})\b/i
    );
    if (launch) fields.launchYear.push(launch[1]);
    fields.officialUrl.push(...approvedUrls(sentence));
  }

  const titleMentions = mentionsAlias(article.title, aliases);
  const explicitUrl = clean(article.officialUrl);
  if ((allowHeadingContext || titleMentions) && isVerifiedOfficialUrl(explicitUrl)) {
    fields.officialUrl.push(explicitUrl);
  }
  if (titleMentions && isVerifiedOfficialUrl(article.sourceUrl)) {
    fields.officialUrl.push(clean(article.sourceUrl));
  }
  return fields;
}

function schemeSource(article) {
  const url = clean(article.sourceUrl);
  return {
    articleId: clean(article.id),
    title: clean(article.title),
    url,
    publisher: clean(article.newspaper),
    publishedDate: clean(article.publishedDate),
    official: isVerifiedOfficialUrl(url),
  };
}

function sourceKey(source) {
  return source.articleId || source.url || [source.title, source.publisher, source.publishedDate].join('|');
}

function uniqueSources(sources) {
  const byKey = new Map();
  for (const source of sources) {
    const key = sourceKey(source);
    if (key && !byKey.has(key)) byKey.set(key, source);
  }
  return [...byKey.values()].sort((a, b) =>
    a.publishedDate.localeCompare(b.publishedDate) ||
    a.articleId.localeCompare(b.articleId) ||
    a.url.localeCompare(b.url) ||
    a.title.localeCompare(b.title)
  );
}

function chooseVoted(values) {
  const counts = new Map();
  for (const value of values.filter(Boolean)) counts.set(value, (counts.get(value) || 0) + 1);
  return [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0]?.[0] || '';
}

function validCoverageYear(value) {
  const match = clean(value).match(/^((?:19|20)\d{2})-\d{2}-\d{2}$/);
  return match?.[1] || '';
}

export function generateSchemes(articles) {
  const groups = new Map();

  for (const article of sortedArticles(articles)) {
    const detections = new Map();
    const detect = (rawName, explicit = false) => {
      const name = tidySchemeName(rawName);
      if (schemeNameProblem(name)) return;
      const key = schemeKey(name);
      const held = detections.get(key) || { names: new Map(), explicit: false };
      held.names.set(name, (held.names.get(name) || 0) + 1);
      held.explicit ||= explicit;
      detections.set(key, held);
    };

    if (article.governmentScheme) detect(article.governmentScheme, true);
    const haystack = `${article.title || ''}\n${article.content || ''}`;
    for (const pattern of SCHEME_PATTERNS) {
      pattern.lastIndex = 0;
      let match;
      while ((match = pattern.exec(haystack)) !== null) detect(match[1], false);
    }

    const articleSchemeCount = detections.size;
    for (const [key, detection] of detections) {
      if (!groups.has(key)) groups.set(key, { names: new Map(), mentions: new Map() });
      const group = groups.get(key);
      for (const [name, count] of detection.names) {
        const vote = group.names.get(name) || { count: 0, explicit: 0 };
        vote.count += count;
        if (detection.explicit) vote.explicit++;
        group.names.set(name, vote);
      }
      const mentionKey = articleSortKey(article);
      if (!group.mentions.has(mentionKey)) {
        group.mentions.set(mentionKey, { article, articleSchemeCount });
      }
    }
  }

  const output = [];
  for (const [key, group] of [...groups.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
    const name = [...group.names.entries()].sort((a, b) =>
      b[1].explicit - a[1].explicit ||
      b[1].count - a[1].count ||
      a[0].length - b[0].length ||
      a[0].localeCompare(b[0])
    )[0][0];
    const aliases = [...group.names.keys()].sort();
    const mentions = [...group.mentions.values()];

    const descriptions = [];
    const details = [];
    const features = [];
    const objectives = [];
    const beneficiaries = [];
    const eligibility = [];
    const benefits = [];
    const funding = [];
    const implementation = [];
    const launchYears = [];
    const officialUrls = [];
    const ministries = [];
    const sectors = [];
    const coverageYears = [];
    const sources = [];

    for (const { article, articleSchemeCount } of mentions) {
      const body = `${article.title || ''}\n${article.summary || ''}\n${article.content || ''}`;
      const context = `${article.title || ''} ${article.summary || ''}`;
      sectors.push(guessSector(context));
      const coverageYear = validCoverageYear(article.publishedDate);
      if (coverageYear) coverageYears.push(coverageYear);
      sources.push(schemeSource(article));

      for (const alias of aliases) {
        const description = findExampleSentence(article.content, alias);
        if (description) descriptions.push(description);
        const detail = schemeDetail(article.content, alias);
        if (detail) details.push(detail);
        features.push(...schemeFeatures(article.content, alias));
      }
      if (!descriptions.length && clean(article.summary)) descriptions.push(clean(article.summary));

      const explicit = extractExplicitSchemeFields(article, aliases, articleSchemeCount === 1);
      objectives.push(...explicit.objective);
      beneficiaries.push(...explicit.beneficiaries);
      eligibility.push(...explicit.eligibility);
      benefits.push(...explicit.benefits);
      funding.push(...explicit.funding);
      implementation.push(...explicit.implementation);
      launchYears.push(...explicit.launchYear);
      officialUrls.push(...explicit.officialUrl);

      const schemeSentences = String(body)
        .split(/(?<=[.!?])\s+|\n+/)
        .map(clean)
        .filter((sentence) => mentionsAlias(sentence, aliases));
      for (const sentence of [...schemeSentences, ...explicit.implementation]) {
        const ministry = findMinistry(sentence);
        if (ministry) ministries.push(ministry);
      }
    }

    const ministry = chooseVoted(ministries);
    const sector = chooseVoted(sectors) || 'Governance';
    const coverageYear = [...coverageYears].sort().at(-1) || '';
    const launchYear = chooseVoted(launchYears.filter((year) => /^(?:19|20)\d{2}$/.test(year)));
    const canonicalSources = uniqueSources(sources);
    const officialUrl = uniqueStrings(officialUrls.filter(isVerifiedOfficialUrl), 1)[0] || '';

    output.push({
      id: hashId('gs', name),
      schemaVersion: CONTENT_SCHEMA_VERSION,
      name,
      fullForm: acronym(name),
      description: bestText(descriptions, 260),
      detailedDescription: bestText(details.length ? details : descriptions, 900),
      keyFeatures: uniqueStrings(features, 4),
      objective: bestText(objectives, 700),
      beneficiaries: uniqueStrings(beneficiaries, 12),
      eligibility: uniqueStrings(eligibility, 12),
      benefits: uniqueStrings(benefits, 12),
      funding: bestText(funding, 700),
      implementation: bestText(implementation, 700),
      launchYear,
      officialUrl,
      sources: canonicalSources,
      upscRelevance: schemeRelevance({ sector, ministry, year: coverageYear }),
      ministry,
      sector,
      year: coverageYear,
      coverageYear,
      iconName: '',
      colorHex: '',
      normalizedName: key,
    });
  }

  return output;
}

// ─────────────────────────────────────────────────────────────────────────────
// Daily current-affairs quiz
// ─────────────────────────────────────────────────────────────────────────────

function stableRank(seed, value) {
  return crypto.createHash('sha256').update(`${seed}|${value}`).digest('hex');
}

function orderedOptions(correct, distractors, seed) {
  const unique = [correct, ...distractors]
    .map(clean)
    .filter((value, index, all) => value && all.indexOf(value) === index)
    .slice(0, 4);
  if (unique.length !== 4) return null;
  unique.sort((a, b) => stableRank(seed, a).localeCompare(stableRank(seed, b)));
  return { options: unique, correctAnswerIndex: unique.indexOf(clean(correct)) };
}

export function generateDailyQuiz(articles, dateStr, { limit = 10 } = {}) {
  const usable = [...articles]
    .filter((article) => clean(article.title))
    .sort((a, b) => clean(a.title).localeCompare(clean(b.title)));
  const candidates = [];
  const seenQuestions = new Set();

  const add = (question, correct, distractors, article, type, explanation) => {
    const q = clean(question);
    if (!q || seenQuestions.has(q.toLowerCase())) return;
    const arranged = orderedOptions(correct, distractors, `${dateStr}|${article.id}|${type}`);
    if (!arranged) return;
    seenQuestions.add(q.toLowerCase());
    candidates.push({
      id: hashId('dq', dateStr, article.id || article.title, type),
      question: q,
      options: arranged.options,
      correctAnswerIndex: arranged.correctAnswerIndex,
      explanation: clean(explanation).slice(0, 500),
      category: primaryCategory(article),
      difficulty: type === 'term' ? 'Medium' : 'Easy',
      articleRef: article.id || '',
      syllabusArea: clean(article.syllabusMapping || article.upscPaper || ''),
      source: 'daily_news',
      publishedDate: dateStr,
      sourceTitle: clean(article.title),
      sourceUrl: clean(article.sourceUrl || ''),
    });
  };

  const terms = usable.flatMap((article) => Object.entries(article.keyTerms || {})
    .map(([term, definition]) => ({ article, term: clean(term), definition: clean(definition) }))
    .filter((item) => item.term.length > 2 && item.definition.length > 20));
  for (const item of terms) {
    const distractors = terms
      .filter((other) => other.term.toLowerCase() !== item.term.toLowerCase())
      .map((other) => other.definition);
    add(
      `In today’s current affairs, what does “${item.term}” mean?`,
      item.definition,
      distractors,
      item.article,
      'term',
      `${item.term}: ${item.definition} Source: ${item.article.title}`,
    );
  }

  const keyPointItems = usable
    .map((article) => ({ article, point: clean((article.keyPoints || [])[0] || (article.shortNotes || [])[0]) }))
    .filter((item) => item.point.length >= 25 && item.point.length <= 220);
  for (const item of keyPointItems) {
    const distractors = keyPointItems
      .filter((other) => other.article.id !== item.article.id)
      .map((other) => other.point);
    add(
      `Which statement is linked to “${clean(item.article.title)}”?`,
      item.point,
      distractors,
      item.article,
      'key-point',
      `${item.point} This was a key point in ${item.article.title}.`,
    );
  }

  const categoryPool = [...new Set(usable.map(primaryCategory))];
  const defaultCategories = ['Polity', 'Economy', 'Environment', 'Science & Technology', 'International Relations', 'Social Issues'];
  for (const article of usable) {
    const correct = primaryCategory(article);
    const distractors = [...categoryPool, ...defaultCategories].filter((value) => value !== correct);
    add(
      `Which UPSC subject best matches “${clean(article.title)}”?`,
      correct,
      distractors,
      article,
      'category',
      `The article is classified under ${correct}${article.upscPaper ? ` (${article.upscPaper})` : ''}.`,
    );
  }

  candidates.sort((a, b) => stableRank(dateStr, a.id).localeCompare(stableRank(dateStr, b.id)));
  return candidates.slice(0, limit);
}

export function generateAll(articles) {
  return {
    vocabulary: generateVocabulary(articles),
    flashcards: generateFlashcards(articles),
    schemes: generateSchemes(articles),
    keyFacts: generateKeyFacts(articles),
  };
}
