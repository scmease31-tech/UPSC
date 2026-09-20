import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_fonts.dart';
import '../config/update_config.dart';
import 'apk_installer_service.dart';
import 'notification_service.dart';
import '../widgets/update_download_dialog.dart';

/// A newer release than the one installed, as described by version.json.
class UpdateInfo {
  final String version; // semantic version, e.g. "1.6.0"
  final int build; // monotonically increasing build number
  final String notes; // release notes / changelog
  final String apkUrl; // HTTPS download URL of the APK (allowlisted)
  final String sha256; // expected SHA-256 of the APK
  final int? sizeBytes; // optional expected size for a sanity check
  final bool mandatory; // optional: block "Later" when true

  const UpdateInfo({
    required this.version,
    required this.build,
    required this.notes,
    required this.apkUrl,
    required this.sha256,
    this.sizeBytes,
    this.mandatory = false,
  });
}

/// The outcome of [UpdateService.evaluateManifest]: a pure verdict on a decoded
/// `version.json` map. Exactly one meaningful state at a time —
///   • [update] non-null            → a newer, valid, allowlisted release,
///   • [error] non-null             → malformed / incomplete / off-allowlist,
///   • both null ([isUpToDate])     → parsed fine but not newer.
class ManifestEvaluation {
  final UpdateInfo? update;
  final String? error;

  /// True when [error] is a security rejection (off-allowlist APK URL) rather
  /// than a plain "incomplete manifest".
  final bool errorIsSecurity;

  const ManifestEvaluation.upgrade(UpdateInfo this.update)
      : error = null,
        errorIsSecurity = false;

  const ManifestEvaluation.failure(String this.error, {bool isSecurity = false})
      : update = null,
        errorIsSecurity = isSecurity;

  const ManifestEvaluation.upToDate()
      : update = null,
        error = null,
        errorIsSecurity = false;

  bool get hasUpdate => update != null;
  bool get isUpToDate => update == null && error == null;
}

/// ──────────────────────────────────────────────────────────────────────────────
/// UpdateService — DIRECT sideload in-app updater.
///
/// On launch AND resume it fetches a stable HTTPS `version.json` from GitHub
/// Pages, compares the installed build against it by semantic version PLUS a
/// monotonically increasing build number, and — when newer — surfaces a Frosted
/// Scholar banner + dialog + notification. Choosing "Update" downloads the APK
/// INSIDE the app (progress/cancel/retry, SHA-256 verified) and invokes the
/// Android SYSTEM installer. There is NO GitHub-page redirect and NO silent
/// install: the system installer always shows the final "Install?" prompt.
///
/// The whole flow is guarded by [UpdateConfig.sideloadUpdaterEnabled]; a future
/// Play Store build disables it entirely.
/// ──────────────────────────────────────────────────────────────────────────────
class UpdateService {
  UpdateService._();

  /// The pending update, once discovered. Held as a notifier so the persistent
  /// banner can react even if the launch dialog was dismissed or missed.
  static final ValueNotifier<UpdateInfo?> available = ValueNotifier<UpdateInfo?>(null);

  static bool _promptedThisSession = false;
  static String? _lastCheckError;

  /// Fetch version.json and compare with the installed build.
  /// Returns null when up to date, disabled, offline, or on web.
  static Future<UpdateInfo?> fetchLatest() async {
    if (kIsWeb || !UpdateConfig.sideloadUpdaterEnabled) return null;
    _lastCheckError = null;

    // Manifest URL must itself be on the allowlist.
    if (!UpdateConfig.isAllowedUrl(UpdateConfig.versionManifestUrl)) {
      _lastCheckError = 'Update source is not configured correctly.';
      return null;
    }

    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;
      final currentBuild =
          int.tryParse(info.buildNumber) ?? UpdateConfig.currentBuildNumber;

      final res = await http
          .get(Uri.parse(UpdateConfig.versionManifestUrl),
              headers: {'Accept': 'application/json', 'Cache-Control': 'no-cache'})
          .timeout(UpdateConfig.networkTimeout);

      if (res.statusCode != 200) {
        _lastCheckError = 'The update server returned error ${res.statusCode}.';
        return null;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;

      final result = evaluateManifest(
        data,
        currentVersion: currentVersion,
        currentBuild: currentBuild,
      );
      if (result.error != null) {
        _lastCheckError = result.error;
        if (result.errorIsSecurity) {
          debugPrint('Rejected off-allowlist APK URL: ${data['apkUrl']}');
        }
        return null;
      }
      if (result.update == null) {
        // Parsed cleanly, but not newer than the installed build.
        available.value = null;
        return null;
      }

      final update = result.update!;
      available.value = update;
      await NotificationService.showUpdateAvailable(version: update.version);
      return update;
    } catch (error) {
      _lastCheckError = 'Could not reach the update server. Check your internet connection.';
      debugPrint('Update check failed: $error');
      return null;
    }
  }

  /// Called after main navigation mounts and on resume. Surfaces the dialog the
  /// first time an update is seen this session; the banner keeps it reachable.
  static Future<void> checkForUpdate(BuildContext context) async {
    final update = await fetchLatest();
    if (update == null || _promptedThisSession) return;
    _promptedThisSession = true;
    if (!context.mounted) return;
    promptUpdate(context, update);
  }

