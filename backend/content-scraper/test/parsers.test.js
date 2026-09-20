import test from 'node:test';
import assert from 'node:assert/strict';

import { classifyPaper, parsePrelimsPaper, parseMainsPaper } from '../upsc-papers.js';
import { classify as classifyUpload } from '../inbox-ingest.js';
import { parsePyqBlock } from '../scrapers.js';
import { restructure, isStructured } from '../restructure.js';
import { generateDailyQuiz, generateFlashcards, generateKeyFacts, generateSchemes } from '../generators.js';

const base = 'https://www.upsc.gov.in/sites/default/files/';

// ── upsc.gov.in filename classification ─────────────────────────────────────

test('classifies CSE Prelims papers, including CSAT', () => {
  assert.deepEqual(classifyPaper(`${base}QP_CSP_2026_GENERAL_STUDIES_PAPER-I_25052026.pdf`), {
    exam: 'CSP', year: 2026, paper: 'Prelims GS-I', url: `${base}QP_CSP_2026_GENERAL_STUDIES_PAPER-I_25052026.pdf`,
  });

  // Underscore is a word character, so a naive \b after "II" never fires — this
  // is what made CSAT papers show up as GS-I.
  assert.equal(
    classifyPaper(`${base}QP_CSP_2026_GENERAL_STUDIES_PAPER-II_25052026.pdf`).paper,
    'Prelims GS-II (CSAT)',
  );
  assert.equal(classifyPaper(`${base}QP-CSP-24-GENERAL-STUDIES-PAPER-I-180624.pdf`).year, 2024);
});

test('classifies CSE Mains GS, Essay and optional papers', () => {
  assert.equal(classifyPaper(`${base}QP-CSM-23-GENERAL-STUDIES-PAPER-III-180923.pdf`).paper, 'GS-III');
  assert.equal(classifyPaper(`${base}GENERAL-STUDIES-PAPER-IV-QP-CSM-25-010925.pdf`).paper, 'GS-IV');
  assert.equal(classifyPaper(`${base}ESSAY-QP-CSM-25-010925.pdf`).paper, 'Essay');
  // Optional-subject papers must be distinguishable so they can be excluded.
  assert.equal(classifyPaper(`${base}ANTHROPOLOGY-PAPER%20I-QP-CSM-25-010925.pdf`).paper, 'Optional');
});

test('ignores non-CSE papers', () => {
  assert.equal(classifyPaper(`${base}QP-CAPF-Exam-2026-GENERAL-ABILITY.pdf`), null);
  assert.equal(classifyPaper(`${base}QP-IES-ISS-26-220626-STATISTICS-PAPER-I.pdf`), null);
});

// ── inbox upload classification ─────────────────────────────────────────────

test('routes uploaded newspapers to the right source', () => {
  assert.equal(classifyUpload('TH Delhi 25.07.2026.pdf').source, 'The Hindu');
  assert.equal(classifyUpload('IE-Delhi-25-07-2026.pdf').source, 'Indian Express');
  // Separators are word characters, so \btoi\b would never match "TOI_25".
  assert.equal(classifyUpload('TOI_25_07_2026.pdf').source, 'Times of India');
});

test('routes uploaded question papers to the PYQ pipeline', () => {
  const prelims = classifyUpload('UPSC Prelims 2023 PYQ.pdf');
  assert.equal(prelims.type, 'questionpaper');
  assert.equal(prelims.exam, 'CSP');
  assert.equal(prelims.year, 2023);

  const csat = classifyUpload('CSAT 2024 paper II.pdf');
  assert.equal(csat.paper, 'Prelims GS-II (CSAT)');

  const mains = classifyUpload('Mains 2022 GS Paper 3.pdf');
  assert.equal(mains.exam, 'CSM');
  assert.equal(mains.paper, 'GS-III');
});

test('an unrecognised PDF is still ingested, never dropped', () => {
  const c = classifyUpload('some random handout.pdf');
  assert.equal(c.type, 'newspaper');
  assert.ok(c.source.length > 0);
});

// ── question-paper parsing ──────────────────────────────────────────────────

