import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Checks GitHub Releases for a newer version, downloads in-app, and installs.
class UpdateService {
  static const _owner = 'sohildobariya31-blip';
  static const _repo = 'UPSC';
  static const _apkAsset = 'UPSC-Daily-Edge.apk';

  /// Call once after login / main navigation mounts.
  static Future<void> checkForUpdate(BuildContext context) async {
    if (kIsWeb) return;

    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version;

      final uri = Uri.parse(
          'https://api.github.com/repos/$_owner/$_repo/releases/latest');
      final res = await http.get(uri, headers: {'Accept': 'application/vnd.github.v3+json'});
      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] as String? ?? '').replaceFirst('v', '');
      if (tag.isEmpty) return;

      // Use GitHub Pages URL for reliable direct download (no redirect chain)
      const downloadUrl = 'https://sohildobariya31-blip.github.io/UPSC/$_apkAsset';

      if (_isNewer(tag, current) && context.mounted) {
        _showUpdateDialog(context, tag, data['body'] as String? ?? '', downloadUrl);
      }
    } catch (_) {
      // Silently fail — update check is best-effort
    }
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
              _downloadAndInstall(context, downloadUrl);
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

  /// Downloads the APK in-app with a progress dialog, then triggers install.
  static Future<void> _downloadAndInstall(BuildContext context, String url) async {
    final progress = ValueNotifier<double>(0);
    final status = ValueNotifier<String>('Connecting...');
    final cancelToken = CancelToken();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF00BFA6)),
              ),
              const SizedBox(width: 14),
              Text('Downloading Update',
                  style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (_, val, __) => Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: val > 0 ? val : null,
                        minHeight: 8,
                        backgroundColor: Colors.grey.withValues(alpha: 0.15),
                        color: const Color(0xFF00BFA6),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('${(val * 100).toStringAsFixed(0)}%',
                        style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: const Color(0xFF00BFA6))),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              ValueListenableBuilder<String>(
                valueListenable: status,
                builder: (_, msg, __) => Text(msg,
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancelToken.cancel('User cancelled');
                Navigator.pop(ctx);
              },
              child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );

    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/$_apkAsset';

      // Delete old file if exists
      final old = File(savePath);
      if (await old.exists()) await old.delete();

      final dio = Dio();
      dio.options.followRedirects = true;
      dio.options.maxRedirects = 5;
      dio.options.receiveTimeout = const Duration(minutes: 10);

      await dio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            progress.value = received / total;
            final mb = (received / 1024 / 1024).toStringAsFixed(1);
            final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
            status.value = '$mb / $totalMb MB';
          } else {
            final mb = (received / 1024 / 1024).toStringAsFixed(1);
            status.value = '$mb MB downloaded';
          }
        },
      );

      progress.value = 1.0;
      status.value = 'Installing...';

      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

      // Trigger APK install
      final result = await OpenFilex.open(savePath, type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open installer: ${result.message}')),
        );
      }
    } on DioException catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (e.type != DioExceptionType.cancel && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: ${e.message ?? "Network error"}')),
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    } finally {
      progress.dispose();
      status.dispose();
    }
  }
}
