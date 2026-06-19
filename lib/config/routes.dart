import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../screens/splash_screen.dart';
import '../screens/main_navigation.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/news/article_detail_screen.dart';
import '../screens/quiz/quiz_play_screen.dart';
import '../screens/quiz/quiz_result_screen.dart';
import '../screens/study/subject_detail_screen.dart';
import '../screens/magazine/magazine_screen.dart';
import '../screens/profile/login_screen.dart';
import '../screens/profile/signup_screen.dart';
import '../screens/explore/daily_practice_screen.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/features/daily_challenge_screen.dart';
import '../screens/features/revision_screen.dart';
import '../screens/features/upsc_must_know_screen.dart';
import '../screens/features/weekly_progress_screen.dart';
import '../screens/features/flashcard_screen.dart';
import '../screens/features/content_tracker_screen.dart';
import '../screens/features/pyq_screen.dart';
import '../screens/features/study_timer_screen.dart';
import '../screens/features/quick_revision_screen.dart';
import '../screens/features/answer_writing_screen.dart';
import '../screens/features/current_affairs_screen.dart';
import '../screens/features/syllabus_tracker_screen.dart';
import '../screens/features/vocabulary_screen.dart';
import '../screens/features/mock_test_screen.dart';
import '../screens/features/govt_schemes_screen.dart';
import '../screens/search/ai_search_screen.dart';
import '../screens/web/web_wrappers.dart';

/// Centralized route configuration.
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String main = '/main';
  static const String onboarding = '/onboarding';
  static const String articleDetail = '/article-detail';
  static const String quizPlay = '/quiz-play';
  static const String quizResult = '/quiz-result';
  static const String subjectDetail = '/subject-detail';
  static const String magazine = '/magazine';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String dailyPractice = '/daily-practice';
  static const String explore = '/explore';
  static const String dailyChallenge = '/daily-challenge';
  static const String revision = '/revision';
  static const String upscMustKnow = '/upsc-must-know';
  static const String weeklyProgress = '/weekly-progress';
  static const String flashcards = '/flashcards';
  static const String contentTracker = '/content-tracker';
  static const String pyq = '/pyq';
  static const String studyTimer = '/study-timer';
  static const String quickRevision = '/quick-revision';
  static const String answerWriting = '/answer-writing';
  static const String currentAffairs = '/current-affairs';
  static const String syllabusTracker = '/syllabus-tracker';
  static const String vocabulary = '/vocabulary';
  static const String mockTest = '/mock-test';
  static const String govtSchemes = '/govt-schemes';
  static const String aiSearch = '/ai-search';

  /// Wraps auth screens with web-friendly split layout on web.
  static Widget _authWrap(Widget child) {
    if (!kIsWeb) return child;
    return WebAuthScaffold(child: child);
  }

  /// Wraps feature screens with web header and constrained layout on web.
  static Widget _featureWrap(Widget child, [String title = '']) {
    if (!kIsWeb) return child;
    return WebFeatureScaffold(title: title, child: child);
  }

  static Map<String, WidgetBuilder> get routes {
    return {
      splash: (_) => const SplashScreen(),
      main: (_) => const MainNavigation(),
      onboarding: (_) => const OnboardingScreen(),
      // Auth — web split layout
      login: (_) => _authWrap(const LoginScreen()),
      signup: (_) => _authWrap(const SignupScreen()),
      // Content — web header + constrained
      articleDetail: (_) => _featureWrap(const ArticleDetailScreen(), 'Article'),
      quizPlay: (_) => _featureWrap(const QuizPlayScreen(), 'Quiz'),
      quizResult: (_) => _featureWrap(const QuizResultScreen(), 'Results'),
      subjectDetail: (_) => _featureWrap(const SubjectDetailScreen(), 'Subject'),
      magazine: (_) => _featureWrap(const MagazineScreen(), 'Magazine'),
      dailyPractice: (_) => _featureWrap(const DailyPracticeScreen(), 'Daily Practice'),
      explore: (_) => _featureWrap(const ExploreScreen(), 'Explore'),
      dailyChallenge: (_) => _featureWrap(const DailyChallengeScreen(), 'Daily Challenge'),
      revision: (_) => _featureWrap(const RevisionScreen(), 'Revision'),
      upscMustKnow: (_) => _featureWrap(const UpscMustKnowScreen(), 'Must Know'),
      weeklyProgress: (_) => _featureWrap(const WeeklyProgressScreen(), 'Weekly Progress'),
      flashcards: (_) => _featureWrap(const FlashcardScreen(), 'Flashcards'),
      contentTracker: (_) => _featureWrap(const ContentTrackerScreen(), 'Content Tracker'),
      pyq: (_) => _featureWrap(const PYQScreen(), 'Previous Year Questions'),
      studyTimer: (_) => _featureWrap(const StudyTimerScreen(), 'Study Timer'),
      quickRevision: (_) => _featureWrap(const QuickRevisionScreen(), 'Quick Revision'),
      answerWriting: (_) => _featureWrap(const AnswerWritingScreen(), 'Answer Writing'),
      currentAffairs: (_) => _featureWrap(const CurrentAffairsScreen(), 'Current Affairs'),
      syllabusTracker: (_) => _featureWrap(const SyllabusTrackerScreen(), 'Syllabus Tracker'),
      vocabulary: (_) => _featureWrap(const VocabularyBuilderScreen(), 'Vocabulary'),
      mockTest: (_) => _featureWrap(const MockTestScreen(), 'Mock Test'),
      govtSchemes: (_) => _featureWrap(const GovtSchemesScreen(), 'Govt Schemes'),
      aiSearch: (_) => _featureWrap(const AiSearchScreen(), 'AI Search'),
    };
  }
}
