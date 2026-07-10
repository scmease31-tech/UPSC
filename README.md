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
