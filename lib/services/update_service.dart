import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Checks GitHub Releases for a newer version and prompts the user to update.
class UpdateService {
  static const _owner = 'sohildobariya31-blip';
  static const _repo = 'UPSC';
  static const _apkAsset = 'UPSC-Daily-Edge.apk';

  /// Call once after login / main navigation mounts.
  static Future<void> checkForUpdate(BuildContext context) async {
    if (kIsWeb) return; // web always gets latest on reload

    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version; // e.g. "1.0.0"

      final uri = Uri.parse(
          'https://api.github.com/repos/$_owner/$_repo/releases/latest');
      final res = await http.get(uri, headers: {'Accept': 'application/vnd.github.v3+json'});
      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] as String? ?? '').replaceFirst('v', '');
      if (tag.isEmpty) return;

      if (_isNewer(tag, current) && context.mounted) {
        _showUpdateDialog(context, tag, data['body'] as String? ?? '');
      }
    } catch (_) {
      // Silently fail — update check is best-effort
    }
  }

  /// Compare semver strings. Returns true if [remote] > [local].
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

  static void _showUpdateDialog(BuildContext context, String version, String notes) {
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
                  style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version $version is available.',
                style: GoogleFonts.inter(fontSize: 14, height: 1.5)),
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
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[700], height: 1.5)),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Later', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              final url = 'https://github.com/$_owner/$_repo/releases/latest/download/$_apkAsset';
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text('Update Now', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00BFA6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
