#!/usr/bin/env node
/**
 * Ensure the live Firebase project has a Web app and export its config.
 *
 * Android and the scraper use upsc-app-e2475-e5c95, while firebase_options.dart
 * was left pointing web at the stale upsc-app-e2475 project. That split makes
 * the same route show different or empty content depending on platform.
 *
 * Uses the existing Firebase service account. If no live-project Web app exists,
 * creates one; otherwise reuses the named (or first active) app. The API key is
 * ordinary Firebase client configuration, not a secret, but the script writes
 * it to an artifact rather than dumping it into Actions logs.
 */

import { cert, initializeApp } from 'firebase-admin/app';
import { writeFileSync } from 'node:fs';

const API = 'https://firebase.googleapis.com/v1beta1';
const DISPLAY_NAME = process.env.FIREBASE_WEB_DISPLAY_NAME || 'UPSC Daily Edge Web';
const OUTPUT = process.env.FIREBASE_WEB_CONFIG_OUTPUT || 'firebase-web-config.json';

function serviceAccount() {
  const encoded = process.env.FIREBASE_SERVICE_ACCOUNT_B64;
  if (!encoded) throw new Error('Missing FIREBASE_SERVICE_ACCOUNT_B64.');
  return JSON.parse(Buffer.from(encoded, 'base64').toString('utf8'));
}

async function tokenFor(account) {
  const credential = cert(account);
  try {
    initializeApp({ credential });
  } catch {
    // Another helper may already have initialized Admin in this process.
  }
  return (await credential.getAccessToken()).access_token;
}

async function request(token, method, path, body) {
  const response = await fetch(`${API}/${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  const data = text ? JSON.parse(text) : {};
  if (!response.ok) {
    throw new Error(`${method} ${path} → HTTP ${response.status}: ${text.slice(0, 500)}`);
  }
  return data;
}

async function waitForOperation(token, name) {
  for (let attempt = 0; attempt < 30; attempt++) {
    const operation = await request(token, 'GET', name);
    if (operation.done) {
      if (operation.error) throw new Error(JSON.stringify(operation.error));
      return operation.response;
    }
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }
  throw new Error(`Timed out waiting for ${name}`);
}

async function main() {
  const account = serviceAccount();
  const projectId = account.project_id;
  const token = await tokenFor(account);
  const parent = `projects/${projectId}`;

  const listed = await request(token, 'GET', `${parent}/webApps?pageSize=100`);
  const active = (listed.apps || []).filter((app) => app.state !== 'DELETED');
  let app = active.find((candidate) => candidate.displayName === DISPLAY_NAME) || active[0];

  if (!app) {
    console.log(`No Web app exists in ${projectId}; creating "${DISPLAY_NAME}".`);
    const operation = await request(token, 'POST', `${parent}/webApps`, {
      displayName: DISPLAY_NAME,
    });
    app = await waitForOperation(token, operation.name);
  } else {
    console.log(`Reusing Web app "${app.displayName}" in ${projectId}.`);
  }

  const config = await request(token, 'GET', `${app.name}/config`);
  const required = ['apiKey', 'appId', 'messagingSenderId', 'projectId'];
  for (const field of required) {
    if (!config[field]) throw new Error(`Web config is missing ${field}.`);
  }
  if (config.projectId !== projectId) {
    throw new Error(`Config project mismatch: ${config.projectId} != ${projectId}`);
  }

  writeFileSync(OUTPUT, `${JSON.stringify(config, null, 2)}\n`, 'utf8');
  console.log(`Web app:  ${app.name}`);
  console.log(`Project:  ${config.projectId}`);
  console.log(`Wrote:    ${OUTPUT}`);
}

main().catch((error) => {
  console.error(`Firebase Web app setup failed: ${error.message}`);
  process.exit(1);
});
