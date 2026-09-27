#!/usr/bin/env node
/**
 * Checkpointed continuation for the one-time canonical vocabulary migration.
 *
 * The first release-day runs completed 2026-07-14..2026-08-17 and
 * 2026-09-16..2026-09-26, growing production from 427 to 878 words. Project read
 * quota was then exhausted before the remaining 2026-08-18..2026-09-15 range
 * could reload the article/index snapshots. This job retries after the next
 * daily quota reset, stores its next date in Firestore, and becomes a one-read
 * no-op after completion.
 */

import { pathToFileURL } from 'node:url';

import { runBackfill } from './backfill.js';
import { initFirebase } from './uploader.js';

export const DEFAULT_START = '2026-08-18';
export const DEFAULT_END = '2026-09-15';
export const CHECKPOINT_COLLECTION = '_maintenance';
export const CHECKPOINT_ID = 'canonical-vocabulary-v2';

function args(values = process.argv.slice(2)) {
  const result = {
    from: '',
    to: DEFAULT_END,
    maxDates: 30,
    dryRun: false,
    help: false,
  };
  for (let index = 0; index < values.length; index++) {
    switch (values[index]) {
      case '--from': result.from = values[++index] || ''; break;
      case '--to': result.to = values[++index] || DEFAULT_END; break;
      case '--max-dates': result.maxDates = Number(values[++index] || 30); break;
      case '--dry-run': result.dryRun = true; break;
      case '--help':
      case '-h': result.help = true; break;
      default: throw new Error(`Unknown argument: ${values[index]}`);
    }
  }
  if (!Number.isInteger(result.maxDates) || result.maxDates < 1) {
    throw new Error('--max-dates must be a positive integer');
  }
  return result;
}

function usage() {
  return `Usage: node resume-vocabulary-backfill.js [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--max-dates N] [--dry-run]`;
}

export function nextCheckpoint(vocabulary, to) {
  const nextFrom = vocabulary.hasMore ? vocabulary.nextFrom : '';
  return {
    nextFrom,
    to,
    completed: !vocabulary.hasMore,
    completedDates: vocabulary.completedDates.length,
    vocabularyDocs: vocabulary.totals.docs,
    uploaded: vocabulary.totals.uploaded,
    skipped: vocabulary.totals.skipped,
  };
}

export async function runCheckpointedVocabulary({
  firestore,
  options,
  run = runBackfill,
  log = console.log,
}) {
  const checkpointRef = firestore
    .collection(CHECKPOINT_COLLECTION)
    .doc(CHECKPOINT_ID);
  const checkpoint = await checkpointRef.get();
  const state = checkpoint.exists ? checkpoint.data() || {} : {};

  if (state.completed === true && !options.from) {
    log(`[VocabularyResume] already complete through ${state.to || options.to}; no work`);
    return { skippedAsComplete: true, checkpoint: state };
  }

  const from = options.from || state.nextFrom || DEFAULT_START;
  const to = options.to || state.to || DEFAULT_END;
  log(
    `[VocabularyResume] from=${from} to=${to} maxDates=${options.maxDates} ` +
      `dryRun=${options.dryRun}`
  );

  const result = await run({
    options: {
      from,
      to,
      maxDates: options.maxDates,
      vocabOnly: true,
      dryRun: options.dryRun,
    },
    firestore,
    log,
  });
  const next = nextCheckpoint(result.vocabulary, to);

  if (!options.dryRun) {
    await checkpointRef.set(
      {
        ...next,
        lastFrom: from,
        updatedAt: new Date().toISOString(),
      },
      { merge: true },
    );
  }
  log(
    next.completed
      ? `[VocabularyResume] COMPLETE through ${to}`
      : `[VocabularyResume] next chunk starts ${next.nextFrom}`
  );
  return { skippedAsComplete: false, checkpoint: next, result };
}

async function main() {
  const options = args();
  if (options.help) {
    console.log(usage());
    return;
  }
  const firestore = initFirebase();
  await runCheckpointedVocabulary({ firestore, options });
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) {
  main().catch((error) => {
    console.error(`Vocabulary continuation failed: ${error.message}`);
    process.exitCode = 1;
  });
}
