import test from 'node:test';
import assert from 'node:assert/strict';

import { classifyPaper, parsePrelimsPaper, parseMainsPaper } from '../upsc-papers.js';
import { classify as classifyUpload } from '../inbox-ingest.js';
import { parsePyqBlock } from '../scrapers.js';
import { restructure, isStructured } from '../restructure.js';

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
