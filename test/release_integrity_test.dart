import 'package:flutter_test/flutter_test.dart';
import 'package:upsc_daily_edge/config/routes.dart';
import 'package:upsc_daily_edge/config/update_config.dart';
import 'package:upsc_daily_edge/data/offline_content.dart';
import 'package:upsc_daily_edge/firebase_options.dart';

void main() {
  test('Android uses the live scraper Firebase project for all data', () {
    expect(DefaultFirebaseOptions.android.projectId, 'upsc-app-e2475-e5c95');
    expect(DefaultFirebaseOptions.androidAuth.projectId, 'upsc-app-e2475-e5c95');
    expect(
      DefaultFirebaseOptions.android.projectId,
      DefaultFirebaseOptions.androidAuth.projectId,
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

  group('sideload updater security invariants', () {
    test('silent install is never permitted', () {
      expect(UpdateConfig.silentInstall, isFalse);
    });

    test('updater is enabled for sideload and disabled for Play builds', () {
      // Default (no PLAY_STORE dart-define) is a sideload build.
      expect(UpdateConfig.isPlayStoreBuild, isFalse);
      expect(UpdateConfig.sideloadUpdaterEnabled, isTrue);
    });

    test('the version manifest URL is HTTPS and on the allowlist', () {
      expect(UpdateConfig.versionManifestUrl, startsWith('https://'));
      expect(UpdateConfig.isAllowedUrl(UpdateConfig.versionManifestUrl), isTrue);
    });

    test('only allowlisted HTTPS origins pass the URL guard', () {
      expect(
        UpdateConfig.isAllowedUrl('https://scmease31-tech.github.io/UPSC/app.apk'),
        isTrue,
      );
      expect(
        UpdateConfig.isAllowedUrl('https://evil.example.com/app.apk'),
        isFalse,
      );
      expect(
        UpdateConfig.isAllowedUrl('http://scmease31-tech.github.io/UPSC/app.apk'),
        isFalse,
        reason: 'plain HTTP must be rejected',
      );
      expect(UpdateConfig.isAllowedUrl('not a url'), isFalse);
      expect(UpdateConfig.isAllowedUrl(''), isFalse);
    });
  });
}
