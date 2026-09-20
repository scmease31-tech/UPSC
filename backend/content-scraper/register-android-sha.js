import { cert, initializeApp } from 'firebase-admin/app';

const API = 'https://firebase.googleapis.com/v1beta1';
const DEFAULT_ANDROID_APP_ID = '1:906645524405:android:838f1c73e83ff7a0dc53fc';

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

function normalizeSha(value) {
  const hex = String(value ?? '').replace(/[^a-fA-F0-9]/g, '').toUpperCase();
  if (!/^[A-F0-9]{40}$/.test(hex)) {
    throw new Error('ANDROID_SIGNING_SHA1 must contain exactly 40 hexadecimal characters.');
  }
  return hex.match(/.{2}/g).join(':');
}

async function request(token, method, url, body) {
  const response = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  const data = text ? JSON.parse(text) : {};
  if (!response.ok) {
    const error = new Error(`${method} ${url} → HTTP ${response.status}: ${text.slice(0, 500)}`);
    error.status = response.status;
    throw error;
  }
  return data;
}

async function main() {
  const serviceAccount = loadServiceAccount();
  const projectId = serviceAccount.project_id;
  const appId = process.env.FIREBASE_ANDROID_APP_ID || DEFAULT_ANDROID_APP_ID;
  const shaHash = normalizeSha(process.env.ANDROID_SIGNING_SHA1);
  const token = await accessToken(serviceAccount);
  const parent = `projects/${projectId}/androidApps/${appId}`;
  const endpoint = `${API}/${parent}/sha`;

  console.log(`Firebase project: ${projectId}`);
  console.log(`Android app:      ${appId}`);
  console.log(`Signing SHA-1:    ${shaHash}`);

  const existing = await request(token, 'GET', endpoint);
  const certificates = existing.certificates ?? [];
  if (certificates.some((item) => normalizeSha(item.shaHash) === shaHash)) {
    console.log('SHA-1 is already registered.');
    return;
  }

  try {
    await request(token, 'POST', endpoint, {
      shaHash,
      certType: 'SHA_1',
    });
  } catch (error) {
    if (error.status === 409) {
      console.log('SHA-1 was already registered concurrently.');
      return;
    }
    throw error;
  }

  console.log('SHA-1 registered successfully.');
}

main().catch((error) => {
  console.error(`Firebase SHA registration failed: ${error.message}`);
  process.exit(1);
});