test('parses Prelims MCQs with four options', () => {
  const text = [
    '1. Consider the following statements about the Cabinet Secretariat:',
    '1. It prepares the agenda for Cabinet meetings.',
    '2. It functions under the Prime Minister.',
    'Which of the statements given above is/are correct?',
    '(a) 1 only',
    '(b) 2 only',
    '(c) Both 1 and 2',
    '(d) Neither 1 nor 2',
    '2. With reference to the Ramsar Convention, which one of the following is correct?',
    '(a) It concerns wetlands',
    '(b) It concerns deserts',
    '(c) It concerns glaciers',
    '(d) It concerns oceans',
  ].join('\n');

  const out = parsePrelimsPaper(text, { year: 2024, url: 'x' });
  assert.equal(out.length, 2);
  assert.equal(out[0].options.length, 4);
  assert.equal(out[0].options[2], 'Both 1 and 2');
  // UPSC publishes no answer key, so questions are stored unkeyed.
  assert.equal(out[0].answer, -1);
  assert.equal(out[0].source, 'UPSC');
  assert.equal(out[0].year, 2024);
  assert.ok(out[0].question.startsWith('Consider the following statements'));
});

test('parses Mains questions by their marks allocation', () => {
  const text = [
    'Discuss the significance of the 73rd and 74th Constitutional Amendments for local',
    'self-governance in India. 15',
    'Examine the role of the Election Commission in ensuring free and fair elections in India. 10',
  ].join('\n');

  const out = parseMainsPaper(text, { year: 2022, paper: 'GS-II', url: 'x' });
  assert.equal(out.length, 2);
  assert.equal(out[0].marks, 15);
  assert.equal(out[1].marks, 10);
  assert.ok(!/\d+$/.test(out[0].question), 'marks must be stripped from the question text');
  assert.equal(out[0].subject, 'Polity');
});

test('drops transliterated Devanagari rather than publishing it', () => {
  // What Tesseract returns for the Hindi half of a bilingual page in -l eng mode.
  const text = [
    'fret & gon va atfae, wiifes st gor ama sora ert ae ffsaa a up gf ak sfaa-a At 10',
    'Examine the ethical concerns arising from the use of artificial intelligence in',
    'public administration. 15',
  ].join('\n');

  const out = parseMainsPaper(text, { year: 2023, paper: 'GS-IV', url: 'x' });
  assert.equal(out.length, 1);
  assert.ok(out[0].question.startsWith('Examine the ethical concerns'));
});

test('never emits paper instructions as questions', () => {
  const text = [
    'There are TWENTY questions printed both in HINDI and in ENGLISH. 20',
    'Answers must be written in the medium authorized in the Admission Certificate. 15',
    'Account for the huge flooding of million-plus cities in India and suggest remedies. 15',
  ].join('\n');

  const out = parseMainsPaper(text, { year: 2020, paper: 'GS-I', url: 'x' });
  assert.equal(out.length, 1);
  assert.ok(out[0].question.startsWith('Account for the huge flooding'));
});

// ── Drishti PYQ block harvesting ────────────────────────────────────────────

test('harvests keyed Prelims MCQs and Mains questions from a Drishti article', () => {
  const block = [
    'UPSC Civil Services Examination, Previous Years Questions (PYQs)',
    'Prelims:',
    'Q. La Nina is suspected to have caused recent floods in Australia. How is La Nina different from El Nino? (2011)',
    '(a) 1 only',
    '(b) 2 only',
    '(c) Both 1 and 2',
    '(d) Neither 1 nor 2',
    'Ans: (d)',
    'Mains:',
    'Q. The interlinking of rivers can provide viable solutions to droughts and floods. Critically examine. (2020)',
  ].join('\n');

  const out = parsePyqBlock(block, { subject: 'Geography', sourceUrl: 'u' });
  const prelims = out.filter((q) => q.type === 'prelims');
  const mains = out.filter((q) => q.type === 'mains');

  assert.equal(prelims.length, 1);
  assert.equal(prelims[0].year, 2011);
  assert.equal(prelims[0].options.length, 4);
  // This answer key is what makes a harvested question attemptable in the app.
  assert.equal(prelims[0].answer, 3);

  assert.equal(mains.length, 1);
  assert.equal(mains[0].year, 2020);
  assert.equal(mains[0].subject, 'Geography');
});

