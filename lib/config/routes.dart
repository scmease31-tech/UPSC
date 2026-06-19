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

  static Map<String, WidgetBuilder> get routes {
    return {
      splash: (_) => const SplashScreen(),
      main: (_) => const MainNavigation(),
      onboarding: (_) => const OnboardingScreen(),
      articleDetail: (_) => const ArticleDetailScreen(),
      quizPlay: (_) => const QuizPlayScreen(),
      quizResult: (_) => const QuizResultScreen(),
      subjectDetail: (_) => const SubjectDetailScreen(),
      magazine: (_) => const MagazineScreen(),
      login: (_) => const LoginScreen(),
      signup: (_) => const SignupScreen(),
      dailyPractice: (_) => const DailyPracticeScreen(),
      explore: (_) => const ExploreScreen(),
      dailyChallenge: (_) => const DailyChallengeScreen(),
      revision: (_) => const RevisionScreen(),
      upscMustKnow: (_) => const UpscMustKnowScreen(),
      weeklyProgress: (_) => const WeeklyProgressScreen(),
      flashcards: (_) => const FlashcardScreen(),
      contentTracker: (_) => const ContentTrackerScreen(),
      pyq: (_) => const PYQScreen(),
      studyTimer: (_) => const StudyTimerScreen(),
      quickRevision: (_) => const QuickRevisionScreen(),
      answerWriting: (_) => const AnswerWritingScreen(),
      currentAffairs: (_) => const CurrentAffairsScreen(),
      syllabusTracker: (_) => const SyllabusTrackerScreen(),
      vocabulary: (_) => const VocabularyBuilderScreen(),
      mockTest: (_) => const MockTestScreen(),
      govtSchemes: (_) => const GovtSchemesScreen(),
      aiSearch: (_) => const AiSearchScreen(),
    };
  }
}
