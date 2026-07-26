# Inbox — drop a newspaper here

Put a newspaper PDF in this folder and it turns into readable articles inside
the app. No commands, no setup, no cost.

## The whole workflow

1. Open this folder on GitHub: **`inbox/`**
2. **Add file → Upload files** → drag the PDF in → **Commit changes**
3. Wait about a minute (watch it under the repo's **Actions** tab)
4. Open the app → **News** tab → pull down to refresh

That's it. The file disappears from `inbox/` once it has been processed, and a
line is added to [`PROCESSED.md`](PROCESSED.md) saying what came out of it.

You can do all of this from a phone browser.

## What gets extracted

| From | Into the app |
| --- | --- |
| Newspaper / editorial pages | Articles in the **News** tab, plus flashcards |
| Any government scheme mentioned | **Govt Schemes** |
| Hard words used in the day's articles | **Vocabulary**, defined automatically |
| A "Daily Vocabulary" PDF | **Vocabulary** |
| A question paper | **Previous Year Questions** |

Scanned PDFs — the kind with no selectable text — are handled too: the workflow
rasterises the pages and runs OCR over them.

### Question papers

Name the file so it says which exam and year it is, and it becomes PYQs:

```
UPSC Prelims 2023 PYQ.pdf
CSAT 2024 Paper II.pdf
Mains 2022 GS Paper 3.pdf
QP-CSM-23-GENERAL-STUDIES-PAPER-II.pdf
```

A paper that has real (selectable) text parses almost completely. UPSC's own
scans have no text layer at all, so those go through OCR and extraction is
partial — anything the OCR renders too noisily to trust is dropped rather than
published as a garbled question.

You don't have to download UPSC's papers yourself: **Actions → UPSC Question
Papers → Run workflow** fetches them straight from upsc.gov.in.

Note that UPSC publishes question papers **without answer keys**, so official
questions appear in the app with their options but are not scored. Where the
daily Drishti scrape quotes the same question with its key, the app shows the
answerable copy instead.

## Naming (optional, but it helps)

The source name is read from the filename. Any of these work:

```
The Hindu 25-07-2026.pdf
TH Delhi 25.07.2026.pdf
IE Delhi 25-07-2026.pdf
TOI_25_07_2026.pdf
Daily Vocabulary 25-07-2026.pdf
Editorials week 30.pdf
```

Recognised sources: The Hindu, Indian Express, Times of India, Business
Standard, Mint, Economic Times, Hindustan Times, PIB, Yojana, Kurukshetra,
Down To Earth.

A file that matches none of them is still ingested — it is treated as a
newspaper named after the file, so nothing is ever silently dropped.

The date in the filename becomes the article date. Without one, today's date is
used.

## Other ways in

**From a link** — if the paper is already online, you don't need to download it:
Actions → *Newspaper Inbox* → **Run workflow** → paste the PDF URL.

**From your computer** — if you'd rather not upload:

```bash
node backend/content-scraper/inbox-ingest.js --dir "C:/Users/you/Downloads"
```

## If something doesn't appear

- A failed file is **left in `inbox/`** on purpose, so it can be retried.
- The Actions log says exactly what happened — look for `[read]`, `[ocr ]`,
  `[parse]` and `[done]` lines.
- A scan with very poor print quality can defeat OCR. Re-uploading a sharper
  copy usually fixes it.

## Requirements

One repository secret, `FIREBASE_SERVICE_ACCOUNT_B64` — the base64 of the
Firebase Admin service-account JSON. The daily scraper already uses it, so if
that workflow works, this one does too.
