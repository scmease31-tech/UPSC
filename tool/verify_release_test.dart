// End-to-end release check against the LIVE Pages endpoint.
//
// Everything else in test/ runs offline against fixtures. This one makes real
// HTTPS requests and pushes the actual published manifest through the app's own
// UpdateService.evaluateManifest, so it answers the question that matters after
// a release: would a real device on the previous version be offered this build,
// and would a device already on it be left alone?
//
// Lives under tool/ because it needs the network and the published release to
// exist, so it must not run in the ordinary suite. Run it after a publish:
//
//     flutter test tool/verify_release_test.dart
//
// flutter_test installs an HttpOverrides that fails every request, so this
// clears it for the duration.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:upsc_daily_edge/config/update_config.dart';
import 'package:upsc_daily_edge/services/update_service.dart';

/// The release before this one, as installed on a real device.
const _previousVersion = '1.5.1';
const _previousBuild = 18;

Future<Map<String, dynamic>> _fetch(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      fail('GET $url returned HTTP ${response.statusCode}');
    }
    final body = await response.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<HttpHeaders> _head(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.openUrl('HEAD', Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      fail('HEAD $url returned HTTP ${response.statusCode}');
    }
    await response.drain<void>();
    return response.headers;
  } finally {
    client.close();
  }
}

void main() {
  setUpAll(() {
    // Restore real networking; flutter_test's default override rejects all I/O.
    HttpOverrides.global = null;
  });

  late Map<String, dynamic> manifest;

  test('the published manifest is reachable at the configured URL', () async {
    manifest = await _fetch(UpdateConfig.versionManifestUrl);
    // ignore: avoid_print
    print('live manifest: ${jsonEncode(manifest)}');
    expect(manifest['version'], isA<String>());
    expect(manifest['build'], isA<int>());
  });

  test('a device on the previous release IS offered this build', () async {
    final r = UpdateService.evaluateManifest(
      manifest,
      currentVersion: _previousVersion,
      currentBuild: _previousBuild,
    );
    expect(r.error, isNull, reason: r.error);
    expect(r.hasUpdate, isTrue,
        reason: 'v$_previousVersion build $_previousBuild must see an update');
    expect(r.update!.version, '1.6.0');
    expect(r.update!.build, greaterThan(_previousBuild));
    // ignore: avoid_print
    print('offered: ${r.update!.version} build ${r.update!.build}');
  });

  test('a device already on this build is NOT prompted again', () async {
    final build = manifest['build'] as int;
    final r = UpdateService.evaluateManifest(
      manifest,
      currentVersion: manifest['version'] as String,
      currentBuild: build,
    );
    expect(r.hasUpdate, isFalse,
        reason: 'build $build must not be offered to itself — that would be a '
            'permanent update prompt');
  });

  test('the advertised APK is on the allowlist and is served', () async {
    final apkUrl = manifest['apkUrl'] as String;
    expect(UpdateConfig.isAllowedUrl(apkUrl), isTrue,
        reason: '$apkUrl is not an allowlisted origin');

    final headers = await _head(apkUrl);
    expect(headers.contentLength, manifest['sizeBytes'],
        reason: 'served APK size does not match the manifest');
  });

  test('the manifest digest is a well-formed SHA-256', () {
    final sha = (manifest['sha256'] as String).trim();
    expect(sha, hasLength(64));
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(sha.toLowerCase()), isTrue);
    expect(sha, isNot(RegExp(r'^0+$')),
        reason: 'placeholder digest was published');
  });

  test('the root download is the same binary the updater installs', () async {
    // The landing page links here. If it drifts from the manifest, new installs
    // get a different build from the one the updater manages.
    final root = manifest['apkUrl'].toString().replaceAll('/update/', '/');
    final headers = await _head(root);
    expect(headers.contentLength, manifest['sizeBytes'],
        reason: 'root download $root differs from the published APK');
  });

  test('the updater is enabled and can never install silently', () {
    expect(UpdateConfig.sideloadUpdaterEnabled, isTrue);
    expect(UpdateConfig.silentInstall, isFalse);
  });
}
