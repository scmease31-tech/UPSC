# UPSC Content Scraper

Automated daily scraper for UPSC current affairs content from:
- **Drishti IAS** — Daily news analysis & editorials
- **Insights on India** — Daily current affairs & editorial analysis

## Features
- Scrapes both sites daily (4x/day via GitHub Actions)
- Deduplicates overlapping content and merges them into enriched articles
- Uploads to Firestore `articles` collection
- Newspaper content upload script for manual content
- Maps to UPSC syllabus (GS Paper, categories, tags)

## Setup

### 1. Firebase Service Account

1. Go to [Firebase Console](https://console.firebase.google.com/project/upsc-app-e2475/settings/serviceaccounts/adminsdk)
2. Click **"Generate new private key"**
3. Download the JSON file
4. Base64-encode it:
   ```powershell
   # PowerShell
   [Convert]::ToBase64String([System.IO.File]::ReadAllBytes("path\to\serviceAccountKey.json"))
   ```
   ```bash
   # Linux/Mac
   base64 -i path/to/serviceAccountKey.json
   ```

### 2. GitHub Secret

1. Go to your repo: **Settings → Secrets and variables → Actions**
2. Click **"New repository secret"**
3. Name: `FIREBASE_SERVICE_ACCOUNT_B64`
4. Value: Paste the base64 string from step 1

### 3. Enable GitHub Actions

The workflow at `.github/workflows/daily-scraper.yml` runs automatically:
- 7:00 AM IST, 12:00 PM IST, 6:00 PM IST, 11:30 PM IST

You can also trigger manually from the **Actions** tab → **Daily UPSC Content Scraper** → **Run workflow**.

## Local Usage

### Install dependencies
```bash
cd backend/content-scraper
npm install
```

### Set Firebase credentials
```bash
# Option A: Service account file
set GOOGLE_APPLICATION_CREDENTIALS=path\to\serviceAccountKey.json

# Option B: Base64 encoded
set FIREBASE_SERVICE_ACCOUNT_B64=<base64-string>
```

### Run scraper
```bash
# Scrape today's content
npm run scrape

# Scrape a specific date
node index.js --date 2026-06-19

# Scrape last 5 days
node index.js --days 5

# Dry run (test without uploading)
node index.js --dry-run
```

### Upload newspaper content
Create a markdown file (e.g., `today.md`):

```markdown
# Article Title Here
Category: Economy
Paper: GS-III

Article content goes here. Include key points:
- Point 1
- Point 2
- Point 3

---

# Next Article
Category: Polity
Paper: GS-II

More content...
```

Then upload:
```bash
node newspaper-upload.js today.md --source "The Hindu" --date 2026-06-19
```

## Architecture

```
Drishti IAS ──┐
              ├─→ Scraper ──→ Deduplicator ──→ Firestore ──→ Flutter App
Insights on   │                  (merge)        (articles)    (web + mobile)
India ────────┘
              
Newspaper ────→ newspaper-upload.js ──→ Firestore
(user .md)
```

## Content Attribution

All content includes proper source attribution:
- `newspaper` field: "Drishti IAS", "Insights on India", or "Drishti IAS + Insights on India" (merged)
- `sourceUrl` field: Original article URL
- Merged articles combine insights from both sources
