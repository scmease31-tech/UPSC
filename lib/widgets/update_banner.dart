import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../config/app_fonts.dart';

import '../config/theme.dart';
import '../services/update_service.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// UpdateBanner — persistent "a newer version is available" card with an
/// Update button.
///
/// The start-up dialog is easy to miss or dismiss, which leaves people running
/// an old build with no way back to the prompt. This banner stays visible until
/// the update is actually installed, and renders nothing when the app is
/// current, so it costs nothing in the common case.
/// ──────────────────────────────────────────────────────────────────────────────
class UpdateBanner extends StatelessWidget {
  final EdgeInsets padding;

  /// Compact form for dense screens (single line, smaller button).
  final bool compact;

  const UpdateBanner({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 4),
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();

    return ValueListenableBuilder<UpdateInfo?>(
      valueListenable: UpdateService.available,
      builder: (context, update, __) {
        if (update == null) return const SizedBox.shrink();

        return Padding(
          padding: padding,
          child: Container(
            padding: EdgeInsets.all(compact ? 12 : 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00897B), Color(0xFF00BFA6)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.28),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.system_update_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Update available',
                        style: AppFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Version ${update.version} — tap to install',
                        style: AppFonts.inter(
                          fontSize: 11.5,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: () => UpdateService.promptUpdate(context, update),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primaryDark,
                    padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Update',
                    style: AppFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
