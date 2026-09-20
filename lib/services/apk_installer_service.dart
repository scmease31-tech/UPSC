import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../config/update_config.dart';

/// The phase of an in-app APK download + install.
enum ApkPhase { idle, downloading, verifying, launchingInstaller, done, error }

/// A category of failure the user can act on. Each maps to a clear message.
enum ApkErrorKind {
  /// No/failed network — retryable once back online.
  offline,

  /// The server answered but not with a usable APK (non-200, wrong size, empty).
  server,

  /// The downloaded bytes did not match the expected SHA-256 — do NOT install.
  digest,

  /// The APK URL is not on the HTTPS allowlist (spoofed/compromised manifest).
  disallowedUrl,

  /// The Android system installer could not be launched.
  installerLaunch,

  /// Called on a build/platform where the sideload updater is disabled.
  disabled,

  /// Unexpected local error (e.g. cannot write file).
  unknown,
}

/// Immutable snapshot of the download/install progress, exposed via a notifier
/// so the dialog can rebuild reactively.
@immutable
class ApkDownloadState {
  final ApkPhase phase;

  /// 0.0–1.0 when the total size is known, else null (indeterminate).
  final double? progress;
  final int receivedBytes;
  final int? totalBytes;
  final ApkErrorKind? errorKind;
  final String? message;

  const ApkDownloadState({
    this.phase = ApkPhase.idle,
    this.progress,
    this.receivedBytes = 0,
    this.totalBytes,
    this.errorKind,
    this.message,
  });

  bool get isTerminal =>
      phase == ApkPhase.done || phase == ApkPhase.error || phase == ApkPhase.idle;
}

/// ──────────────────────────────────────────────────────────────────────────────
/// ApkInstallerService — downloads the configured APK INSIDE the app, with
/// progress / cancel / retry, verifies its SHA-256, then invokes the Android
/// SYSTEM installer (which shows the mandatory final "Install?" confirmation —
/// there is NO silent install path here).
///
/// Every network URL is validated against [UpdateConfig.allowedOrigins] before
/// use, and the whole flow is a no-op unless [UpdateConfig.sideloadUpdaterEnabled].
/// ──────────────────────────────────────────────────────────────────────────────
class ApkInstallerService {
  ApkInstallerService._();

  /// Reactive state for the UI.
  static final ValueNotifier<ApkDownloadState> state =
      ValueNotifier<ApkDownloadState>(const ApkDownloadState());

  static http.Client? _client;
  static bool _cancelled = false;

  /// Cancel an in-flight download. Safe to call at any time.
  static void cancel() {
    _cancelled = true;
    _client?.close();
    _client = null;
    state.value = const ApkDownloadState(phase: ApkPhase.idle, message: 'Download cancelled.');
  }