// ── restructuring flat legacy article bodies ────────────────────────────────

test('promotes section headings and bullets in a flat body', () => {
  const flat = [
    'Assam Floods and Flood Management in India',
    'Why in News? Assam has witnessed its worst floods in over 60 years.',
    'What are the Causes of Floods in India?',
    '• Heavy rainfall during the south-west monsoon.',
    '• Encroachment of natural drainage channels.',
    'Way Forward:',
    'Strengthen embankments and restore wetlands.',
  ].join('\n');

  const out = restructure(flat, { title: 'Assam Floods and Flood Management in India' });

  assert.ok(isStructured(out));
  assert.match(out, /^## Why in News\?$/m);
  assert.match(out, /^## What are the Causes of Floods in India\?$/m);
  assert.match(out, /^## Way Forward$/m);
  assert.match(out, /^• Heavy rainfall during the south-west monsoon\.$/m);
  // The headline must not be repeated inside the body.
  assert.doesNotMatch(out, /^Assam Floods and Flood Management in India$/m);
  // A heading glued to its paragraph gets separated, not swallowed.
  assert.match(out, /^Assam has witnessed its worst floods/m);
});

test('drops bibliographic labels rather than making them headings', () => {
  const flat = [
    'Source: IE',
    'Subject: Government Scheme',
    'Context: The Cabinet approved the policy today, replacing the 2012 framework.',
    'Objectives',
    'Raise domestic urea capacity and cut imports.',
  ].join('\n');

  const out = restructure(flat, { title: '' });

  // "## Source" followed by a two-letter body reads worse than no heading.
  assert.doesNotMatch(out, /## Source/i);
  assert.doesNotMatch(out, /## Subject/i);
  assert.doesNotMatch(out, /\bIE\b/);
  assert.match(out, /^## Context$/m);
  assert.match(out, /^## Objectives$/m);
});

test('strips site furniture', () => {
  const flat = [
    'Star marking (1-5) indicates the importance of topic for CSE',
    'Switch To Hindi',
    '22 min read',
    'Why in News?',
    'The Supreme Court issued directions on prison reform this week.',
  ].join('\n');

  const out = restructure(flat, { title: '' });
  assert.doesNotMatch(out, /Star marking|Switch To Hindi|min read/i);
  assert.match(out, /^## Why in News\?$/m);
});

test('leaves already-structured text alone and reports it as structured', () => {
  const already = '## Why in News?\n\nSomething happened.\n\n• A bullet point here.';
  assert.ok(isStructured(already));
  const out = restructure(already, { title: '' });
  assert.match(out, /^## Why in News\?$/m);
  assert.match(out, /^• A bullet point here\.$/m);
});

test('plain prose with no structure is not mangled into headings', () => {
  const prose = 'The committee met on Tuesday. It reviewed the draft policy and '
    + 'recommended three changes before the next session.';
  const out = restructure(prose, { title: '' });
  assert.doesNotMatch(out, /^## /m);
  assert.match(out, /committee met on Tuesday/);
});

test('decodes HTML entities left behind by earlier scrapes', () => {
  const flat = 'Context: Inspired by Pope Leo XIV&#8217;s Magnifica Humanitas &amp; the '
    + 'Declaration, it calls for protecting human dignity &mdash; from unchecked AI systems.';
  const out = restructure(flat, { title: '' });
  assert.match(out, /Pope Leo XIV’s/);
  assert.match(out, / & the Declaration/);
  assert.doesNotMatch(out, /&#\d+;|&amp;|&mdash;/);
});

test('recovers list items that lost their bullets', () => {
  const flat = [
    'Core Principles of the Declaration',
    'Disarming the Next Arms Race: Coordinated efforts to halt dual arms races.',
    'Responsible Development: Aligning technological progress with human ethics.',
    'Responsible Governance: Building international oversight frameworks.',
  ].join('\n');

  const out = restructure(flat, { title: '' });
  assert.match(out, /^• Disarming the Next Arms Race: /m);
  assert.match(out, /^• Responsible Governance: /m);
});

test('a lone label sentence is not turned into a bullet', () => {
  const flat = 'Note: The committee will reconvene in December to review the draft text.';
  const out = restructure(flat, { title: '' });
  assert.doesNotMatch(out, /^• /m);
});

test('drops a heading immediately followed by another heading', () => {
  const flat = [
    'About The Rome Declaration for an Unarmed and Disarming Peace:',
    'What it is?',
    'The Declaration calls for protecting human dignity from unchecked AI systems.',
  ].join('\n');

  const out = restructure(flat, { title: '' });
  assert.doesNotMatch(out, /## About The Rome Declaration/);
  assert.match(out, /## What it is\?/);
});

test('re-running on already-structured text changes nothing', () => {
  const structured = [
    '## Why in News?',
    '',
    'The Rome Declaration was signed in July 2026 by Nobel laureates and AI scientists.',
    '',
    '## Summary',
    '',
    '• The Declaration warns against outsourcing moral decisions to AI systems.',
    '',
    '◦ It calls for an international treaty on autonomous weapons.',
  ].join('\n');

  const once = restructure(structured, { title: '' });
  const twice = restructure(once, { title: '' });
  assert.equal(twice, once, 'restructure must be idempotent');
  assert.match(once, /^## Why in News\?$/m);
  assert.match(once, /^• The Declaration warns/m);
  assert.match(once, /^◦ It calls for an international treaty/m);
});

// ── derived study content ───────────────────────────────────────────────────

const sampleArticle = {
  title: 'Rome Declaration for an Unarmed and Disarming Peace',
  summary: 'Nobel laureates and AI scientists signed a declaration warning against delegating moral decisions to AI systems.',
  newspaper: 'Drishti IAS',
  publishedDate: '2026-07-24',
  categoryTags: ['International Relations'],
  keyPoints: [],
  content: [
    '## Why in News?',
    '',
    'The Rome Declaration was signed in July 2026 by Nobel laureates and AI scientists.',
    '',
    '## What is the Rome Declaration?',
    '',
    'The Rome Declaration is a moral appeal calling for an international treaty on autonomous weapons systems.',
    '',
    '## Core Principles',
    '',
    '• Nuclear Disarmament: Renewed commitment to verifiable elimination of atomic arsenals by 2045.',
    '• Responsible Governance: Building oversight frameworks for high-risk tools under Article 51 of the Charter.',
  ].join('\n'),
};

test('flashcards come from sections and definitions, not just one per article', () => {
  const cards = generateFlashcards([sampleArticle]);
  // Previously this produced exactly one card, because term cards needed a
  // keyTerms glossary that no scraper populates.
  assert.ok(cards.length >= 4, `expected several cards, got ${cards.length}`);

  const fronts = cards.map((c) => c.front);
  assert.ok(fronts.some((f) => /^What is the Rome Declaration\?$/.test(f)), 'question heading kept verbatim');
  assert.ok(fronts.some((f) => /^Why in news:/.test(f)), 'concept card present');
  // A plain heading is qualified with the topic so it stands alone.
  assert.ok(fronts.some((f) => /^Core Principles — Rome Declaration/.test(f)));
  for (const c of cards) assert.ok(c.back.length >= 30, `card "${c.front}" has a thin back`);
});

test('a heading that already names the topic is not repeated in the front', () => {
  const cards = generateFlashcards([sampleArticle]);
  assert.ok(
    !cards.some((c) => /Rome Declaration.*—.*Rome Declaration/.test(c.front)),
    'front must not repeat the topic twice',
  );
});

test('definition cards reject clause fragments', () => {
  const article = {
    ...sampleArticle,
    content: 'The capital, Skopje, is the birthplace of Mother Teresa and a major cultural centre of the region.',
  };
  const cards = generateFlashcards([article]);
  assert.ok(!cards.some((c) => /^The capital,/.test(c.front)), 'a comma-laden fragment is not a term');
});

test('key facts pick out durable, checkable statements', () => {
  const [card] = generateKeyFacts([sampleArticle]);
  assert.ok(card, 'expected a key-facts card');
  assert.equal(card.category, 'International Relations');
  assert.equal(card.title, sampleArticle.title);
  assert.ok(card.facts.length >= 2);
  // Every fact should carry a number, date, body or legal reference.
  for (const f of card.facts) {
    assert.match(f, /\d{4}|Article\s+\d+|Treaty|Convention|Declaration|Mission/i);
  }
});

test('key facts skip articles with nothing memorable', () => {
  const vague = {
    ...sampleArticle,
    keyPoints: [],
    content: 'Officials met to discuss the matter. They agreed to continue talks at a later date.',
    summary: 'Officials met to discuss the matter.',
  };
  assert.equal(generateKeyFacts([vague]).length, 0);
});


test('daily news quiz is deterministic, valid, and changes by date', () => {
  const categories = ['Polity', 'Economy', 'Environment', 'Science & Technology'];
  const terms = [
    ['Constitutional morality', 'A principle requiring public power to follow constitutional values and institutional limits.'],
    ['Fiscal consolidation', 'A policy process that reduces fiscal deficits and stabilises public debt over time.'],
    ['Carbon sink', 'A natural or artificial reservoir that absorbs more carbon dioxide than it releases.'],
    ['Quantum communication', 'Communication that uses quantum states to detect interception and protect information.'],
  ];
  const articles = categories.map((category, index) => ({
    ...sampleArticle,
    id: `article-${index}`,
    title: `${category} development ${index + 1}`,
    categoryTags: [category],
    upscPaper: index < 2 ? 'GS-II' : 'GS-III',
    keyTerms: { [terms[index][0]]: terms[index][1] },
    keyPoints: [`${category} policy includes a distinct verified finding number ${index + 1} for UPSC preparation.`],
    sourceUrl: `https://example.com/${index}`,
  }));

  const first = generateDailyQuiz(articles, '2026-09-20', { limit: 10 });
  const repeat = generateDailyQuiz(articles, '2026-09-20', { limit: 10 });
  const nextDay = generateDailyQuiz(articles, '2026-09-21', { limit: 10 });

  assert.deepEqual(first, repeat, 'same date and articles must regenerate identically');
  assert.ok(first.length >= 6, `expected a useful daily set, got ${first.length}`);
  assert.equal(new Set(first.map((question) => question.id)).size, first.length);
  assert.notDeepEqual(first.map((question) => question.id), nextDay.map((question) => question.id));
  for (const question of first) {
    assert.equal(question.options.length, 4);
    assert.ok(question.correctAnswerIndex >= 0 && question.correctAnswerIndex < 4);
    assert.equal(question.publishedDate, '2026-09-20');
    assert.equal(question.source, 'daily_news');
    assert.ok(question.explanation.length >= 20);
    assert.ok(question.articleRef);
  }
});

test('daily news quiz handles sparse publication days without throwing', () => {
  const sparse = generateDailyQuiz([{ ...sampleArticle, id: 'only-one' }], '2026-09-20');
  assert.ok(Array.isArray(sparse));
  assert.ok(sparse.length <= 10);
});


// ─────────────────────────────────────────────────────────────────────────────
// Government schemes
//
// The app's detail sheet reads detailedDescription, keyFeatures, ministry and
// upscRelevance. generateSchemes used to set none of them, so every
// scraper-derived scheme opened to a near-empty sheet.
// ─────────────────────────────────────────────────────────────────────────────

const schemeArticle = {
  id: 'art-scheme-1',
  title: 'Cabinet approves PM Vishwakarma Yojana for traditional artisans',
  summary:
    'The Union Cabinet approved the PM Vishwakarma Yojana, a credit and skilling package for traditional artisans and craftspeople.',
  content: [
    'The Union Cabinet has approved the PM Vishwakarma Yojana, implemented by the Ministry of Micro, Small and Medium Enterprises.',
    'PM Vishwakarma Yojana provides collateral-free credit of up to 3 lakh rupees in two tranches to registered artisans.',
    'Under PM Vishwakarma Yojana, beneficiaries receive a stipend of 500 rupees per day during skill training.',
    'The Ministry of Micro, Small and Medium Enterprises will run the scheme across 18 traditional trades.',
    'Officials said the scheme has been in the news recently and is widely discussed.',
  ].join(' '),
  publishedDate: '2026-09-18',
  categoryTags: ['Economy'],
  governmentScheme: 'PM Vishwakarma Yojana',
};

test('derived schemes carry the fields the detail sheet renders', () => {
  const schemes = generateSchemes([schemeArticle]);
  const scheme = schemes.find((s) => /Vishwakarma/i.test(s.name));
  assert.ok(scheme, 'the scheme was not detected');

  for (const field of ['detailedDescription', 'keyFeatures', 'upscRelevance', 'ministry']) {
    assert.ok(field in scheme, `missing field: ${field}`);
  }
  assert.ok(scheme.detailedDescription.length > scheme.description.length / 2);
  assert.ok(scheme.upscRelevance.length > 0);
});

test('the ministry is read from the article, never guessed', () => {
  const [scheme] = generateSchemes([schemeArticle]).filter((s) =>
    /Vishwakarma/i.test(s.name)
  );
  assert.equal(scheme.ministry, 'Ministry of Micro, Small and Medium Enterprises');

  // No ministry named anywhere → blank, not a plausible-looking guess. Which
  // ministry runs a scheme is examinable; a wrong answer is worse than none.
  const noMinistry = generateSchemes([
    {
      ...schemeArticle,
      content:
        'PM Vishwakarma Yojana provides collateral-free credit of up to 3 lakh rupees to 1000 artisans.',
    },
  ]).find((s) => /Vishwakarma/i.test(s.name));
  assert.equal(noMinistry.ministry, '');
});

test('key features are concrete and drop narrative filler', () => {
  const scheme = generateSchemes([schemeArticle]).find((s) =>
    /Vishwakarma/i.test(s.name)
  );
  assert.ok(scheme.keyFeatures.length > 0, 'no key features extracted');
  assert.ok(scheme.keyFeatures.length <= 4);
  // Every bullet must mention the scheme and carry a checkable figure.
  for (const f of scheme.keyFeatures) {
    assert.match(f.toLowerCase(), /vishwakarma/);
    assert.match(f, /\d/);
  }
  // "has been in the news recently" is filler and must not become a feature.
  assert.ok(!scheme.keyFeatures.some((f) => /in the news recently/i.test(f)));
});

test('upscRelevance states syllabus mapping without inventing outcomes', () => {
  const scheme = generateSchemes([schemeArticle]).find((s) =>
    /Vishwakarma/i.test(s.name)
  );
  assert.match(scheme.upscRelevance, /GS-/);
  assert.match(scheme.upscRelevance, /Ministry of Micro, Small and Medium Enterprises/);
  // No claims about success, coverage or impact.
  assert.ok(!/successful|most effective|best scheme|will eradicate/i.test(scheme.upscRelevance));
});

test('a scheme with no usable detail still produces valid fields', () => {
  const thin = generateSchemes([
    {
      id: 'art-thin',
      title: 'Officials review the Sagarmala Mission',
      summary: 'A short note.',
      content: 'Officials reviewed the Sagarmala Mission this week.',
      publishedDate: '2026-09-18',
      categoryTags: ['Infrastructure'],
    },
  ]).find((s) => /Sagarmala/i.test(s.name));

  assert.ok(thin, 'the scheme was not detected');
  assert.equal(typeof thin.detailedDescription, 'string');
  assert.ok(Array.isArray(thin.keyFeatures));
  assert.equal(typeof thin.ministry, 'string');
  // Relevance is always present because it comes from the sector mapping.
  assert.match(thin.upscRelevance, /GS-/);
});

test('scheme generation stays deterministic across runs', () => {
  const a = generateSchemes([schemeArticle]);
  const b = generateSchemes([schemeArticle]);
  assert.deepEqual(a, b);
});