  /// Manual "Check for updates" — always reports an outcome.
  static Future<void> checkNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!UpdateConfig.sideloadUpdaterEnabled) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Updates are delivered through the app store on this build.')));
      return;
    }
    final update = await fetchLatest();
    if (!context.mounted) return;

    if (update == null) {
      if (_lastCheckError != null) {
        messenger.showSnackBar(SnackBar(content: Text(_lastCheckError!)));
        return;
      }
      final info = await PackageInfo.fromPlatform();
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('You are on the latest version (${info.version}).')),
      );
      return;
    }
    promptUpdate(context, update);
  }

  /// Show the Frosted Scholar update dialog for a discovered update.
  static void promptUpdate(BuildContext context, UpdateInfo update) {
    _showUpdateDialog(context, update);
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  /// Pure, side-effect-free evaluation of a decoded `version.json` map against
  /// the installed build. This is the exact decision logic [fetchLatest] runs;
  /// it is public so the manifest-parse, version/build comparison and
  /// allowlist rules can be unit-tested without a network call or platform
  /// channels.
  ///
  /// Returns a [ManifestEvaluation] with exactly one of:
  ///   • [ManifestEvaluation.update] set  → a newer, valid, allowlisted update,
  ///   • [ManifestEvaluation.error] set   → malformed / incomplete / off-list,
  ///   • both null                        → parsed cleanly but not newer.
  static ManifestEvaluation evaluateManifest(
    Map<String, dynamic> data, {
    required String currentVersion,
    required int currentBuild,
  }) {
    final remoteVersion = (data['version'] as String? ?? '').trim();
    final remoteBuild = _asInt(data['build']);
    final apkUrl = (data['apkUrl'] as String? ?? '').trim();
    final sha = (data['sha256'] as String? ?? '').trim();

    if (remoteVersion.isEmpty || remoteBuild == null || apkUrl.isEmpty || sha.isEmpty) {
      return const ManifestEvaluation.failure('The update information was incomplete.');
    }

    // Reject a manifest that points the APK at a non-allowlisted origin.
    if (!UpdateConfig.isAllowedUrl(apkUrl)) {
      return const ManifestEvaluation.failure(
        'Update blocked: the download link is not an approved source.',
        isSecurity: true,
      );
    }

    // Newer if EITHER the build number increased OR the semantic version did.
    // The build number is authoritative (monotonic); the semver is a
    // human-facing tie-break / display value.
    final isNewer =
        remoteBuild > currentBuild || isSemverNewer(remoteVersion, currentVersion);
    if (!isNewer) {
      return const ManifestEvaluation.upToDate();
    }

    return ManifestEvaluation.upgrade(UpdateInfo(
      version: remoteVersion,
      build: remoteBuild,
      notes: data['notes'] as String? ?? '',
      apkUrl: apkUrl,
      sha256: sha,
      sizeBytes: _asInt(data['sizeBytes']),
      mandatory: data['mandatory'] == true,
    ));
  }

  /// True when [remote] is a strictly higher semantic version than [local].
  /// Public for testing; used by [evaluateManifest].
  static bool isSemverNewer(String remote, String local) {
    final r = _semverParts(remote);
    final l = _semverParts(local);
    for (var i = 0; i < 3; i++) {
      if (r[i] > l[i]) return true;
      if (r[i] < l[i]) return false;
    }
    return false;
  }

  static List<int> _semverParts(String v) {
    // Strip a leading "v" and any build/pre-release suffix after "+" or "-".
    final core = v.replaceFirst(RegExp(r'^v'), '').split(RegExp(r'[-+]')).first;
    final parts = core.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts.sublist(0, 3);
  }

  // ── Frosted Scholar update dialog ──
  static void _showUpdateDialog(BuildContext context, UpdateInfo update) {
    showDialog<void>(
      context: context,
      barrierDismissible: !update.mandatory,
      builder: (ctx) => _FrostedScholarUpdateDialog(update: update),
    );
  }
}

/// Frosted-glass "Update Available" dialog. "Update" launches the in-app
/// download+install flow (never a browser redirect).
class _FrostedScholarUpdateDialog extends StatelessWidget {
  final UpdateInfo update;

  const _FrostedScholarUpdateDialog({required this.update});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00BFA6).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.system_update_rounded, color: Color(0xFF00BFA6), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Update Available',
                style: AppFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Version ${update.version} (build ${update.build}) is available.',
              style: AppFonts.inter(fontSize: 14, height: 1.5)),
          if (update.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: Text(update.notes,
                    style: AppFonts.inter(fontSize: 12, color: Colors.grey[700], height: 1.5)),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (!update.mandatory)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Later', style: AppFonts.inter(fontWeight: FontWeight.w600)),
          ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(context);
            // Reset any prior terminal state, then open the download dialog.
            ApkInstallerService.reset();
            showUpdateDownloadDialog(context, update);
          },
          icon: const Icon(Icons.download_rounded, size: 18),
          label: Text('Update', style: AppFonts.inter(fontWeight: FontWeight.w600)),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF00BFA6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}
