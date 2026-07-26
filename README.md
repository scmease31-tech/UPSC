# UPSC Daily Edge

A premium Flutter app for UPSC exam preparation — daily current affairs, quizzes, flashcards, study tools, and AI-powered search in one place.

## Features

- **Daily Current Affairs** — Auto-scraped from Drishti IAS & Insights on India, uploaded to Firestore
- **Quiz Engine** — Category-wise MCQs with timer, scoring, and weekly stats
- **Study Tools** — Flashcards, vocabulary builder, answer writing practice, PYQ bank
- **AI Search** — Gemini-powered contextual search across all content
- **Progress Tracking** — Streaks, daily goals, weekly progress, syllabus tracker
- **In-App Updates** — Auto-detects new releases from GitHub and prompts to install
- **Responsive** — Adaptive layouts for mobile and web (sidebar nav on wide screens)
- **Dark Mode** — Full glassmorphic dark theme with persistence

## Adding a newspaper — upload and it's in the app

Drop any newspaper PDF into the [`inbox/`](inbox/) folder on GitHub (Add file →
Upload files → Commit). The **Newspaper Inbox** workflow extracts the articles —
running OCR when the PDF is a scan with no text layer — uploads them to
Firestore, clears the file and logs the result in `inbox/PROCESSED.md`. Pull to
refresh in the app.

Works from a phone browser, needs no local setup, and runs entirely on the free
GitHub Actions and Firebase tiers. Full instructions: [`inbox/README.md`](inbox/README.md).

## Content pipeline

| Source | How it runs | Lands in |
| --- | --- | --- |
| Drishti IAS + Insights on India | `daily-scraper.yml`, 4×/day | `articles`, `pyqs`, `flashcards`, `vocabulary`, `govtSchemes` |
| Newspaper or question paper you upload | `newspaper-inbox.yml`, on upload | `articles`, `pyqs`, `flashcards`, `vocabulary`, `govtSchemes` |
| Official UPSC papers from upsc.gov.in | `upsc-papers.yml`, manual | `pyqs` |
| Everything already stored | `repair-articles.yml`, weekly | re-derives all of the above |
| PDFs on your own machine | `node backend/content-scraper/daily-ingest.js` | same as above |

**Keeping the archive current.** The pipeline keeps improving, so older articles
sit at older quality levels. `repair-articles.js` walks the whole collection
weekly: articles with their own source page are re-fetched and re-parsed, the
rest have reading structure imposed on the stored text, missing artwork is
looked up, and then vocabulary, PYQs, schemes and flashcards are re-derived from
the full history. Re-running is safe — current articles are skipped and every
derived collection de-duplicates on write.

The Drishti scraper reads each article's own page rather than the daily index,
which is what supplies real headline artwork, the section structure used by the
reader view, and the verbatim previous-year questions that grow the PYQ tab.

**Article artwork.** Sources sometimes publish with no image. The pipeline then
looks for an openly-licensed topic image (Wikipedia / Wikimedia Commons) and
stores it with its attribution. A match is only accepted when it is
demonstrably about the same subject — a wrong-but-pretty photo is worse than the
app's own generated cover, which is what an article falls back to.

**Daily vocabulary** is mined from the day's articles: uncommon editorial-register
words, filtered against a common-word list and their inflections, then defined via
the free Dictionary API and shown with the sentence they appeared in.

**Official papers.** UPSC publishes Civil Services papers as image-only scans with
no answer keys, so `upsc-papers.js` OCRs them (English + Hindi, so the Hindi half
can be recognised and stripped) and stores questions unkeyed. Anything OCR renders
too noisily is dropped rather than published.

## Architecture

```
lib/
├── config/          # Theme, routes, constants, image registry
├── data/            # Dummy/seed data for offline fallback
├── models/          # Data classes (Article, QuizQuestion, Subject, UserProfile)
├── providers/       # ChangeNotifier state management (Provider)
├── screens/         # Feature screens organized by domain
│   ├── home/        # Dashboard with progress, quick actions, trending
│   ├── news/        # Article list, detail, date-grouped layout
│   ├── quiz/        # Quiz play, results
│   ├── study/       # Subject explorer, study timer
│   ├── features/    # Flashcards, PYQ, vocab, revision, mock tests
│   ├── profile/     # Auth, settings, bookmarks
│   ├── explore/     # Daily practice, explore grid
│   ├── search/      # AI-powered search
│   └── web/         # Web-specific shell and wrappers
├── services/        # Firebase, notifications, ads, Gemini, update checker
├── utils/           # Constants, helpers
└── widgets/         # Reusable UI components (GlassCard, ArticleCard, etc.)
```

## Tech Stack

| Layer | Choice |
|-------|--------|
| Framework | Flutter 3.x (Material 3) |
| State | Provider (ChangeNotifier) |
| Backend | Firebase (Firestore, Auth, Storage, Messaging) |
| Typography | Google Fonts (Plus Jakarta Sans, Inter) |
| Images | CachedNetworkImage + Shimmer placeholders |
| AI | Google Gemini API |
| Ads | Google Mobile Ads |
| CI/CD | GitHub Actions (APK build on tag, daily scraper) |

## Getting Started

```bash
# Clone and install
git clone https://github.com/scmease31-tech/UPSC.git
cd UPSC
flutter pub get

# Run on device/emulator
flutter run

# Build release APK
flutter build apk --release
```

### Prerequisites

- Flutter SDK >= 3.1.0
- Firebase project configured (`google-services.json` already included)
- Android SDK for APK builds

## Release Flow

Releases are tag-based. To ship an update:

```bash
# 1. Bump version in pubspec.yaml
# 2. Commit and push
git add -A && git commit -m "v1.0.4: description"
git push

# 3. Tag and push — triggers CI build + release
git tag v1.0.4
git push origin v1.0.4
```

The CI workflow builds the APK, creates a GitHub Release, and deploys the APK to GitHub Pages for in-app auto-update.

## Project Conventions

- **Theme** — All colors, gradients, shadows, spacing defined in `lib/config/theme.dart`
- **Widgets** — Reusable glassmorphic components in `lib/widgets/`
- **Routing** — Centralized named routes in `lib/config/routes.dart`
- **Services** — Firestore access via `ApiContentService` with tiered caching
- **Lint** — Strict analysis rules in `analysis_options.yaml`

## License

Private repository. All rights reserved.
