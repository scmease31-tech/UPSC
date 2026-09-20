// Fetches the CURRENT google-services.json for the Android app straight from
// the Firebase Management API and writes it to android/app/google-services.json.
//
// register-android-sha.js registers a signing SHA-1 with the Firebase project,
// which creates the matching OAuth client server-side. That alone is not enough:
// Google Sign-In reads the oauth_client list baked into the APK's
// google-services.json, so a stale file means the app never sees the client for
// its own signing certificate and sign-in fails with no usable ID token.
//
// Running this after a SHA registration pulls the regenerated config, so the
// committed file and the Firebase project agree.
//
// Needs FIREBASE_SERVICE_ACCOUNT_B64. Same credential as deploy-rules.js, so it
// works without Firebase Console access.

import { writeFileSync } from 'node:fs';
import { cert, initializeApp } from 'firebase-admin/app';

const API = 'https://firebase.googleapis.com/v1beta1';
const DEFAULT_ANDROID_APP_ID = '1:906645524405:android:838f1c73e83ff7a0dc53fc';
const DEFAULT_OUTPUT = 'android/app/google-services.json';

function loadServiceAccount() {
  const b64 = process.env.FIREBASE_SERVICE_ACCOUNT_B64;
  if (!b64) {
    throw new Error('Missing FIREBASE_SERVICE_ACCOUNT_B64.');
  }
  return JSON.parse(Buffer.from(b64, 'base64').toString('utf-8'));
}

async function accessToken(serviceAccount) {
  const credential = cert(serviceAccount);
  try {
    initializeApp({ credential });
  } catch {
    // A prior Firebase helper may already have initialized the Admin SDK.
  }
  const token = await credential.getAccessToken();
  return token.access_token;
}

function shaList(config) {
  const client = (config.client ?? [])[0] ?? {};
  return (client.oauth_client ?? [])
    .filter((entry) => entry.client_type === 1)
    .map((entry) => (entry.android_info?.certificate_hash ?? '').toLowerCase())
    .filter(Boolean);
}

async function main() {
  const serviceAccount = loadServiceAccount();
  const projectId = serviceAccount.project_id;
  const appId = process.env.FIREBASE_ANDROID_APP_ID || DEFAULT_ANDROID_APP_ID;
  const output = process.env.GOOGLE_SERVICES_OUTPUT || DEFAULT_OUTPUT;
  const token = await accessToken(serviceAccount);

  const url = `${API}/projects/${projectId}/androidApps/${appId}/config`;
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`GET ${url} → HTTP ${response.status}: ${text.slice(0, 500)}`);
  }

  const payload = JSON.parse(text);
  if (!payload.configFileContents) {
    throw new Error('Response contained no configFileContents.');
  }
  const contents = Buffer.from(payload.configFileContents, 'base64').toString('utf-8');

  // Parse before writing so a malformed response cannot clobber a good file.
  const config = JSON.parse(contents);
  const hashes = shaList(config);

  writeFileSync(output, `${JSON.stringify(config, null, 2)}\n`, 'utf-8');

  console.log(`Firebase project: ${projectId}`);
  console.log(`Android app:      ${appId}`);
  console.log(`Wrote:            ${output}`);
  console.log(`Registered SHA-1 certificate hashes (${hashes.length}):`);
  for (const hash of hashes) {
    console.log(`  ${hash}`);
  }

  const expected = (process.env.ANDROID_SIGNING_SHA1 ?? '')
    .replace(/[^a-fA-F0-9]/g, '')
    .toLowerCase();
  if (expected) {
    if (hashes.includes(expected)) {
      console.log(`Upload key ${expected} is present. Google Sign-In will work.`);
    } else {
      console.error(
        `::error::Upload key ${expected} is NOT in the fetched config. ` +
          'Google Sign-In will fail in a build signed with that key.',
      );
      process.exit(1);
    }
  }
}

main().catch((error) => {
  console.error(`google-services.json fetch failed: ${error.message}`);
  process.exit(1);
});