  /// Download [url], verify it against [expectedSha256], then launch the system
  /// installer. [expectedSize] (bytes, optional) is used as an extra sanity
  /// check. Retry by simply calling this again.
  ///
  /// Guarded: does nothing on web or on a Play Store build.
  static Future<void> downloadAndInstall({
    required String url,
    required String expectedSha256,
    int? expectedSize,
  }) async {
    if (kIsWeb || !UpdateConfig.sideloadUpdaterEnabled) {
      state.value = const ApkDownloadState(
        phase: ApkPhase.error,
        errorKind: ApkErrorKind.disabled,
        message: 'In-app updates are not available in this build.',
      );
      return;
    }

    // Hard allowlist gate — reject before any network call.
    if (!UpdateConfig.isAllowedUrl(url)) {
      state.value = const ApkDownloadState(
        phase: ApkPhase.error,
        errorKind: ApkErrorKind.disallowedUrl,
        message: 'Update blocked: the download link is not an approved source.',
      );
      return;
    }

    _cancelled = false;
    _client = http.Client();
    state.value = const ApkDownloadState(phase: ApkPhase.downloading, progress: null);

    File? outFile;
    try {
      final dir = await getApplicationCacheDirectory();
      outFile = File('${dir.path}/upsc_update.apk');
      if (await outFile.exists()) {
        await outFile.delete();
      }

      final request = http.Request('GET', Uri.parse(url));
      final response =
          await _client!.send(request).timeout(UpdateConfig.networkTimeout);

      if (response.statusCode != 200) {
        _fail(ApkErrorKind.server,
            'The update server returned error ${response.statusCode}. Please try again later.');
        return;
      }

      final total = response.contentLength ?? expectedSize;
      final sink = outFile.openWrite();
      final digestOutput = _DigestCapture();
      final sha = sha256.startChunkedConversion(digestOutput);
      int received = 0;

      try {
        await for (final chunk in response.stream) {
          if (_cancelled) {
            return; // sink closed in finally; state set to idle by cancel()
          }
          received += chunk.length;
          sink.add(chunk);
          sha.add(chunk);
          state.value = ApkDownloadState(
            phase: ApkPhase.downloading,
            receivedBytes: received,
            totalBytes: total,
            progress: (total != null && total > 0) ? received / total : null,
          );
        }
      } finally {
        await sink.close();
      }

      if (_cancelled) return;

      if (received == 0) {
        _fail(ApkErrorKind.server, 'The downloaded update was empty. Please try again.');
        return;
      }
      if (expectedSize != null && received != expectedSize) {
        _fail(ApkErrorKind.server,
            'The downloaded update was incomplete. Check your connection and retry.');
        return;
      }

      // ── Verify SHA-256 ──
      state.value = ApkDownloadState(
        phase: ApkPhase.verifying,
        receivedBytes: received,
        totalBytes: total,
        progress: 1.0,
      );
      sha.close();
      final actual = digestOutput.value!.toString().toLowerCase();
      final expected = expectedSha256.trim().toLowerCase();
      if (expected.isEmpty || actual != expected) {
        await outFile.delete().catchError((_) => outFile!);
        _fail(ApkErrorKind.digest,
            'The update failed its security check and was discarded. It was not installed.');
        return;
      }

      // ── Hand to the Android SYSTEM installer ──
      // open_filex opens the APK with the system package installer, which shows
      // the MANDATORY final "Install?" confirmation. This is never silent.
      state.value = ApkDownloadState(
        phase: ApkPhase.launchingInstaller,
        receivedBytes: received,
        totalBytes: total,
        progress: 1.0,
      );
      final result = await OpenFilex.open(
        outFile.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        _fail(ApkErrorKind.installerLaunch,
            'Could not open the installer. Enable "Install unknown apps" for UPSC Daily Edge and retry.');
        return;
      }

      state.value = ApkDownloadState(
        phase: ApkPhase.done,
        receivedBytes: received,
        totalBytes: total,
        progress: 1.0,
      );
    } on TimeoutException {
      _fail(ApkErrorKind.offline,
          'The download timed out. Check your internet connection and try again.');
    } on SocketException {
      _fail(ApkErrorKind.offline,
          'No internet connection. Reconnect and try again.');
    } on http.ClientException {
      if (_cancelled) return; // client.close() during cancel throws here
      _fail(ApkErrorKind.offline,
          'The connection was interrupted. Check your internet and retry.');
    } catch (error) {
      _fail(ApkErrorKind.unknown, 'The update could not be completed. Please try again.');
      debugPrint('APK install failed: $error');
    } finally {
      _client?.close();
      _client = null;
    }
  }

  static void _fail(ApkErrorKind kind, String message) {
    state.value = ApkDownloadState(phase: ApkPhase.error, errorKind: kind, message: message);
  }

  /// Reset back to idle (e.g. after the user dismisses a terminal state).
  static void reset() {
    _cancelled = false;
    state.value = const ApkDownloadState();
  }
}

/// A tiny [Sink] that captures the single [Digest] emitted when the chunked
/// SHA-256 conversion is closed. Avoids depending on `package:convert`'s
/// `AccumulatorSink`.
class _DigestCapture implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
