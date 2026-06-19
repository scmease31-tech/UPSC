import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
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

/// ──────────────────────────────────────────────────────────────────────────────
/// MagazineScreen — Weekly PDF magazine downloads with glassmorphic cards.
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
                      ? Center(child: Text('No magazines available', style: GoogleFonts.inter(color: AppTheme.textS(context))))
                      : ListView.builder(
                          controller: _scrollController,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
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
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios_rounded), onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          }),
          Text('Weekly Magazine', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
        ],
      ),
    );
  }

  Widget _buildMagCard(BuildContext context, WeeklyMagazine mag) {
    final df = DateFormat('d MMM');
    final dateRange = '${df.format(mag.weekStartDate)} – ${df.format(mag.weekEndDate)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Background image
            SizedBox(
              height: 160,
              width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: AppImages.magazineCover,
                fit: BoxFit.cover,
                placeholder: (_, __) => Shimmer.fromColors(
                  baseColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                  highlightColor: AppTheme.primaryColor.withValues(alpha: 0.04),
                  child: Container(color: Colors.white),
                ),
                errorWidget: (_, __, ___) => Container(
                  decoration: BoxDecoration(gradient: AppTheme.heroGradient),
                ),
              ),
            ),
            // Dark gradient overlay
            Container(
              height: 160,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft, end: Alignment.centerRight,
                  colors: [
                    AppTheme.primaryDark.withValues(alpha: 0.9),
                    AppTheme.accentViolet.withValues(alpha: 0.7),
                  ],
                ),
              ),
            ),
            // Content
            Container(
              height: 160,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  // Icon container
                  Container(
                        width: 64, height: 84,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 28),
                            const SizedBox(height: 4),
                            Text('PDF', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white70)),
                          ],
                        ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(dateRange, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white70)),
                        ),
                        const SizedBox(height: 6),
                        Text(mag.title, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        Text(mag.description, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => _openPdf(mag.pdfUrl),
                    child: Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: const Icon(Icons.download_rounded, color: Colors.white, size: 22),
                    ),
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
