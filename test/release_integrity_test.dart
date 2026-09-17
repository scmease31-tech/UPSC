import 'package:flutter_test/flutter_test.dart';
import 'package:upsc_daily_edge/config/routes.dart';
import 'package:upsc_daily_edge/data/offline_content.dart';
import 'package:upsc_daily_edge/firebase_options.dart';

void main() {
  test('Android content and authentication projects stay intentionally split', () {
    expect(DefaultFirebaseOptions.android.projectId, 'upsc-app-e2475');
    expect(DefaultFirebaseOptions.androidAuth.projectId, 'upsc-app-e2475-e5c95');
    expect(
      DefaultFirebaseOptions.android.projectId,
      isNot(DefaultFirebaseOptions.androidAuth.projectId),
    );
  });

  test('Firestore-backed pages have embedded non-empty fallbacks', () {
    expect(OfflineContent.govtSchemes, isNotEmpty);
    expect(OfflineContent.mockTests, isNotEmpty);
    expect(OfflineContent.revisionNotes, isNotEmpty);
    expect(OfflineContent.currentAffairs, isNotEmpty);
    expect(
      OfflineContent.mockTests.every(
        (test) => (test['questions'] as List<dynamic>).isNotEmpty,
      ),
      isTrue,
    );
  });

  test('every public application route is registered', () {
    final routes = AppRoutes.routes;
    for (final route in <String>[
      AppRoutes.splash,
      AppRoutes.main,
      AppRoutes.onboarding,
      AppRoutes.articleDetail,
      AppRoutes.quizPlay,
      AppRoutes.quizResult,
      AppRoutes.subjectDetail,
      AppRoutes.magazine,
      AppRoutes.login,
      AppRoutes.signup,
      AppRoutes.dailyPractice,
      AppRoutes.explore,
      AppRoutes.dailyChallenge,
      AppRoutes.revision,
      AppRoutes.upscMustKnow,
      AppRoutes.weeklyProgress,
      AppRoutes.flashcards,
      AppRoutes.contentTracker,
      AppRoutes.pyq,
      AppRoutes.studyTimer,
      AppRoutes.quickRevision,
      AppRoutes.answerWriting,
      AppRoutes.currentAffairs,
      AppRoutes.syllabusTracker,
      AppRoutes.vocabulary,
      AppRoutes.mockTest,
      AppRoutes.govtSchemes,
      AppRoutes.bookmarks,
      AppRoutes.aiSearch,
      AppRoutes.credits,
    ]) {
      expect(routes, contains(route), reason: 'Missing route: $route');
    }
  });
}
