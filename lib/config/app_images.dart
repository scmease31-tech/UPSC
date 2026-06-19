/// ──────────────────────────────────────────────────────────────────────────────
/// AppImages — Centralized image URLs and asset helpers used throughout the app.
/// Uses high-quality open-licensed illustrations from Undraw & Unsplash.
/// ──────────────────────────────────────────────────────────────────────────────
class AppImages {
  AppImages._();

  // ── Onboarding illustrations (Unsplash open license) ──
  static const onboardingNews =
      'https://images.unsplash.com/photo-1504711434969-e33886168d6c?w=600&q=80';
  static const onboardingQuiz =
      'https://images.unsplash.com/photo-1456513080510-7bf3a84b82f8?w=600&q=80';
  static const onboardingFlashcards =
      'https://images.unsplash.com/photo-1532153975070-2e9ab71f1b14?w=600&q=80';
  static const onboardingTrack =
      'https://images.unsplash.com/photo-1434030216411-0b793f4b4173?w=600&q=80';

  // ── Home banners ──
  static const homeBannerStudy =
      'https://images.unsplash.com/photo-1513475382585-d06e58bcb0e0?w=800&q=80';
  static const homeBannerUpsc =
      'https://images.unsplash.com/photo-1568667256549-094345857637?w=800&q=80';

  // ── Category header images (used in news/articles) ──
  static const categoryPolity =
      'https://images.unsplash.com/photo-1555848962-6e79363ec58f?w=400&q=80';
  static const categoryEconomy =
      'https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=400&q=80';
  static const categoryEnvironment =
      'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=400&q=80';
  static const categoryScience =
      'https://images.unsplash.com/photo-1507413245164-6160d8298b31?w=400&q=80';
  static const categoryInternational =
      'https://images.unsplash.com/photo-1526470608268-f674ce90ebd4?w=400&q=80';
  static const categoryGeography =
      'https://images.unsplash.com/photo-1524661135-423995f22d0b?w=400&q=80';
  static const categoryHistory =
      'https://images.unsplash.com/photo-1461360228754-6e81c478b882?w=400&q=80';
  static const categorySocial =
      'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=400&q=80';
  static const categoryDefault =
      'https://images.unsplash.com/photo-1457369804613-52c61a468e7d?w=400&q=80';

  // ── Quiz illustrations ──
  static const quizHero =
      'https://images.unsplash.com/photo-1606326608606-aa0b62935f2b?w=600&q=80';
  static const quizCelebration =
      'https://images.unsplash.com/photo-1513151233558-d860c5398176?w=600&q=80';

  // ── Study / subjects ──
  static const studyHero =
      'https://images.unsplash.com/photo-1497633762265-9d179a990aa6?w=600&q=80';
  static const studyBooks =
      'https://images.unsplash.com/photo-1481627834876-b7833e8f5570?w=600&q=80';

  // ── Profile ──
  static const profileDefault =
      'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=200&q=80';

  // ── Magazine ──
  static const magazineCover =
      'https://images.unsplash.com/photo-1585776245991-cf89dd7fc73a?w=400&q=80';

  // ── Explore ──
  static const exploreMap =
      'https://images.unsplash.com/photo-1476610182048-b716b8518aae?w=600&q=80';

  // ── Auth / Login ──
  static const authIllustration =
      'https://images.unsplash.com/photo-1516321318423-f06f85e504b3?w=600&q=80';

  // ── Daily Challenge ──
  static const challengeHero =
      'https://images.unsplash.com/photo-1546410531-bb4caa6b424d?w=600&q=80';
  static const challengeTrophy =
      'https://images.unsplash.com/photo-1567427017947-545c5f8d16ad?w=400&q=80';

  // ── Weekly Progress ──
  static const progressHero =
      'https://images.unsplash.com/photo-1460925895917-afdab827c52f?w=600&q=80';

  // ── Flashcards ──
  static const flashcardHero =
      'https://images.unsplash.com/photo-1606326608606-aa0b62935f2b?w=600&q=80';

  // ── Content Tracker ──
  static const trackerHero =
      'https://images.unsplash.com/photo-1484480974693-6ca0a78fb36b?w=600&q=80';

  // ── Revision ──
  static const revisionHero =
      'https://images.unsplash.com/photo-1488190211105-8b0e65b80b4e?w=600&q=80';

  // ── Placeholder / fallback gradient patterns ──
  static const placeholderPattern =
      'https://images.unsplash.com/photo-1557683316-973673baf926?w=400&q=80';

  /// Get category image by name
  static String categoryImage(String? category) {
    switch (category?.toLowerCase()) {
      case 'polity':
        return categoryPolity;
      case 'economy':
        return categoryEconomy;
      case 'environment':
        return categoryEnvironment;
      case 'science':
      case 'science & tech':
        return categoryScience;
      case 'international':
        return categoryInternational;
      case 'geography':
        return categoryGeography;
      case 'history':
        return categoryHistory;
      case 'social':
        return categorySocial;
      default:
        return categoryDefault;
    }
  }

  /// Get onboarding image by page index
  static String onboardingImage(int index) {
    switch (index) {
      case 0:
        return onboardingNews;
      case 1:
        return onboardingQuiz;
      case 2:
        return onboardingFlashcards;
      case 3:
        return onboardingTrack;
      default:
        return onboardingNews;
    }
  }
}
