#!/usr/bin/env node
/**
 * Deploy firestore.rules via the Firebase Rules REST API.
 *
 * `firebase deploy --only firestore:rules` first calls Service Usage to check
 * that firestore.googleapis.com is enabled. The Firebase Admin service account
 * has no `serviceusage.services.get` permission, so that precheck fails with a
 * 403 and the deploy never starts — even though the account is perfectly able
 * to write rules.
 *
 * This talks to the Rules API directly, which needs only the firebaserules
 * permissions the Admin SDK service account already holds:
 *
 *   1. create a ruleset from the local firestore.rules
 *   2. point the `cloud.firestore` release at it
 *
 * Credentials: FIREBASE_SERVICE_ACCOUNT_B64 or GOOGLE_APPLICATION_CREDENTIALS.
 *
 * Usage:
 *   node deploy-rules.js                 # deploy
 *   node deploy-rules.js --dry-run       # validate + show what would change
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { cert, initializeApp } from 'firebase-admin/app';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(HERE, '..', '..');
const RULES_FILE = path.join(REPO_ROOT, 'firestore.rules');

const API = 'https://firebaserules.googleapis.com/v1';

function loadServiceAccount() {
  const b64 = process.env.FIREBASE_SERVICE_ACCOUNT_B64;
  if (b64) return JSON.parse(Buffer.from(b64, 'base64').toString('utf-8'));

  const file = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (file && fs.existsSync(file)) return JSON.parse(fs.readFileSync(file, 'utf-8'));

  throw new Error(
    'Missing Firebase credentials. Set FIREBASE_SERVICE_ACCOUNT_B64 (base64) '
    + 'or GOOGLE_APPLICATION_CREDENTIALS (path to the service-account JSON).',
  );
}

/** Mint an OAuth token using the Admin SDK's own credential plumbing. */
async function accessToken(serviceAccount) {
  const credential = cert(serviceAccount);
  // initializeApp is not strictly required for getAccessToken, but keeps the
  // credential object on the documented path.
  try {
    initializeApp({ credential });
  } catch { /* already initialised */ }
  const token = await credential.getAccessToken();
  return token.access_token;
}

async function api(token, method, url, body) {
  const res = await fetch(url.startsWith('http') ? url : `${API}${url}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${method} ${url} → HTTP ${res.status}: ${text.slice(0, 500)}`);
  }
  return text ? JSON.parse(text) : {};
}

async function main() {
  const dryRun = process.argv.includes('--dry-run');

  if (!fs.existsSync(RULES_FILE)) throw new Error(`Not found: ${RULES_FILE}`);
  const source = fs.readFileSync(RULES_FILE, 'utf-8');

  const serviceAccount = loadServiceAccount();
  const projectId = serviceAccount.project_id;
  console.log(`Project: ${projectId}`);
  console.log(`Rules:   ${RULES_FILE} (${source.length} bytes)`);

  const token = await accessToken(serviceAccount);

  // Report the collections the rules open up, so a deploy is auditable.
  const publicReads = [...source.matchAll(/match \/(\w+)\/\{[^}]+\}\s*\{\s*allow read: if true/g)]
    .map((m) => m[1]);
  if (publicReads.length) {
    console.log(`Public-read collections (${publicReads.length}): ${publicReads.join(', ')}`);
  }

  if (dryRun) {
    console.log('\nDry run — nothing deployed.');
    return;
  }

  console.log('\nCreating ruleset…');
  const ruleset = await api(token, 'POST', `/projects/${projectId}/rulesets`, {
    source: { files: [{ name: 'firestore.rules', content: source }] },
  });
  console.log(`  ${ruleset.name}`);

  console.log('Updating cloud.firestore release…');
  const releaseName = `projects/${projectId}/releases/cloud.firestore`;
  try {
    await api(token, 'PATCH', `/${releaseName}`, {
      release: { name: releaseName, rulesetName: ruleset.name },
    });
  } catch (e) {
    // First-ever deploy: the release does not exist yet, so PATCH 404s.
    if (!/HTTP 404/.test(e.message)) throw e;
    console.log('  release missing — creating it');
    await api(token, 'POST', `/projects/${projectId}/releases`, {
      name: releaseName,
      rulesetName: ruleset.name,
    });
  }

  console.log('\nDeployed. Firestore is now serving these rules.');
}

main().catch((e) => {
  console.error(`\nFailed: ${e.message}`);
  process.exit(1);
});
