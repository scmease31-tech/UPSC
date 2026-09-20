#!/usr/bin/env node
/**
 * Audit — and optionally prune — the `govtSchemes` collection.
 *
 * Scheme names are pattern-matched out of article prose, which also sweeps up
 * sentence fragments ("Conclusion The PM SHRI Scheme"), verb phrases
 * ("Delivering Development Through Scheme") and organisations that are not
 * government schemes at all ("Ramakrishna Mission"). Those are what make the
 * list look unreliable.
 *
 * Usage:
 *   node audit-schemes.js              # list every name, flag the rejects
 *   node audit-schemes.js --prune      # delete the rejects
 *   node audit-schemes.js --prune --dry-run
 *
 * Credentials: GOOGLE_APPLICATION_CREDENTIALS or FIREBASE_SERVICE_ACCOUNT_B64.
 */

import { getFirestore } from 'firebase-admin/firestore';
import { initFirebase } from './uploader.js';
import { schemeNameProblem } from './generators.js';

const prune = process.argv.includes('--prune');
const dryRun = process.argv.includes('--dry-run');

initFirebase();
const db = getFirestore();

const snap = await db.collection('govtSchemes').get();
console.log(`govtSchemes docs: ${snap.size}\n`);

const keep = [];
const reject = [];
for (const doc of snap.docs) {
  const name = String(doc.data().name ?? '');
  const problem = schemeNameProblem(name);
  if (problem) reject.push({ id: doc.id, name, problem });
  else keep.push(name);
}

const byProblem = new Map();
for (const r of reject) {
  if (!byProblem.has(r.problem)) byProblem.set(r.problem, []);
  byProblem.get(r.problem).push(r.name);
}

console.log(`REJECT ${reject.length} / ${snap.size}`);
for (const [problem, names] of [...byProblem.entries()].sort(
  (a, b) => b[1].length - a[1].length
)) {
  console.log(`\n  ${problem}  (${names.length})`);
  for (const n of names.slice(0, 12)) console.log(`    - ${n}`);
  if (names.length > 12) console.log(`    ...and ${names.length - 12} more`);
}

console.log(`\nKEEP ${keep.length}`);
for (const n of keep.slice(0, 40)) console.log(`    + ${n}`);
if (keep.length > 40) console.log(`    ...and ${keep.length - 40} more`);

if (!prune) {
  console.log('\n(audit only — pass --prune to delete the rejects)');
  process.exit(0);
}

if (dryRun) {
  console.log(`\n[DryRun] Would delete ${reject.length} docs.`);
  process.exit(0);
}

let deleted = 0;
for (let i = 0; i < reject.length; i += 400) {
  const batch = db.batch();
  for (const r of reject.slice(i, i + 400)) {
    batch.delete(db.collection('govtSchemes').doc(r.id));
    deleted++;
  }
  await batch.commit();
}
console.log(`\nDeleted ${deleted} docs. Remaining: ${snap.size - deleted}`);
process.exit(0);
