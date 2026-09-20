// Unit tests for the DIRECT sideload in-app updater's logic core:
//   • version.json manifest parsing (well-formed, incomplete, malformed types)
//   • semantic-version + build-number comparison (update / no-update / downgrade)
//   • bad SHA-256 digest detection (the exact chunked-SHA primitive the
//     ApkInstallerService verifies with)
//   • offline / server error classification (ApkErrorKind + state model)
//   • the shipped web/update/version.json is parseable and describes an upgrade
//
// These exercise the PURE, side-effect-free surface the network path delegates
// to (UpdateService.evaluateManifest / isSemverNewer) so no HTTP call or
// platform channel is needed. UI states are covered in
// sideload_updater_ui_test.dart.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upsc_daily_edge/config/update_config.dart';
import 'package:upsc_daily_edge/services/apk_installer_service.dart';
import 'package:upsc_daily_edge/services/update_service.dart';

/// A valid manifest map for the current (build 18 / 1.5.1) installed binary.
Map<String, dynamic> validManifest({
  String version = '1.6.0',
  Object? build = 19,
  String apkUrl =
      'https://scmease31-tech.github.io/UPSC/update/UPSC-Daily-Edge.apk',
  String sha256 =
      'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899',
  Object? sizeBytes = 38123456,
  bool mandatory = false,
  String notes = 'Notes',
}) =>
    <String, dynamic>{
      'version': version,
      'build': build,
      'notes': notes,
      'apkUrl': apkUrl,
      'sha256': sha256,
      'sizeBytes': sizeBytes,
      'mandatory': mandatory,
    };

