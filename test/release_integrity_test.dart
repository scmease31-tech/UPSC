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

    test('the APK can only come from the project Pages origin', () {
      // The allowlist is one origin on purpose. Users are never sent to the
      // repository for a build, and release assets are per-ABI with a lower
      // versionCode than the APK the updater manages — installing one would
      // desync the device from the update channel.
      expect(UpdateConfig.allowedOrigins,
          ['https://scmease31-tech.github.io']);

      for (final repoUrl in <String>[
        'https://github.com/scmease31-tech/UPSC/releases/latest/download/UPSC-Daily-Edge.apk',
        'https://objects.githubusercontent.com/some/asset.apk',
        'https://release-assets.githubusercontent.com/some/asset.apk',
        'https://raw.githubusercontent.com/scmease31-tech/UPSC/main/app.apk',
      ]) {
        expect(UpdateConfig.isAllowedUrl(repoUrl), isFalse,
            reason: 'the updater must refuse a repository download: $repoUrl');
      }
    });

    test('a lookalike host cannot pass as the Pages origin', () {
      for (final url in <String>[
        'https://scmease31-tech.github.io.evil.com/app.apk',
        'https://evil-scmease31-tech.github.io/app.apk',
        'https://scmease31-tech.github.io:8443/app.apk',
      ]) {
        expect(UpdateConfig.isAllowedUrl(url), isFalse, reason: url);
      }
    });
  });
}
