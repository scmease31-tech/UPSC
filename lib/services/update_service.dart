import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// A newer release than the one installed.
class UpdateInfo {
  final String version;
  final String notes;
  final String downloadUrl;

  const UpdateInfo({required this.version, required this.notes, required this.downloadUrl});
}

/// Checks GitHub Releases for a newer version and points the user at it.
class UpdateService {
  static const _owner = 'scmease31-tech';
  static const _repo = 'UPSC';
  static const _apkAsset = 'UPSC-Daily-Edge.apk';

  /// The pending update, once one has been found.
  ///
  /// Held as a notifier rather than only shown in a start-up dialog: a user who
  /// dismisses that dialog — or who never sees it because the check finished
  /// after they navigated away — still gets a persistent Update button in the
  /// Profile tab.
  static final ValueNotifier<UpdateInfo?> available = ValueNotifier<UpdateInfo?>(null);

  static bool _checkedThisSession = false;

  /// Fetch the latest release and compare it with the installed build.
  /// Returns null when up to date, offline, or on web.
  static Future<UpdateInfo?> fetchLatest() async {
    if (kIsWeb) return null;

    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version;

      final uri = Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases/latest');
      final res = await http
          .get(uri, headers: {'Accept': 'application/vnd.github.v3+json'})
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] as String? ?? '').replaceFirst('v', '');
      if (tag.isEmpty || !_isNewer(tag, current)) {
        available.value = null;
        return null;
      }

      // GitHub Pages URL gives a direct download with no redirect chain.
      final update = UpdateInfo(
        version: tag,
        notes: data['body'] as String? ?? '',
        downloadUrl: 'https://$_owner.github.io/$_repo/$_apkAsset',
      );
      available.value = update;
      return update;
    } catch (_) {
      // Best-effort: an update check must never break app start-up.
      return null;
    }
  }

  /// Called once after main navigation mounts. Surfaces the dialog the first
  /// time an update is seen in a session; the banner keeps it reachable after.
  static Future<void> checkForUpdate(BuildContext context) async {
    final update = await fetchLatest();
    if (update == null || _checkedThisSession) return;
    _checkedThisSession = true;
    if (!context.mounted) return;
    promptUpdate(context, update);
  }

  /// Show the update dialog for an already-discovered update.
  static void promptUpdate(BuildContext context, UpdateInfo update) {
    _showUpdateDialog(context, update.version, update.notes, update.downloadUrl);
  }

  /// Manual "Check for updates" — always reports an outcome to the user.
  static Future<void> checkNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final update = await fetchLatest();
    if (!context.mounted) return;

    if (update == null) {
      final info = await PackageInfo.fromPlatform();
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('You are on the latest version (${info.version}).')),
      );
      return;
    }
    promptUpdate(context, update);
  }

  static bool _isNewer(String remote, String local) {
    final r = remote.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final l = local.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    while (r.length < 3) r.add(0);
    while (l.length < 3) l.add(0);
    for (var i = 0; i < 3; i++) {
      if (r[i] > l[i]) return true;
      if (r[i] < l[i]) return false;
    }
    return false;
  }

  static void _showUpdateDialog(BuildContext context, String version, String notes, String downloadUrl) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
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
            Text('Version $version is available.',
                style: AppFonts.inter(fontSize: 14, height: 1.5)),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: Text(notes,
                      style: AppFonts.inter(fontSize: 12, color: Colors.grey[700], height: 1.5)),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Later', style: AppFonts.inter(fontWeight: FontWeight.w600)),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openReleasePage(context);
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text('Get Update', style: AppFonts.inter(fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00BFA6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the GitHub release page in the browser.
  ///
  /// This deliberately does NOT download or install an APK. Google Play's
  /// Device and Network Abuse policy prohibits apps that fetch and install
  /// packages from outside Play, and the REQUEST_INSTALL_PACKAGES permission it
  /// needed is a restricted permission Google does not grant to study apps.
  /// Sideload users still get told an update exists and can grab it manually;
  /// Play users are updated by Play itself.
  static Future<void> _openReleasePage(BuildContext context) async {
    final uri = Uri.parse('https://github.com/$_owner/$_repo/releases/latest');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {
      // fall through to the message below
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Could not open the release page. Visit github.com/$_owner/$_repo/releases',
          style: AppFonts.inter(fontSize: 13),
        ),
      ),
    );
  }
}
