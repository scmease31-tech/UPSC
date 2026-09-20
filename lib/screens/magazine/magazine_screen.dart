import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../config/app_images.dart';
import '../../providers/study_provider.dart';
import '../../widgets/glass_widgets.dart';
import '../../models/weekly_magazine.dart';
import 'package:upsc_daily_edge/design_system/frosted_scholar.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// MagazineScreen — Weekly PDF magazine downloads with glassmorphic cards.
/// Migrated to the Frosted Scholar design system (tokens + primitives).
/// ──────────────────────────────────────────────────────────────────────────────
class MagazineScreen extends StatefulWidget {
  const MagazineScreen({super.key});

  @override
  State<MagazineScreen> createState() => _MagazineScreenState();
}

class _MagazineScreenState extends State<MagazineScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final study = context.watch<StudyProvider>();

    return GradientScaffold(
      showAppBar: false,
      child: SafeArea(
        child: Column(
          children: [
            _backBar(context),
            Expanded(
              child: study.isLoading
                  ? Center(child: Lottie.asset('assets/animations/loading.json', width: 120, height: 120))
                  : study.magazines.isEmpty
                      ? const FsEmptyState(
                          icon: Icons.auto_stories_outlined,
                          title: 'No magazines available',
                          message: 'Weekly compilations will appear here once published.',
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(
                              FsSpace.lg, FsSpace.xs, FsSpace.lg, 100),
                          itemCount: study.magazines.length,
                          itemBuilder: (context, i) => _buildMagCard(context, study.magazines[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _backBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xs, FsSpace.xs, FsSpace.lg, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
          ),
          Text('Weekly Magazine', style: FsType.title(context)),
        ],
      ),
    );
  }

  Widget _buildMagCard(BuildContext context, WeeklyMagazine mag) {
    final df = DateFormat('d MMM');
    final dateRange = '${df.format(mag.weekStartDate)} – ${df.format(mag.weekEndDate)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: FsSpace.md),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FsRadii.lg),
        child: Stack(
          children: [
            // Image and overlay fill whatever height the content needs, so the
            // banner adapts to width and font scale instead of a fixed height.
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: AppImages.magazineCover,
                fit: BoxFit.cover,
                placeholder: (_, __) => Shimmer.fromColors(
                  baseColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                  highlightColor: AppTheme.primaryColor.withValues(alpha: 0.04),
                  child: Container(color: Colors.white),
                ),
                errorWidget: (_, __, ___) => Container(
                  decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
                ),
              ),
            ),
            // Dark gradient overlay
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      AppTheme.primaryDark.withValues(alpha: 0.9),
                      AppTheme.accentViolet.withValues(alpha: 0.7),
                    ],
                  ),
                ),
              ),
            ),
            // Content defines the banner height; 148 is now a floor.
            Container(
              constraints: const BoxConstraints(minHeight: 148),
              padding: const EdgeInsets.symmetric(
                  horizontal: FsSpace.lg, vertical: FsSpace.md),
              child: Row(
                children: [
                  // Icon container
                  Container(
                    width: 64,
                    height: 84,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(FsRadii.card),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 28),
                        const SizedBox(height: FsSpace.xxs),
                        Text('PDF',
                            style: FsType.label(context).copyWith(color: Colors.white70)),
                      ],
                    ),
                  ),
                  const SizedBox(width: FsSpace.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: FsSpace.xs, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(FsRadii.sm),
                          ),
                          child: Text(dateRange,
                              style: FsType.label(context).copyWith(color: Colors.white70)),
                        ),
                        const SizedBox(height: FsSpace.xs),
                        Text(mag.title,
                            style: FsType.subtitle(context).copyWith(color: Colors.white),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: FsSpace.xxs),
                        Text(mag.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FsType.caption(context).copyWith(color: Colors.white70)),
                      ],
                    ),
                  ),
                  const SizedBox(width: FsSpace.md),
                  FsIconButton(
                    icon: Icons.download_rounded,
                    color: Colors.white,
                    size: 48,
                    tooltip: 'Download PDF',
                    onPressed: () => _openPdf(mag.pdfUrl),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPdf(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
