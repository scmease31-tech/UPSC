/**
 * Impose reading structure on flat article text.
 *
 * Articles saved before the scraper read per-article pages are one long run of
 * text: headings, bullets and paragraphs all flattened together, interleaved
 * with site furniture ("Star marking (1-5) indicates…", "Switch To Hindi").
 * The app's reader renders "## " headings and "• " bullets, so those articles
 * show as an undifferentiated wall.
 *
 * Where an article can be re-fetched from its own URL that is always better —
 * this is for the ones that cannot be (Insights entries whose sourceUrl is the
 * daily index, and newspaper PDFs that have no URL at all).
 *
 * Deliberately conservative: it only promotes a line to a heading on strong
 * evidence. Inventing structure that is not there reads worse than leaving
 * prose alone.
 */

/** Site chrome that carries no article content. */
const JUNK_LINE = new RegExp([
  'Star marking',
  'indicates the importance of topic',
  'Switch To Hindi',
  '^Prev$', '^Next$',
  '^\\d+\\s*min read$',
  'Reach Us',
  'Copyright ©',
  'All rights reserved',
  'Download the app',
  'Click here',
  'Also Read',
  'Read More',
  'Follow us',
  'Subscribe',
  'Rapid Fire',
  '^Tags:$',
  '^Share$',
  '^Print$',
].join('|'), 'i');

/** Section names that are headings wherever they appear. */
const SECTION_WORDS = [
  'why in news', 'what is', 'key points', 'key takeaways', 'background', 'about',
  'introduction', 'significance', 'importance', 'challenges', 'concerns', 'issues',
  'way forward', 'conclusion', 'analysis', 'impact', 'benefits', 'advantages',
  'disadvantages', 'limitations', 'recommendations', 'measures', 'suggestions',
  'objectives', 'features', 'salient features', 'provisions', 'eligibility',
  'implementation', 'current status', 'data and facts', 'statistics',
  'government initiatives', 'related schemes', 'international comparison',
  'frequently asked questions', 'summary', 'context',
  'prelims', 'mains', 'upsc relevance', 'syllabus',
];

/**
 * Bibliographic labels, not sections. "Source: IE" and "Subject: Governance"
 * are already stored as their own fields; promoting them to headings produces
 * a heading with a two-letter body, which reads worse than dropping them.
 */
const META_INLINE_RE = /^(source|subject|tags?|newspaper)\s*:\s*(.{0,60})$/i;
const META_LABEL_RE = /^(source|subject|tags?|newspaper)\s*:?\s*$/i;

const SECTION_RE = new RegExp(`^(${SECTION_WORDS.join('|')})\\b`, 'i');

/** Interrogative headings: "What are the Causes of Floods in India?" */
const QUESTION_HEADING_RE = /^(what|why|how|who|when|where|which)\b[^.!]{4,88}\?$/i;

/** "Way Forward:", "Eligibility Criteria:" — a short label ending in a colon. */
const LABEL_HEADING_RE = /^[A-Z][^.!?]{2,90}:$/;

const BULLET_RE = /^\s*([•◦■▪●o*\-–—]|\d{1,2}[.)])\s+(?=\S)/;

function isHeading(line) {
  const t = line.trim().replace(/\s+/g, ' ');
  if (t.length < 3 || t.length > 110) return false;
  if (BULLET_RE.test(t)) return false;
  if (META_INLINE_RE.test(t) || META_LABEL_RE.test(t)) return false;
  if (QUESTION_HEADING_RE.test(t)) return true;
  if (SECTION_RE.test(t) && t.length <= 80) return true;
  if (LABEL_HEADING_RE.test(t)) return true;
  return false;
}

/**
 * Split a run-together line into its component sentences/labels.
 *
 * Flattened HTML frequently glues a heading onto the paragraph that followed
 * it ("Why in News? Assam has witnessed…"). Detect that boundary so the
 * heading can be promoted.
 */
function splitLeadingHeading(line) {
  const m = line.match(/^((?:what|why|how|who|when|where|which)\b[^.!?]{4,80}\?)\s+(\S.*)$/i);
  if (m) return [m[1], m[2]];

  const label = line.match(/^([A-Z][A-Za-z /&'-]{2,40}:)\s+(\S.*)$/);
  if (label && SECTION_RE.test(label[1])) return [label[1], label[2]];

  return null;
}

/**
 * @param {string} raw    Stored article body.
 * @param {object} [opts]
 * @param {string} [opts.title]  Article title, dropped if it opens the body.
 * @returns {string} Text using the app's "## " / "• " markers.
 */
export function restructure(raw, { title = '' } = {}) {
  if (!raw || raw.trim().length === 0) return '';

  // Flattened bodies often use " | " or repeated spaces where line breaks were.
  const lines = raw
    .replace(/\r\n/g, '\n')
    .split(/\n+/)
    .flatMap((l) => l.split(/\s*\|\s*/))
    .map((l) => l.replace(/\s+/g, ' ').trim())
    .filter(Boolean)
    .filter((l) => !JUNK_LINE.test(l));

  const out = [];
  const pushHeading = (text) => {
    const clean = text.trim().replace(/:$/, '');
    if (!clean) return;
    if (out.length && out[out.length - 1] === `## ${clean}`) return;
    out.push(`## ${clean}`);
  };

  const titleKey = title.toLowerCase().replace(/[^a-z0-9]/g, '');

  for (let i = 0; i < lines.length; i++) {
    let line = lines[i];

    // The headline is echoed in the body, and not always on the first line —
    // flattened pages repeat it after the metadata block too.
    if (titleKey && line.toLowerCase().replace(/[^a-z0-9]/g, '') === titleKey) continue;

    // Drop "Source: IE" / "Subject: Governance" and a bare label followed by
    // its short value on the next line.
    if (META_INLINE_RE.test(line)) continue;
    if (META_LABEL_RE.test(line)) {
      const next = lines[i + 1];
      if (next && next.length <= 60 && !isHeading(next)) i++;
      continue;
    }

    const split = splitLeadingHeading(line);
    if (split) {
      pushHeading(split[0]);
      line = split[1];
    }

    if (isHeading(line)) { pushHeading(line); continue; }

    const bullet = line.match(BULLET_RE);
    if (bullet) {
      const body = line.replace(BULLET_RE, '').trim();
      if (body.length > 2) out.push(`• ${body}`);
      continue;
    }

    // Ordinary prose. Very long runs are usually several paragraphs that lost
    // their breaks — split them on sentence boundaries so the reader can breathe.
    if (line.length > 700) {
      const sentences = line.split(/(?<=[.!?])\s+/);
      let buf = '';
      for (const s of sentences) {
        if ((buf + ' ' + s).trim().length > 480) { out.push(buf.trim()); buf = s; }
        else buf = `${buf} ${s}`.trim();
      }
      if (buf.trim()) out.push(buf.trim());
      continue;
    }

    out.push(line);
  }

  // A heading with nothing under it is noise.
  while (out.length && out[out.length - 1].startsWith('## ')) out.pop();

  return out.join('\n\n');
}

/** True when the body already uses the reader's markers. */
export function isStructured(text) {
  return /^##\s/m.test(text || '') || /^•\s/m.test(text || '');
}