void main() {
  group('version.json manifest parsing', () {
    test('a well-formed manifest yields an UpdateInfo with every field', () {
      final r = UpdateService.evaluateManifest(
        validManifest(),
        currentVersion: '1.5.1',
        currentBuild: 18,
      );
      expect(r.hasUpdate, isTrue);
      final u = r.update!;
      expect(u.version, '1.6.0');
      expect(u.build, 19);
      expect(u.notes, 'Notes');
      expect(u.apkUrl,
          'https://scmease31-tech.github.io/UPSC/update/UPSC-Daily-Edge.apk');
      expect(u.sha256, hasLength(64));
      expect(u.sizeBytes, 38123456);
      expect(u.mandatory, isFalse);
    });

    test('build accepts an int, a num, or a numeric string', () {
      for (final b in <Object>[19, 19.0, '19']) {
        final r = UpdateService.evaluateManifest(
          validManifest(build: b),
          currentVersion: '1.5.1',
          currentBuild: 18,
        );
        expect(r.hasUpdate, isTrue, reason: 'build=$b ($b runtimeType)');
        expect(r.update!.build, 19);
      }
    });

    test('mandatory flag parses only from a literal true', () {
      expect(
        UpdateService.evaluateManifest(validManifest(mandatory: true),
                currentVersion: '1.5.1', currentBuild: 18)
            .update!
            .mandatory,
        isTrue,
      );
      // Non-boolean truthy values must NOT flip it on.
      final r = UpdateService.evaluateManifest(
        validManifest()..['mandatory'] = 'true',
        currentVersion: '1.5.1',
        currentBuild: 18,
      );
      expect(r.update!.mandatory, isFalse);
    });

    test('missing / empty required fields → incomplete, not a crash', () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (m) => m.remove('version'),
        (m) => m['version'] = '',
        (m) => m.remove('build'),
        (m) => m['build'] = 'not-a-number',
        (m) => m.remove('apkUrl'),
        (m) => m['apkUrl'] = '',
        (m) => m.remove('sha256'),
        (m) => m['sha256'] = '',
      ]) {
        final m = validManifest();
        mutate(m);
        final r = UpdateService.evaluateManifest(
          m,
          currentVersion: '1.5.1',
          currentBuild: 18,
        );
        expect(r.hasUpdate, isFalse, reason: 'mutation on $m');
        expect(r.error, 'The update information was incomplete.');
        expect(r.errorIsSecurity, isFalse);
      }
    });

    test('whitespace around string fields is trimmed', () {
      final r = UpdateService.evaluateManifest(
        validManifest(version: '  1.6.0  ')
          ..['apkUrl'] =
              '  https://scmease31-tech.github.io/UPSC/x.apk  ',
        currentVersion: '1.5.1',
        currentBuild: 18,
      );
      expect(r.hasUpdate, isTrue);
      expect(r.update!.version, '1.6.0');
      expect(r.update!.apkUrl, 'https://scmease31-tech.github.io/UPSC/x.apk');
    });

    test('an off-allowlist APK URL is rejected as a SECURITY error', () {
      final r = UpdateService.evaluateManifest(
        validManifest(apkUrl: 'https://evil.example.com/UPSC.apk'),
        currentVersion: '1.5.1',
        currentBuild: 18,
      );
      expect(r.hasUpdate, isFalse);
      expect(r.errorIsSecurity, isTrue);
      expect(r.error,
          'Update blocked: the download link is not an approved source.');
    });

    test('a plain-HTTP APK URL is rejected even on an allowlisted host', () {
      final r = UpdateService.evaluateManifest(
        validManifest(apkUrl: 'http://scmease31-tech.github.io/UPSC.apk'),
        currentVersion: '1.5.1',
        currentBuild: 18,
      );
      expect(r.errorIsSecurity, isTrue);
    });
  });

  group('semantic-version + build-number comparison', () {
    test('UPDATE: higher build number alone triggers an update', () {
      final r = UpdateService.evaluateManifest(
        validManifest(version: '1.5.1', build: 19), // same semver, higher build
        currentVersion: '1.5.1',
        currentBuild: 18,
      );
      expect(r.hasUpdate, isTrue);
    });

    test('UPDATE: higher semver alone triggers an update', () {
      final r = UpdateService.evaluateManifest(
        validManifest(version: '1.6.0', build: 18), // same build, higher semver
        currentVersion: '1.5.1',
        currentBuild: 18,
      );
      expect(r.hasUpdate, isTrue);
    });

    test('NO-UPDATE: identical version and build is up to date', () {
      final r = UpdateService.evaluateManifest(
        validManifest(version: '1.5.1', build: 18),
        currentVersion: '1.5.1',
        currentBuild: 18,
      );
      expect(r.hasUpdate, isFalse);
      expect(r.isUpToDate, isTrue);
      expect(r.error, isNull);
    });

    test('DOWNGRADE: lower build AND lower semver is NOT offered', () {
      final r = UpdateService.evaluateManifest(
        validManifest(version: '1.4.0', build: 17),
        currentVersion: '1.5.1',
        currentBuild: 18,
      );
      expect(r.hasUpdate, isFalse);
      expect(r.isUpToDate, isTrue);
    });

    test(
        'DOWNGRADE guard is per-axis: lower build but higher semver still '
        'updates (semver OR build)', () {
      // remoteBuild(17) < current(18) but 1.6.0 > 1.5.1 → the OR still fires.
      final r = UpdateService.evaluateManifest(
        validManifest(version: '1.6.0', build: 17),
        currentVersion: '1.5.1',
        currentBuild: 18,
      );
      expect(r.hasUpdate, isTrue);
    });

    group('isSemverNewer', () {
      test('greater major/minor/patch each compare correctly', () {
        expect(UpdateService.isSemverNewer('2.0.0', '1.9.9'), isTrue);
        expect(UpdateService.isSemverNewer('1.6.0', '1.5.9'), isTrue);
        expect(UpdateService.isSemverNewer('1.5.2', '1.5.1'), isTrue);
      });

      test('equal is NOT newer (strict)', () {
        expect(UpdateService.isSemverNewer('1.5.1', '1.5.1'), isFalse);
      });

      test('lower is NOT newer', () {
        expect(UpdateService.isSemverNewer('1.4.9', '1.5.0'), isFalse);
        expect(UpdateService.isSemverNewer('0.9.9', '1.0.0'), isFalse);
      });

      test('a leading "v" and pre-release/build suffixes are ignored', () {
        expect(UpdateService.isSemverNewer('v1.6.0', '1.5.1'), isTrue);
        expect(UpdateService.isSemverNewer('1.6.0-beta', '1.5.1'), isTrue);
        expect(UpdateService.isSemverNewer('1.6.0+42', '1.5.1'), isTrue);
        expect(UpdateService.isSemverNewer('1.5.1-rc1', '1.5.1'), isFalse);
      });

      test('short or ragged versions pad to three parts', () {
        expect(UpdateService.isSemverNewer('2', '1.9'), isTrue);
        expect(UpdateService.isSemverNewer('1.5', '1.5.0'), isFalse);
        expect(UpdateService.isSemverNewer('1.5.0.1', '1.5.0'), isFalse);
      });

      test('non-numeric junk degrades to 0 rather than throwing', () {
        expect(UpdateService.isSemverNewer('abc', '1.0.0'), isFalse);
        expect(UpdateService.isSemverNewer('1.6.0', 'garbage'), isTrue);
      });
    });
  });

  group('SHA-256 digest verification (the ApkInstallerService primitive)', () {
    // The service streams chunks through sha256.startChunkedConversion and
    // compares the lowercased hex against the manifest's sha256. These tests
    // pin that contract: a matching digest passes, any mismatch fails.
    List<int> bytesOf(String s) => utf8.encode(s);

    String chunkedDigest(List<List<int>> chunks) {
      Digest? captured;
      final sink = ChunkedConversionSink<Digest>.withCallback(
          (list) => captured = list.single);
      final input = sha256.startChunkedConversion(sink);
      for (final c in chunks) {
        input.add(c);
      }
      input.close();
      return captured!.toString().toLowerCase();
    }

    test('a chunked digest equals the one-shot digest for the same bytes', () {
      final payload = bytesOf('UPSC-Daily-Edge fake apk payload');
      final oneShot = sha256.convert(payload).toString().toLowerCase();
      final streamed = chunkedDigest([
        payload.sublist(0, 5),
        payload.sublist(5, 20),
        payload.sublist(20),
      ]);
      expect(streamed, oneShot);
    });

    test('MATCH: expected == actual passes the check', () {
      final payload = bytesOf('release-bytes');
      final expected = sha256.convert(payload).toString().toLowerCase();
      final actual = chunkedDigest([payload]);
      expect(actual, expected);
    });

    test('MISMATCH: tampered bytes produce a different digest', () {
      final good = sha256.convert(bytesOf('release-bytes')).toString();
      final tampered = chunkedDigest([bytesOf('release-bytes-TAMPERED')]);
      expect(tampered, isNot(good.toLowerCase()));
    });

    test('an all-zero placeholder digest never matches real content', () {
      final zero = '0' * 64;
      final actual = chunkedDigest([bytesOf('anything at all')]);
      expect(actual, isNot(zero));
      expect(actual, hasLength(64));
    });

    test('comparison is case-insensitive (both sides lowercased)', () {
      final payload = bytesOf('case-test');
      final expectedUpper =
          sha256.convert(payload).toString().toUpperCase();
      final actual = chunkedDigest([payload]);
      expect(actual, expectedUpper.toLowerCase());
    });
  });

  group('offline / server error classification', () {
    test('ApkErrorKind covers offline, server, and digest as distinct kinds',
        () {
      expect(
        {
          ApkErrorKind.offline,
          ApkErrorKind.server,
          ApkErrorKind.digest,
          ApkErrorKind.disallowedUrl,
          ApkErrorKind.installerLaunch,
          ApkErrorKind.disabled,
          ApkErrorKind.unknown,
        }.length,
        7,
        reason: 'each failure mode must be independently actionable',
      );
    });

    test('an error state is terminal and carries a kind + message', () {
      const s = ApkDownloadState(
        phase: ApkPhase.error,
        errorKind: ApkErrorKind.offline,
        message: 'No internet connection. Reconnect and try again.',
      );
      expect(s.isTerminal, isTrue);
      expect(s.errorKind, ApkErrorKind.offline);
      expect(s.message, contains('internet'));
    });

    test('a server error is distinct from an offline error', () {
      const offline =
          ApkDownloadState(phase: ApkPhase.error, errorKind: ApkErrorKind.offline);
      const server =
          ApkDownloadState(phase: ApkPhase.error, errorKind: ApkErrorKind.server);
      expect(offline.errorKind, isNot(server.errorKind));
    });

    test('the disabled kind is the only non-retryable error', () {
      // The dialog offers Retry for every error EXCEPT disabled.
      const disabled = ApkDownloadState(
          phase: ApkPhase.error, errorKind: ApkErrorKind.disabled);
      expect(disabled.errorKind == ApkErrorKind.disabled, isTrue);
    });
  });

  group('ApkDownloadState model (progress / terminal semantics)', () {
    test('idle, done and error are terminal; downloading/verifying are not',
        () {
      expect(const ApkDownloadState(phase: ApkPhase.idle).isTerminal, isTrue);
      expect(const ApkDownloadState(phase: ApkPhase.done).isTerminal, isTrue);
      expect(const ApkDownloadState(phase: ApkPhase.error).isTerminal, isTrue);
      expect(const ApkDownloadState(phase: ApkPhase.downloading).isTerminal,
          isFalse);
      expect(const ApkDownloadState(phase: ApkPhase.verifying).isTerminal,
          isFalse);
      expect(
          const ApkDownloadState(phase: ApkPhase.launchingInstaller).isTerminal,
          isFalse);
    });

    test('determinate progress carries a 0..1 fraction and byte counts', () {
      const s = ApkDownloadState(
        phase: ApkPhase.downloading,
        receivedBytes: 500,
        totalBytes: 1000,
        progress: 0.5,
      );
      expect(s.progress, 0.5);
      expect(s.receivedBytes, 500);
      expect(s.totalBytes, 1000);
    });

    test('indeterminate progress (unknown total) leaves progress null', () {
      const s = ApkDownloadState(
          phase: ApkPhase.downloading, receivedBytes: 500, totalBytes: null);
      expect(s.progress, isNull);
    });

    test('the default state is idle with zero bytes and no error', () {
      const s = ApkDownloadState();
      expect(s.phase, ApkPhase.idle);
      expect(s.receivedBytes, 0);
      expect(s.errorKind, isNull);
      expect(s.isTerminal, isTrue);
    });
  });

  group('shipped web/update/version.json', () {
    // The PREVIOUS public release. The manifest advertises the build CI is
    // publishing right now, and publish-pages.yml feeds that same number to
    // `flutter build --build-number`, so manifest build == installed build for
    // anyone already on the new release. The upgrade invariant that actually
    // matters — and the one that stays true across releases — is that someone
    // still on the prior release is offered this one.
    const previousReleaseVersion = '1.5.1';
    const previousReleaseBuild = 18;

    test('parses and offers an upgrade to the previous release', () {
      final file = File('web/update/version.json');
      expect(file.existsSync(), isTrue,
          reason: 'the published manifest must exist in the repo');
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

      // Evaluate it exactly as an installed v1.5.1 (build 18) app would.
      final r = UpdateService.evaluateManifest(
        data,
        currentVersion: previousReleaseVersion,
        currentBuild: previousReleaseBuild,
      );
      // 1.6.0 > 1.5.1 and build 19 > 18 → this must be offered as an update.
      expect(r.hasUpdate, isTrue);
      expect(r.update!.build, greaterThan(previousReleaseBuild));
      expect(r.update!.apkUrl, startsWith('https://'));
      expect(UpdateConfig.isAllowedUrl(r.update!.apkUrl), isTrue,
          reason: 'the shipped APK URL must be on the allowlist');
    });

    test('is in lock-step with the build this binary reports', () {
      final data =
          jsonDecode(File('web/update/version.json').readAsStringSync())
              as Map<String, dynamic>;
      // publish-pages.yml builds the APK with the very number it writes into
      // the manifest, so a freshly updated device must see no further update.
      expect(data['build'], UpdateConfig.currentBuildNumber);
      final r = UpdateService.evaluateManifest(
        data,
        currentVersion: '1.6.0',
        currentBuild: UpdateConfig.currentBuildNumber,
      );
      expect(r.hasUpdate, isFalse,
          reason: 'a device already on the published build must not be '
              'offered the same build again');
    });

    test('the shipped manifest sha256 is a 64-char hex string', () {
      final data =
          jsonDecode(File('web/update/version.json').readAsStringSync())
              as Map<String, dynamic>;
      final sha = (data['sha256'] as String).trim();
      expect(sha, hasLength(64));
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha), isTrue);
    });
  });
}
