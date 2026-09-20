import 'package:flutter/material.dart';

import '../config/app_fonts.dart';
import '../config/theme.dart';
import '../services/apk_installer_service.dart';
import '../services/update_service.dart';

/// Opens the Frosted Scholar download/install dialog and kicks off the download.
void showUpdateDownloadDialog(BuildContext context, UpdateInfo update) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdateDownloadDialog(update: update),
  );
  // Start immediately.
  ApkInstallerService.downloadAndInstall(
    url: update.apkUrl,
    expectedSha256: update.sha256,
    expectedSize: update.sizeBytes,
  );
}

/// ──────────────────────────────────────────────────────────────────────────────
/// Reactive download + install dialog. Shows a progress bar with cancel while
/// downloading, a verifying step, "opening installer" while the system prompt
/// launches, and clear offline / server / digest error messages with a Retry.
///
/// Public so it can be widget-tested directly against a driven
/// [ApkInstallerService.state]; production code reaches it via
/// [showUpdateDownloadDialog], which also starts the download.
/// ──────────────────────────────────────────────────────────────────────────────
class UpdateDownloadDialog extends StatelessWidget {
  final UpdateInfo update;

  const UpdateDownloadDialog({super.key, required this.update});

  String _fmtBytes(int b) {
    if (b <= 0) return '0 MB';
    final mb = b / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ApkDownloadState>(
      valueListenable: ApkInstallerService.state,
      builder: (context, s, _) {
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
                child: Icon(_titleIcon(s.phase), color: const Color(0xFF00BFA6), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_titleText(s.phase),
                    style: AppFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          content: _buildContent(context, s),
          actions: _buildActions(context, s),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, ApkDownloadState s) {
    switch (s.phase) {
      case ApkPhase.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_errorIcon(s.errorKind), color: AppTheme.errorRed, size: 32),
            const SizedBox(height: 10),
            Text(s.message ?? 'The update could not be completed.',
                style: AppFonts.inter(fontSize: 14, height: 1.5)),
          ],
        );
      case ApkPhase.verifying:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LinearProgressIndicator(value: 1.0),
            const SizedBox(height: 12),
            Text('Verifying update…',
                style: AppFonts.inter(fontSize: 13, color: Colors.grey[700])),
          ],
        );
      case ApkPhase.launchingInstaller:
      case ApkPhase.done:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Opening the Android installer…',
                style: AppFonts.inter(fontSize: 14, height: 1.5)),
            const SizedBox(height: 6),
            Text('Confirm the install on the system prompt to finish updating.',
                style: AppFonts.inter(fontSize: 12, color: Colors.grey[600], height: 1.4)),
          ],
        );
      case ApkPhase.downloading:
      default:
        final pct = s.progress;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: pct),
            const SizedBox(height: 10),
            Text(
              pct != null
                  ? 'Downloading ${(pct * 100).toStringAsFixed(0)}%  •  ${_fmtBytes(s.receivedBytes)}${s.totalBytes != null ? ' / ${_fmtBytes(s.totalBytes!)}' : ''}'
                  : 'Downloading…  ${_fmtBytes(s.receivedBytes)}',
              style: AppFonts.inter(fontSize: 13, color: Colors.grey[700]),
            ),
          ],
        );
    }
  }

  List<Widget> _buildActions(BuildContext context, ApkDownloadState s) {
    switch (s.phase) {
      case ApkPhase.error:
        final canRetry = s.errorKind != ApkErrorKind.disabled;
        return [
          TextButton(
            onPressed: () {
              ApkInstallerService.reset();
              Navigator.pop(context);
            },
            child: Text('Close', style: AppFonts.inter(fontWeight: FontWeight.w600)),
          ),
          if (canRetry)
            FilledButton.icon(
              onPressed: () {
                ApkInstallerService.downloadAndInstall(
                  url: update.apkUrl,
                  expectedSha256: update.sha256,
                  expectedSize: update.sizeBytes,
                );
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('Retry', style: AppFonts.inter(fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00BFA6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
        ];
      case ApkPhase.launchingInstaller:
      case ApkPhase.done:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Done', style: AppFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ];
      case ApkPhase.verifying:
        return const [];
      case ApkPhase.downloading:
      default:
        return [
          TextButton(
            onPressed: () {
              ApkInstallerService.cancel();
              Navigator.pop(context);
            },
            child: Text('Cancel', style: AppFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ];
    }
  }

  IconData _titleIcon(ApkPhase p) {
    switch (p) {
      case ApkPhase.error:
        return Icons.error_outline_rounded;
      case ApkPhase.verifying:
        return Icons.verified_user_rounded;
      case ApkPhase.launchingInstaller:
      case ApkPhase.done:
        return Icons.install_mobile_rounded;
      default:
        return Icons.download_rounded;
    }
  }

  String _titleText(ApkPhase p) {
    switch (p) {
      case ApkPhase.error:
        return 'Update Failed';
      case ApkPhase.verifying:
        return 'Verifying';
      case ApkPhase.launchingInstaller:
      case ApkPhase.done:
        return 'Install Update';
      default:
        return 'Downloading Update';
    }
  }

  IconData _errorIcon(ApkErrorKind? kind) {
    switch (kind) {
      case ApkErrorKind.offline:
        return Icons.wifi_off_rounded;
      case ApkErrorKind.digest:
      case ApkErrorKind.disallowedUrl:
        return Icons.gpp_bad_rounded;
      case ApkErrorKind.server:
        return Icons.cloud_off_rounded;
      case ApkErrorKind.installerLaunch:
        return Icons.app_blocking_rounded;
      default:
        return Icons.error_outline_rounded;
    }
  }
}
